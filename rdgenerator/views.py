import io
from pathlib import Path
from django.http import HttpResponse, JsonResponse, HttpResponseForbidden
from django.shortcuts import render, get_object_or_404
from django.core.files.base import ContentFile
import os
import secrets
import re
import requests
import base64
import json
import uuid
import pyzipper
from django.conf import settings as _settings
from django.db.models import Q
from .forms import GenerateForm, HEX_COLOR_RE
from .models import GithubRun
from PIL import Image
from urllib.parse import quote

# get_png, download and save_custom_client build file paths from request values;
# only accept a UUID and a plain file name so "../" or absolute paths cannot escape png/ and exe/.
_UUID_RE = re.compile(r'^[0-9a-fA-F-]{36}$')
_NAME_RE = re.compile(r'^[\w.-]+$')

def _safe_parts(uuid_val, filename):
    if not uuid_val or not _UUID_RE.match(uuid_val):
        return False
    if filename is not None and (not _NAME_RE.match(filename) or filename.startswith('.')):
        return False
    return True


def _norm_hex_color(value):
    """Return canonical #RRGGBB, or '' for blank/invalid (stock color).

    The workflows receive this as a step env var and interpolate it into Dart
    0xAARRGGBB literals, so nothing but validated hex may reach them.
    """
    value = value if isinstance(value, str) else ''
    value = value.strip()
    if not value or not HEX_COLOR_RE.match(value):
        return ''
    return '#' + value.lstrip('#').upper()


def get_full_url(request):
    """URL the GitHub workflow uses to reach this server. GENURL wins over the
    request host, which can be an internal address behind a reverse proxy."""
    if _settings.GENURL:
        genurl = _settings.GENURL.rstrip('/')
        if '://' in genurl:
            return genurl
        return f"{_settings.PROTOCOL}://{genurl}"
    return f"{_settings.PROTOCOL}://{request.get_host()}"


def generate_custom_client(params, full_url):
    """
    Core generation logic shared by web form and JSON API.

    Args:
        params: dict containing all configuration fields (keys match GenerateForm field names)
        full_url: the full URL of this service (protocol + host)

    Returns:
        dict with 'success' key. On success: also includes 'uuid', 'filename', 'platform', 'log_url'.
        On failure: includes 'error' and optionally 'status_code'.
    """
    user_secret = params.get('sh_secret_field', '')
    selfhosted = (_settings.SH_SECRET == user_secret)
    platform = params.get('platform', 'windows')
    version = params.get('version', '1.5.3')
    app_version = params.get('app_version', '')
    # app_version overrides the version string embedded in the built client
    # without changing the git tag that version selects. If left empty, the
    # RustDesk build's own version (from the checked-out tag) is used.
    delayFix = params.get('delayFix', True)
    xOffline = params.get('xOffline', False)
    hidecm = params.get('hidecm', False)
    removeNewVersionNotif = params.get('removeNewVersionNotif', False)
    update_public_key = params.get('update_public_key', '')
    # If a custom update public key is provided, force the "remove new version
    # notification" behaviour off so the client keeps checking for updates via
    # the self-hosted update URL instead.
    if update_public_key:
        removeNewVersionNotif = False
    server = params.get('serverIP', '')
    serverPort = params.get('serverPort', '')
    key = params.get('key', '')
    apiServer = params.get('apiServer', '')
    urlLink = params.get('urlLink', '')
    downloadLink = params.get('downloadLink', '')
    if not server:
        server = 'rs-ny.rustdesk.com' #default rustdesk server
    if not serverPort:
        serverPort = '21116' #default rustdesk rendezvous port
    if not key:
        key = 'OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=' #default rustdesk key
    if not apiServer:
        apiServer = server+":21114"
    if not urlLink:
        urlLink = "https://rustdesk.com"
    if not downloadLink:
        downloadLink = "https://rustdesk.com/download"
    direction = params.get('direction', 'both')
    installation = params.get('installation', 'installationY')
    settings = params.get('settings', 'settingsY')
    appname_display = params.get('appname', '')
    if not appname_display:
        appname_display = "rustdesk"
    appname = re.sub(r"[:|\\/]", "", appname_display).replace(" ", "")
    filename = params.get('exename', 'rustdesk')
    compname = params.get('compname', '')
    if not compname:
        compname = "Purslane Ltd"
    androidappid = params.get('androidappid', '')
    if not androidappid:
        androidappid = "com.carriez.flutter_hbb"
    compname = compname.replace("&","\\&")
    permPass = params.get('permanentPassword', '')
    theme = params.get('theme', 'system')
    themeDorO = params.get('themeDorO', 'default')
    # Optional Flutter theme colours; blank means "leave the stock colour".
    themeColor = _norm_hex_color(params.get('themeColor', ''))
    themeSurfaceLight = _norm_hex_color(params.get('themeSurfaceLight', ''))
    themeSurfaceDark = _norm_hex_color(params.get('themeSurfaceDark', ''))
    themeMeColor = _norm_hex_color(params.get('themeMeColor', ''))
    passApproveMode = params.get('passApproveMode', 'password-click')
    denyLan = params.get('denyLan', False)
    enableDirectIP = params.get('enableDirectIP', False)
    autoClose = params.get('autoClose', False)
    permissionsType = params.get('permissionsType', 'custom')
    enableKeyboard = params.get('enableKeyboard', True)
    enableClipboard = params.get('enableClipboard', True)
    enableFileTransfer = params.get('enableFileTransfer', True)
    enableAudio = params.get('enableAudio', True)
    enableTCP = params.get('enableTCP', True)
    enableRemoteRestart = params.get('enableRemoteRestart', True)
    enableRecording = params.get('enableRecording', True)
    enableBlockingInput = params.get('enableBlockingInput', True)
    enableRemoteModi = params.get('enableRemoteModi', False)
    removeWallpaper = params.get('removeWallpaper', True)
    defaultManual = params.get('defaultManual', '')
    overrideManual = params.get('overrideManual', '')
    enablePrinter = params.get('enablePrinter', True)
    enableCamera = params.get('enableCamera', True)
    enableTerminal = params.get('enableTerminal', True)

    if all(char.isascii() for char in filename):
        filename = re.sub(r'[^\w\s-]', '_', filename).strip()
        filename = filename.replace(" ","_")
    else:
        filename = "rustdesk"
    if not all(char.isascii() for char in appname):
        appname = "rustdesk"
    # Treat "RustDesk" as the default name too, so the app-name key and the
    # workflow's directory rename stay in sync.
    if appname.lower() == "rustdesk":
        appname = "rustdesk"
    myuuid = str(uuid.uuid4())

    try:
        iconfile = params.get('iconfile')
        if not iconfile:
            iconfile = params.get('iconbase64')
        iconlink_url, iconlink_uuid, iconlink_file = save_png(iconfile,myuuid,full_url,"icon.png")
    except:
        print("failed to get icon, using default")
        iconlink_url = "false"
        iconlink_uuid = "false"
        iconlink_file = "false"
    try:
        logofile = params.get('logofile')
        if not logofile:
            logofile = params.get('logobase64')
        logolink_url, logolink_uuid, logolink_file = save_png(logofile,myuuid,full_url,"logo.png")
    except:
        print("failed to get logo")
        logolink_url = "false"
        logolink_uuid = "false"
        logolink_file = "false"
    try:
        privacyfile = params.get('privacyfile')
        if not privacyfile:
            privacyfile = params.get('privacybase64')
        privacylink_url, privacylink_uuid, privacylink_file = save_png(privacyfile,myuuid,full_url,"privacy.png")
    except:
        print("failed to get logo")
        privacylink_url = "false"
        privacylink_uuid = "false"
        privacylink_file = "false"

    ###create the custom.txt json here and send in as inputs below
    decodedCustom = {}
    if direction != "both":
        decodedCustom['conn-type'] = direction
    if installation == "installationN":
        decodedCustom['disable-installation'] = 'Y'
    if settings == "settingsN":
        decodedCustom['disable-settings'] = 'Y'
    if appname.lower() != "rustdesk":
        decodedCustom['app-name'] = appname_display

    # Permissions and security settings are enforced (override) so they also
    # apply on machines that already have a saved RustDesk configuration.
    # Anything placed in default-settings loses to a value the user (or a
    # previous installation) already stored.
    decodedCustom['override-settings'] = {}
    decodedCustom['default-settings'] = {}
    override = decodedCustom['override-settings']

    if permPass != "":
        decodedCustom['password'] = permPass

    if theme != "system":
        if themeDorO == "default":
            if platform == "windows-x86":
                decodedCustom['default-settings']['allow-darktheme'] = 'Y' if theme == "dark" else 'N'
            else:
                decodedCustom['default-settings']['theme'] = theme
        elif themeDorO == "override":
            if platform == "windows-x86":
                decodedCustom['override-settings']['allow-darktheme'] = 'Y' if theme == "dark" else 'N'
            else:
                decodedCustom['override-settings']['theme'] = theme

    # enable-lan-discovery and allow-auto-disconnect are read through
    # Config::get_option, so they must live in a settings map.  A top-level
    # key would only land in HARD_SETTINGS and be ignored by get_option.
    override['enable-lan-discovery'] = 'N' if denyLan else 'Y'
    override['allow-auto-disconnect'] = 'Y' if autoClose else 'N'

    # The permission checkboxes are disabled by the form for "full" and
    # "view", so disabled inputs are not submitted.  Derive those two modes
    # explicitly instead of trusting the missing parameters.
    if permissionsType == "full":
        enableKeyboard = enableClipboard = enableFileTransfer = True
        enableAudio = enableTCP = enableRemoteRestart = enableRecording = True
        enableBlockingInput = enableRemoteModi = True
        enablePrinter = enableCamera = enableTerminal = True
    elif permissionsType == "view":
        enableKeyboard = enableClipboard = enableFileTransfer = False
        enableAudio = enableTCP = enableRemoteRestart = enableRecording = False
        enableBlockingInput = enableRemoteModi = False
        enablePrinter = enableCamera = enableTerminal = False

    override['access-mode'] = permissionsType
    override['enable-keyboard'] = 'Y' if enableKeyboard else 'N'
    override['enable-clipboard'] = 'Y' if enableClipboard else 'N'
    override['enable-file-transfer'] = 'Y' if enableFileTransfer else 'N'
    override['enable-audio'] = 'Y' if enableAudio else 'N'
    override['enable-tunnel'] = 'Y' if enableTCP else 'N'
    override['enable-remote-restart'] = 'Y' if enableRemoteRestart else 'N'
    override['enable-record-session'] = 'Y' if enableRecording else 'N'
    override['enable-block-input'] = 'Y' if enableBlockingInput else 'N'
    override['allow-remote-config-modification'] = 'Y' if enableRemoteModi else 'N'
    override['direct-server'] = 'Y' if enableDirectIP else 'N'
    # A baked permanent password is authoritative: make it the permanent
    # password method instead of silently leaving "both passwords" enabled.
    override['verification-method'] = 'use-permanent-password' if permPass else 'use-both-passwords'
    # hide_cm() only returns true with approve-mode=password and a permanent
    # password, so do not advertise the feature when it cannot work.
    effective_hidecm = bool(hidecm and permPass)
    override['approve-mode'] = 'password' if effective_hidecm else passApproveMode
    override['allow-hide-cm'] = 'Y' if effective_hidecm else 'N'
    override['allow-remove-wallpaper'] = 'Y' if removeWallpaper else 'N'
    override['enable-remote-printer'] = 'Y' if enablePrinter else 'N'
    override['enable-camera'] = 'Y' if enableCamera else 'N'
    override['enable-terminal'] = 'Y' if enableTerminal else 'N'
    if direction == 'incoming':
        override['custom-rendezvous-server'] = server
        override['api-server'] = apiServer

    # Some keys are only read from HARD_SETTINGS and never from a
    # default-settings/override-settings map.  Route those to the top level
    # when an advanced user enters them in either manual box.
    hard_custom_keys = {
        'conn-type',
        'password',
        'salt',
        'app-name',
        'disable-installation',
        'disable-settings',
        'disable-tcp-listen',
        'disable-ab',
        'disable-account',
    }

    def apply_manual_settings(lines, target):
        for line in lines.splitlines():
            if '=' in line:
                k, value = line.split('=', 1)
                k = k.strip()
                value = value.strip()
                if k in hard_custom_keys:
                    decodedCustom[k] = value
                else:
                    target[k] = value

    if defaultManual:
        apply_manual_settings(defaultManual, decodedCustom['default-settings'])

    if overrideManual:
        apply_manual_settings(overrideManual, decodedCustom['override-settings'])
    
    decodedCustomJson = json.dumps(decodedCustom)

    string_bytes = decodedCustomJson.encode("ascii")
    base64_bytes = base64.b64encode(string_bytes)
    encodedCustom = base64_bytes.decode("ascii")

    ####from here run the github action, we need user, repo, access token.
    if platform == 'windows':
        url = 'https://api.github.com/repos/'+_settings.GHUSER+'/'+_settings.REPONAME+'/actions/workflows/generator-windows.yml/dispatches'
        if selfhosted:
            url = 'https://api.github.com/repos/'+_settings.GHUSER+'/'+_settings.REPONAME+'/actions/workflows/sh-generator-windows.yml/dispatches'
    if platform == 'windows-x86':
        url = 'https://api.github.com/repos/'+_settings.GHUSER+'/'+_settings.REPONAME+'/actions/workflows/generator-windows-x86.yml/dispatches'
    elif platform == 'linux':
        url = 'https://api.github.com/repos/'+_settings.GHUSER+'/'+_settings.REPONAME+'/actions/workflows/generator-linux.yml/dispatches'
    elif platform == 'android':
        url = 'https://api.github.com/repos/'+_settings.GHUSER+'/'+_settings.REPONAME+'/actions/workflows/generator-android.yml/dispatches'
    elif platform == 'macos':
        url = 'https://api.github.com/repos/'+_settings.GHUSER+'/'+_settings.REPONAME+'/actions/workflows/generator-macos.yml/dispatches'
    else:
        url = 'https://api.github.com/repos/'+_settings.GHUSER+'/'+_settings.REPONAME+'/actions/workflows/generator-windows.yml/dispatches'
        if selfhosted:
            url = 'https://api.github.com/repos/'+_settings.GHUSER+'/'+_settings.REPONAME+'/actions/workflows/sh-generator-windows.yml/dispatches'

    inputs_raw = {
        "server":server,
        "serverPort":serverPort,
        "key":key,
        "apiServer":apiServer,
        "custom":encodedCustom,
        "uuid":myuuid,
        "iconlink_url":iconlink_url,
        "iconlink_uuid":iconlink_uuid,
        "iconlink_file":iconlink_file,
        "logolink_url":logolink_url,
        "logolink_uuid":logolink_uuid,
        "logolink_file":logolink_file,
        "privacylink_url":privacylink_url,
        "privacylink_uuid":privacylink_uuid,
        "privacylink_file":privacylink_file,
        "appname":appname,
        "genurl":_settings.GENURL,
        "themeColor": themeColor,
        "themeSurfaceLight": themeSurfaceLight,
        "themeSurfaceDark": themeSurfaceDark,
        "themeMeColor": themeMeColor,
        "urlLink":urlLink,
        "downloadLink":downloadLink,
        "delayFix": 'true' if delayFix else 'false',
        "rdgen":'true',
        "xOffline": 'true' if xOffline else 'false',
        "removeNewVersionNotif": 'true' if removeNewVersionNotif else 'false',
        "update_public_key": update_public_key,
        "compname": compname,
        "androidappid":androidappid,
        "filename":filename
    }

    temp_json_path = f"data_{uuid.uuid4()}.json"
    zip_filename = f"secrets_{uuid.uuid4()}.zip"
    zip_path = "temp_zips/%s" % (zip_filename)
    Path("temp_zips").mkdir(parents=True, exist_ok=True)

    with open(temp_json_path, "w") as f:
        json.dump(inputs_raw, f)

    with pyzipper.AESZipFile(zip_path, 'w', compression=pyzipper.ZIP_LZMA, encryption=pyzipper.WZ_AES) as zf:
        zf.setpassword(_settings.ZIP_PASSWORD.encode())
        zf.write(temp_json_path, arcname="secrets.json")

    if os.path.exists(temp_json_path):
        os.remove(temp_json_path)

    zipJson = {}
    zipJson['url'] = full_url
    zipJson['file'] = zip_filename

    zip_url = json.dumps(zipJson)

    data = {
        "ref":_settings.GHBRANCH,
        "inputs":{
            "version":version,
            "app_version":app_version,
            "zip_url":zip_url
        },
        "return_run_details": True
    } 
    headers = {
        'Accept':  'application/vnd.github+json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer '+_settings.GHBEARER,
        'X-GitHub-Api-Version': '2026-03-10'
    }
    new_github_run = GithubRun(
        uuid=myuuid,
        status="Starting generator...please wait"
    )
    try:
        response = requests.post(url, json=data, headers=headers)
        if response.status_code == 204 or response.status_code == 200:
            github_data = response.json()
            print(github_data)
            new_github_run.github_run_id = github_data.get('workflow_run_id')
            new_github_run.status = "in_progress"
            new_github_run.save()

            return {
                "success": True,
                "uuid": myuuid,
                "filename": filename,
                "platform": platform,
                "log_url": github_data.get('html_url')
            }
        else:
            return {
                "success": False,
                "error": "GitHub rejected the start request",
                "status_code": 500
            }
    except Exception as e:
        return {
            "success": False,
            "error": f"Connection error: {str(e)}",
            "status_code": 500
        }


def _get_run_status(uuid_val):
    """
    Core status-check logic shared by web form and JSON API.

    Args:
        uuid_val: the UUID string of the generation run

    Returns:
        dict with 'found', 'status', 'github_log_url', and optionally 'gh_run'.
        If not found, 'found' is False.
    """
    try:
        gh_run = GithubRun.objects.get(uuid=uuid_val)
    except GithubRun.DoesNotExist:
        return {"found": False}

    github_log_url = f"https://github.com/{_settings.GHUSER}/{_settings.REPONAME}/actions/runs/{gh_run.github_run_id}"

    if gh_run.status not in ['success', 'failure', 'cancelled', 'timed_out', 'skipped']:
        headers = {
            "Authorization": f"Bearer {_settings.GHBEARER}",
            "Accept": "application/vnd.github+json"
        }
        api_url = f"https://api.github.com/repos/{_settings.GHUSER}/{_settings.REPONAME}/actions/runs/{gh_run.github_run_id}"
        
        try:
            gh_response = requests.get(api_url, headers=headers)
            if gh_response.status_code == 200:
                gh_data = gh_response.json()
                
                if gh_data['status'] == 'completed':
                    gh_run.status = gh_data['conclusion']
                    gh_run.save()
        except Exception as e:
            print(f"Error checking GitHub: {e}")

    return {
        "found": True,
        "status": gh_run.status,
        "github_log_url": github_log_url,
        "gh_run": gh_run
    }


def generator_view(request):
    if request.method == 'POST':
        form = GenerateForm(request.POST, request.FILES)
        if form.is_valid():
            params = form.cleaned_data
            full_url = get_full_url(request)
            result = generate_custom_client(params, full_url)
            if result['success']:
                return render(request, 'waiting.html', {
                    'filename': result['filename'],
                    'uuid': result['uuid'],
                    'status': "Starting generator...please wait",
                    'platform': result['platform'],
                    'log_url': result['log_url']
                })
            else:
                return JsonResponse({"error": result['error']}, status=result.get('status_code', 500))
    else:
        form = GenerateForm()
    #return render(request, 'maintenance.html')
    return render(request, 'generator.html', {'form': form})


def _expected_files_for_platform(filename, platform):
    """Return the list of expected output filenames for a given platform."""
    if platform == 'windows':
        return [f"{filename}.exe", f"{filename}.msi"]
    elif platform == 'windows-x86':
        return [f"{filename}.exe"]
    elif platform == 'linux':
        return [
            f"{filename}-x86_64.deb",
            f"{filename}-unattended-wayland-x86_64.deb",
            f"{filename}-x86_64.rpm",
            f"{filename}-suse-x86_64.rpm",
            f"{filename}-x86_64.pkg.tar.zst",
            f"{filename}-aarch64.deb",
            f"{filename}-aarch64.rpm",
            f"{filename}-suse-aarch64.rpm",
            f"{filename}-aarch64.pkg.tar.zst",
            f"{filename}-x86_64.AppImage",
            f"{filename}-aarch64.AppImage",
            f"{filename}-x86_64.flatpak",
            f"{filename}-aarch64.flatpak",
        ]
    elif platform == 'android':
        return [
            f"{filename}-aarch64.apk",
            f"{filename}-x86_64.apk",
            f"{filename}-armv7.apk",
        ]
    elif platform == 'macos':
        return [
            f"{filename}-x86_64.dmg",
            f"{filename}-aarch64.dmg",
        ]
    return []


def check_for_file(request):
    filename = request.GET.get('filename')
    uuid = request.GET.get('uuid')
    platform = request.GET.get('platform')

    result = _get_run_status(uuid)
    if not result['found']:
        from django.http import Http404
        raise Http404("Run not found")

    gh_run = result['gh_run']
    github_log_url = result['github_log_url']

    if gh_run.status == "success":
        expected = _expected_files_for_platform(filename, platform)
        existing_files = []
        missing_files = []
        for f in expected:
            file_path = os.path.join('exe', uuid, f)
            if os.path.isfile(file_path):
                existing_files.append(f)
            else:
                missing_files.append(f)

        return render(request, 'generated.html', {
            'filename': filename,
            'uuid': uuid,
            'platform': platform,
            'existing_files': existing_files,
            'missing_files': missing_files,
            'github_log_url': github_log_url,
        })
        
    elif gh_run.status in ['failure', 'cancelled', 'timed_out', 'skipped', 'action_required']:
        return render(request, 'failure.html', {
            'log_url': github_log_url, 
            'filename': filename, 
            'uuid': uuid, 
            'platform': platform,
            'status': gh_run.status
        })
        
    else:
        return render(request, 'waiting.html', {
            'filename': filename, 
            'uuid': uuid, 
            'status': gh_run.status, 
            'platform': platform, 
            'log_url': github_log_url
        })

def download(request):
    filename = request.GET['filename']
    uuid = request.GET['uuid']
    if not _safe_parts(uuid, filename):
        return HttpResponseForbidden("Invalid filename")
    file_path = os.path.join('exe', uuid, filename)
    with open(file_path, 'rb') as file:
        content = file.read()
    response = HttpResponse(content, headers={
        'Content-Type': 'application/vnd.microsoft.portable-executable',
        'Content-Disposition': f'attachment; filename="{filename}"'
    })
    return response

def get_png(request):
    filename = request.GET['filename']
    uuid = request.GET['uuid']
    if not _safe_parts(uuid, filename):
        return HttpResponseForbidden("Invalid filename")
    file_path = os.path.join('png',uuid,filename)
    with open(file_path, 'rb') as file:
        response = HttpResponse(file, headers={
            'Content-Type': 'application/vnd.microsoft.portable-executable',
            'Content-Disposition': f'attachment; filename="{filename}"'
        })

    return response

def create_github_run(myuuid):
    new_github_run = GithubRun(
        uuid=myuuid,
        status="Starting generator...please wait"
    )
    new_github_run.save()

def update_github_run(request):
    data = json.loads(request.body)
    myuuid = data.get('uuid')
    mystatus = data.get('status')
    GithubRun.objects.filter(Q(uuid=myuuid)).update(status=mystatus)
    return HttpResponse('')

def resize_and_encode_icon(imagefile):
    maxWidth = 200
    try:
        with io.BytesIO() as image_buffer:
            for chunk in imagefile.chunks():
                image_buffer.write(chunk)
            image_buffer.seek(0)

            img = Image.open(image_buffer)
            imgcopy = img.copy()
    except (IOError, OSError):
        raise ValueError("Uploaded file is not a valid image format.")

    # Check if resizing is necessary
    if img.size[0] <= maxWidth:
        with io.BytesIO() as image_buffer:
            imgcopy.save(image_buffer, format=imagefile.content_type.split('/')[1])
            image_buffer.seek(0)
            return_image = ContentFile(image_buffer.read(), name=imagefile.name)
        return base64.b64encode(return_image.read())

    # Calculate resized height based on aspect ratio
    wpercent = (maxWidth / float(img.size[0]))
    hsize = int((float(img.size[1]) * float(wpercent)))

    # Resize the image while maintaining aspect ratio using LANCZOS resampling
    imgcopy = imgcopy.resize((maxWidth, hsize), Image.Resampling.LANCZOS)

    with io.BytesIO() as resized_image_buffer:
        imgcopy.save(resized_image_buffer, format=imagefile.content_type.split('/')[1])
        resized_image_buffer.seek(0)

        resized_imagefile = ContentFile(resized_image_buffer.read(), name=imagefile.name)

    # Return the Base64 encoded representation of the resized image
    resized64 = base64.b64encode(resized_imagefile.read())
    #print(resized64)
    return resized64
 
#the following is used when accessed from an external source, like the rustdesk api server
def startgh(request):
    #print(request)
    data_ = json.loads(request.body)
    ####from here run the github action, we need user, repo, access token.
    url = 'https://api.github.com/repos/'+_settings.GHUSER+'/'+_settings.REPONAME+'/actions/workflows/generator-'+data_.get('platform')+'.yml/dispatches'  
    data = {
        "ref": _settings.GHBRANCH,
        "inputs":{
            "server":data_.get('server'),
            "key":data_.get('key'),
            "apiServer":data_.get('apiServer'),
            "custom":data_.get('custom'),
            "uuid":data_.get('uuid'),
            "iconlink":data_.get('iconlink'),
            "logolink":data_.get('logolink'),
            "appname":data_.get('appname'),
            "extras":data_.get('extras'),
            "filename":data_.get('filename')
        }
    } 
    headers = {
        'Accept':  'application/vnd.github+json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer '+_settings.GHBEARER,
        'X-GitHub-Api-Version': '2026-03-10'
    }
    response = requests.post(url, json=data, headers=headers)
    print(response)
    return HttpResponse(status=204)

def save_png(file, uuid, domain, name):
    file_save_path = "png/%s/%s" % (uuid, name)
    Path("png/%s" % uuid).mkdir(parents=True, exist_ok=True)

    if isinstance(file, str):  # Check if it's a base64 string
        try:
            header, encoded = file.split(';base64,')
            decoded_img = base64.b64decode(encoded)
            file = ContentFile(decoded_img, name=name) # Create a file-like object
        except ValueError:
            print("Invalid base64 data")
            return None  # Or handle the error as you see fit
        except Exception as e:  # Catch general exceptions during decoding
            print(f"Error decoding base64: {e}")
            return None
        
    with open(file_save_path, "wb+") as f:
        for chunk in file.chunks():
            f.write(chunk)
    # imageJson = {}
    # imageJson['url'] = domain
    # imageJson['uuid'] = uuid
    # imageJson['file'] = name
    #return "%s/%s" % (domain, file_save_path)
    return domain, uuid, name

def save_custom_client(request):
    file = request.FILES['file']
    myuuid = request.POST.get('uuid')
    if not _safe_parts(myuuid, file.name):
        return HttpResponseForbidden("Invalid filename")
    file_save_path = "exe/%s/%s" % (myuuid, file.name)
    Path("exe/%s" % myuuid).mkdir(parents=True, exist_ok=True)
    with open(file_save_path, "wb+") as f:
        for chunk in file.chunks():
            f.write(chunk)

    return HttpResponse("File saved successfully!")

def cleanup_secrets(request):
    # Pass the UUID as a query param or in JSON body
    data = json.loads(request.body)
    my_uuid = data.get('uuid')
    
    if not my_uuid:
        return HttpResponse("Missing UUID", status=400)

    # 1. Find the files in your temp directory matching the UUID
    temp_dir = os.path.join('temp_zips')
    
    # We look for any file starting with 'secrets_' and containing the uuid
    for filename in os.listdir(temp_dir):
        if my_uuid in filename and filename.endswith('.zip'):
            file_path = os.path.join(temp_dir, filename)
            try:
                os.remove(file_path)
                print(f"Successfully deleted {file_path}")
            except OSError as e:
                print(f"Error deleting file: {e}")

    return HttpResponse("Cleanup successful", status=200)

def get_zip(request):
    filename = request.GET['filename']
    base_dir = os.path.abspath('temp_zips')
    file_path = os.path.abspath(os.path.join(base_dir, filename))
    if not file_path.startswith(base_dir + os.sep):
        return HttpResponseForbidden("Invalid filename")
    with open(file_path, 'rb') as file:
        response = HttpResponse(file, headers={
            'Content-Type': 'application/vnd.microsoft.portable-executable',
            'Content-Disposition': f'attachment; filename="{filename}"'
        })

    return response


