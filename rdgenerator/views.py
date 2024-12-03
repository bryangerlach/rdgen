import io
from pathlib import Path
from django.http import HttpResponse, JsonResponse
from django.shortcuts import render
from django.core.files.base import ContentFile
import os
import re
import requests
import base64
import json
import uuid
from django.conf import settings as _settings
from django.db.models import Q
from .forms import GenerateForm
from .models import GithubRun
from PIL import Image
from urllib.parse import quote

def generator_view(request):
    if request.method == 'POST':
        form = GenerateForm(request.POST, request.FILES)
        if form.is_valid():
            platform = form.cleaned_data['platform']
            version = form.cleaned_data['version']
            delayFix = form.cleaned_data['delayFix']
            server = form.cleaned_data['serverIP']
            key = form.cleaned_data['key']
            apiServer = form.cleaned_data['apiServer']
            urlLink = form.cleaned_data['urlLink']
            if not server:
                server = 'rs-ny.rustdesk.com' #default rustdesk server
            if not key:
                key = 'OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=' #default rustdesk key
            if not apiServer:
                apiServer = server+":21114"
            if not urlLink:
                urlLink = "https://rustdesk.com"
            direction = form.cleaned_data['direction']
            installation = form.cleaned_data['installation']
            settings = form.cleaned_data['settings']
            appname = form.cleaned_data['appname']
            filename = form.cleaned_data['exename']
            permPass = form.cleaned_data['permanentPassword']
            theme = form.cleaned_data['theme']
            themeDorO = form.cleaned_data['themeDorO']
            runasadmin = form.cleaned_data['runasadmin']
            passApproveMode = form.cleaned_data['passApproveMode']
            denyLan = form.cleaned_data['denyLan']
            enableDirectIP = form.cleaned_data['enableDirectIP']
            #ipWhitelist = form.cleaned_data['ipWhitelist']
            autoClose = form.cleaned_data['autoClose']
            permissionsDorO = form.cleaned_data['permissionsDorO']
            permissionsType = form.cleaned_data['permissionsType']
            enableKeyboard = form.cleaned_data['enableKeyboard']
            enableClipboard = form.cleaned_data['enableClipboard']
            enableFileTransfer = form.cleaned_data['enableFileTransfer']
            enableAudio = form.cleaned_data['enableAudio']
            enableTCP = form.cleaned_data['enableTCP']
            enableRemoteRestart = form.cleaned_data['enableRemoteRestart']
            enableRecording = form.cleaned_data['enableRecording']
            enableBlockingInput = form.cleaned_data['enableBlockingInput']
            enableRemoteModi = form.cleaned_data['enableRemoteModi']
            removeWallpaper = form.cleaned_data['removeWallpaper']
            defaultManual = form.cleaned_data['defaultManual']
            overrideManual = form.cleaned_data['overrideManual']


            filename = re.sub(r'[^\w\s-]', '_', filename).strip()
            myuuid = str(uuid.uuid4())
            protocol = 'http'
            host = request.get_host()
            full_url = f"{protocol}://{host}"
            try:
                iconfile = form.cleaned_data['iconfile']
                #iconbase64 = resize_and_encode_icon(iconfile)
                iconlink = save_png(iconfile,myuuid,full_url,"icon.png")
            except:
                print("failed to get icon, using default")
                #iconbase64 = b"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"
                iconlink = "false"
            try:
                logofile = form.cleaned_data['logofile']
                #logobase64 = resize_and_encode_icon(logofile)
                logolink = save_png(logofile,myuuid,full_url,"logo.png")
            except:
                print("failed to get logo")
                #logobase64 = b""
                logolink = "false"

            ###create the custom.txt json here and send in as inputs below
            decodedCustom = {}
            if direction != "Both":
                decodedCustom['conn-type'] = direction
            if installation == "installationN":
                decodedCustom['disable-installation'] = 'Y'
            if settings == "settingsN":
                decodedCustom['disable-settings'] = 'Y'
            if appname.upper != "rustdesk".upper and appname != "":
                decodedCustom['app-name'] = appname
            decodedCustom['override-settings'] = {}
            decodedCustom['default-settings'] = {}
            if permPass != "":
                decodedCustom['password'] = permPass
            if theme != "system":
                if themeDorO == "default":
                    decodedCustom['default-settings']['theme'] = theme
                elif themeDorO == "override":
                    decodedCustom['override-settings']['theme'] = theme
            decodedCustom['approve-mode'] = passApproveMode
            decodedCustom['enable-lan-discovery'] = 'N' if denyLan else 'Y'
            decodedCustom['direct-server'] = 'Y' if enableDirectIP else 'N'
            decodedCustom['allow-auto-disconnect'] = 'Y' if autoClose else 'N'
            decodedCustom['allow-remove-wallpaper'] = 'Y' if removeWallpaper else 'N'
            if permissionsDorO == "default":
                decodedCustom['default-settings']['access-mode'] = permissionsType
                decodedCustom['default-settings']['enable-keyboard'] = 'Y' if enableKeyboard else 'N'
                decodedCustom['default-settings']['enable-clipboard'] = 'Y' if enableClipboard else 'N'
                decodedCustom['default-settings']['enable-file-transfer'] = 'Y' if enableFileTransfer else 'N'
                decodedCustom['default-settings']['enable-audio'] = 'Y' if enableAudio else 'N'
                decodedCustom['default-settings']['enable-tunnel'] = 'Y' if enableTCP else 'N'
                decodedCustom['default-settings']['enable-remote-restart'] = 'Y' if enableRemoteRestart else 'N'
                decodedCustom['default-settings']['enable-record-session'] = 'Y' if enableRecording else 'N'
                decodedCustom['default-settings']['enable-block-input'] = 'Y' if enableBlockingInput else 'N'
                decodedCustom['default-settings']['allow-remote-config-modification'] = 'Y' if enableRemoteModi else 'N'
            else:
                decodedCustom['override-settings']['access-mode'] = permissionsType
                decodedCustom['override-settings']['enable-keyboard'] = 'Y' if enableKeyboard else 'N'
                decodedCustom['override-settings']['enable-clipboard'] = 'Y' if enableClipboard else 'N'
                decodedCustom['override-settings']['enable-file-transfer'] = 'Y' if enableFileTransfer else 'N'
                decodedCustom['override-settings']['enable-audio'] = 'Y' if enableAudio else 'N'
                decodedCustom['override-settings']['enable-tunnel'] = 'Y' if enableTCP else 'N'
                decodedCustom['override-settings']['enable-remote-restart'] = 'Y' if enableRemoteRestart else 'N'
                decodedCustom['override-settings']['enable-record-session'] = 'Y' if enableRecording else 'N'
                decodedCustom['override-settings']['enable-block-input'] = 'Y' if enableBlockingInput else 'N'
                decodedCustom['override-settings']['allow-remote-config-modification'] = 'Y' if enableRemoteModi else 'N'

            for line in defaultManual.splitlines():
                k, value = line.split('=')
                decodedCustom['default-settings'][k.strip()] = value.strip()

            for line in overrideManual.splitlines():
                k, value = line.split('=')
                decodedCustom['override-settings'][k.strip()] = value.strip()
            
            decodedCustomJson = json.dumps(decodedCustom)

            string_bytes = decodedCustomJson.encode("ascii")
            base64_bytes = base64.b64encode(string_bytes)
            encodedCustom = base64_bytes.decode("ascii")

            #github limits inputs to 10, so lump extras into one with json
            extras = {}
            extras['runasadmin'] = runasadmin
            extras['urlLink'] = urlLink
            extras['delayFix'] = 'true' if delayFix else 'false'
            extras['version'] = version
            extras['rdgen'] = 'true'
            extra_input = json.dumps(extras)

            ####from here run the github action, we need user, repo, access token.
            if platform == 'windows':
                url = 'https://api.github.com/repos/'+_settings.GHUSER+'/rdgen/actions/workflows/generator-windows.yml/dispatches' 
            elif platform == 'linux':
                url = 'https://api.github.com/repos/'+_settings.GHUSER+'/rdgen/actions/workflows/generator-linux.yml/dispatches'  
            elif platform == 'android':
                url = 'https://api.github.com/repos/'+_settings.GHUSER+'/rdgen/actions/workflows/generator-android.yml/dispatches'
            else:
                url = 'https://api.github.com/repos/'+_settings.GHUSER+'/rdgen/actions/workflows/generator-windows.yml/dispatches'
            ####breaking changes were made in 1.3.3 version, so if 1.3.2 or lower, use:
            if version == '1.3.2' or version == '1.3.1' or version == '1.3.0':
                if platform == 'windows':
                    url = 'https://api.github.com/repos/'+_settings.GHUSER+'/rdgen/actions/workflows/pre133-generator-windows.yml/dispatches' 
                elif platform == 'linux':
                    url = 'https://api.github.com/repos/'+_settings.GHUSER+'/rdgen/actions/workflows/pre133-generator-linux.yml/dispatches'  
                elif platform == 'android':
                    url = 'https://api.github.com/repos/'+_settings.GHUSER+'/rdgen/actions/workflows/pre133-generator-android.yml/dispatches'
                else:
                    url = 'https://api.github.com/repos/'+_settings.GHUSER+'/rdgen/actions/workflows/pre133-generator-windows.yml/dispatches'

            #url = 'https://api.github.com/repos/'+_settings.GHUSER+'/rustdesk/actions/workflows/test.yml/dispatches'  
            data = {
                "ref":"master",
                "inputs":{
                    "server":server,
                    "key":key,
                    "apiServer":apiServer,
                    "custom":encodedCustom,
                    "uuid":myuuid,
                    #"iconbase64":iconbase64.decode("utf-8"),
                    #"logobase64":logobase64.decode("utf-8") if logobase64 else "",
                    "iconlink":iconlink,
                    "logolink":logolink,
                    "appname":appname,
                    "extras":extra_input,
                    "filename":filename
                }
            } 
            #print(data)
            headers = {
                'Accept':  'application/vnd.github+json',
                'Content-Type': 'application/json',
                'Authorization': 'Bearer '+_settings.GHBEARER,
                'X-GitHub-Api-Version': '2022-11-28'
            }
            create_github_run(myuuid)
            response = requests.post(url, json=data, headers=headers)
            print(response)
            if response.status_code == 204:
                return render(request, 'waiting.html', {'filename':filename, 'uuid':myuuid, 'status':"Starting generator...please wait", 'platform':platform})
            else:
                return JsonResponse({"error": "Something went wrong"})
    else:
        form = GenerateForm()
    return render(request, 'generator.html', {'form': form})


def check_for_file(request):
    filename = request.GET['filename']
    uuid = request.GET['uuid']
    platform = request.GET['platform']
    gh_run = GithubRun.objects.filter(Q(uuid=uuid)).first()
    status = gh_run.status

    #if file_exists:
    if status == "Success":
        return render(request, 'generated.html', {'filename': filename, 'uuid':uuid, 'platform':platform})
    else:
        return render(request, 'waiting.html', {'filename':filename, 'uuid':uuid, 'status':status, 'platform':platform})

def download(request):
    filename = request.GET['filename']
    uuid = request.GET['uuid']
    #filename = filename+".exe"
    file_path = os.path.join('exe',uuid,filename)
    with open(file_path, 'rb') as file:
        response = HttpResponse(file, headers={
            'Content-Type': 'application/vnd.microsoft.portable-executable',
            'Content-Disposition': f'attachment; filename="{filename}"'
        })

    return response

def get_png(request):
    filename = request.GET['filename']
    uuid = request.GET['uuid']
    #filename = filename+".exe"
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
    url = 'https://api.github.com/repos/'+_settings.GHUSER+'/rdgen/actions/workflows/generator-'+data_.get('platform')+'.yml/dispatches'  
    data = {
        "ref":"master",
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
        'X-GitHub-Api-Version': '2022-11-28'
    }
    response = requests.post(url, json=data, headers=headers)
    print(response)
    return HttpResponse(status=204)

def save_png(file, uuid, domain, name):
    file_save_path = "png/%s/%s" % (uuid, name)
    Path("png/%s" % uuid).mkdir(parents=True, exist_ok=True)
    with open(file_save_path, "wb+") as f:
        for chunk in file.chunks():
            f.write(chunk)
    imageJson = {}
    imageJson['url'] = domain
    imageJson['uuid'] = uuid
    imageJson['file'] = name
    #return "%s/%s" % (domain, file_save_path)
    return json.dumps(imageJson)

def save_custom_client(request):
    file = request.FILES['file']
    myuuid = request.POST.get('uuid')
    file_save_path = "exe/%s/%s" % (myuuid, file.name)
    Path("exe/%s" % myuuid).mkdir(parents=True, exist_ok=True)
    with open(file_save_path, "wb+") as f:
        for chunk in file.chunks():
            f.write(chunk)

    return HttpResponse("File saved successfully!")
