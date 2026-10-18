import json
import os
import re
from django.http import JsonResponse
from django.conf import settings as _settings
from .views import generate_custom_client, _get_run_status, _UUID_RE


# Field validation constraints (mirrored from GenerateForm)
PLATFORM_CHOICES = ['windows', 'windows-x86', 'linux', 'android', 'macos']
VERSION_CHOICES = ['master', '1.5.0', '1.4.9', '1.4.8', '1.4.7', '1.4.6', '1.4.5', '1.4.4', '1.4.3', '1.4.2', '1.4.1', '1.4.0']
DIRECTION_CHOICES = ['incoming', 'outgoing', 'both']
INSTALLATION_CHOICES = ['installationY', 'installationN']
SETTINGS_CHOICES = ['settingsY', 'settingsN']
THEME_CHOICES = ['light', 'dark', 'system']
THEME_DORO_CHOICES = ['default', 'override']
PASS_APPROVE_MODE_CHOICES = ['password', 'click', 'password-click']
PERMISSIONS_DORO_CHOICES = ['default', 'override']
PERMISSIONS_TYPE_CHOICES = ['custom', 'full', 'view']

# Boolean fields
BOOL_FIELDS = [
    'delayFix', 'xOffline', 'hidecm', 'removeNewVersionNotif',
    'denyLan', 'enableDirectIP', 'autoClose',
    'enableKeyboard', 'enableClipboard', 'enableFileTransfer', 'enableAudio',
    'enableTCP', 'enableRemoteRestart', 'enableRecording', 'enableBlockingInput',
    'enableRemoteModi', 'removeWallpaper', 'enablePrinter', 'enableCamera', 'enableTerminal',
]

# Optional string fields (no validation needed, just accept as-is)
OPTIONAL_STR_FIELDS = [
    'sh_secret_field', 'serverIP', 'serverPort', 'key', 'apiServer', 'urlLink', 'downloadLink',
    'appname', 'compname', 'androidappid', 'permanentPassword',
    'defaultManual', 'overrideManual',
    'iconbase64', 'logobase64', 'privacybase64',
    'update_public_key',
    'app_version',
]


def validate_generate_params(data):
    """
    Validate JSON API parameters against the same constraints as GenerateForm.

    Returns:
        tuple: (cleaned_data dict, errors dict)
        If errors is non-empty, validation failed.
    """
    errors = {}
    cleaned = {}

    # Required string field
    exename = data.get('exename', '')
    if not exename:
        errors['exename'] = 'This field is required.'
    else:
        cleaned['exename'] = exename

    # Choice fields
    choice_validations = {
        'platform': (PLATFORM_CHOICES, 'windows'),
        'version': (VERSION_CHOICES, '1.4.9'),
        'direction': (DIRECTION_CHOICES, 'both'),
        'installation': (INSTALLATION_CHOICES, 'installationY'),
        'settings': (SETTINGS_CHOICES, 'settingsY'),
        'theme': (THEME_CHOICES, 'system'),
        'themeDorO': (THEME_DORO_CHOICES, 'default'),
        'passApproveMode': (PASS_APPROVE_MODE_CHOICES, 'password-click'),
        'permissionsDorO': (PERMISSIONS_DORO_CHOICES, 'default'),
        'permissionsType': (PERMISSIONS_TYPE_CHOICES, 'custom'),
    }
    for field, (choices, default) in choice_validations.items():
        value = data.get(field, default)
        if value not in choices:
            errors[field] = f'Invalid choice. Must be one of: {choices}'
        else:
            cleaned[field] = value

    # Boolean fields
    for field in BOOL_FIELDS:
        value = data.get(field, False)
        
        if isinstance(value, str) and value.lower() == 'on':
            value = True
            
        if not isinstance(value, bool):
            errors[field] = 'Must be a boolean value.'
        else:
            cleaned[field] = value

    # Optional string fields
    for field in OPTIONAL_STR_FIELDS:
        cleaned[field] = data.get(field, '')

    # Free-text names flow into single/double-quoted bash sed scripts
    # (same rule as GenerateForm.clean_appname/clean_compname).
    for field in ('appname', 'compname'):
        value = cleaned.get(field, '')
        if isinstance(value, str) and re.search(r'[&\\|\'"$`\r\n]', value):
            errors[field] = (
                'Contains characters unsupported in build scripts '
                '(& \\ | \' " $ `, newlines).'
            )

    # File fields are not used in API mode (base64 fields are used instead)
    cleaned['iconfile'] = None
    cleaned['logofile'] = None
    cleaned['privacyfile'] = None

    return cleaned, errors


def api_generate(request):
    """
    POST /api/generate

    Accepts a JSON body with client configuration parameters and triggers
    the custom client generation process via GitHub Actions.

    Returns JSON with success status, uuid, filename, platform, and log_url.
    """
    if request.method != 'POST':
        return JsonResponse({"success": False, "error": "Method not allowed. Use POST."}, status=405)

    try:
        data = json.loads(request.body)
    except (json.JSONDecodeError, ValueError) as e:
        return JsonResponse({"success": False, "error": f"Invalid JSON: {str(e)}"}, status=400)

    # Optional platform override: allows the caller to overwrite the
    # "platform" key carried in the JSON body (e.g. when the saved config
    # says "windows" but the build should run as "linux"/"android"). The
    # override may be supplied as a query parameter or as an additional
    # field in the request body.
    PLATFORM_OVERRIDE_KEYS = (
        'platform', 'set_platform', 'setPlatform', 'platform_override',
        'override_platform', 'platformOverride', 'overridePlatform',
        'platform_setting', 'platformSetting',
    )
    override_platform = None
    for key in PLATFORM_OVERRIDE_KEYS:
        value = request.GET.get(key)
        if value is not None and value != '':
            override_platform = value
            break
    # Also accept any query parameter whose value is a valid platform choice.
    if override_platform is None:
        for key, value in request.GET.items():
            if isinstance(value, str) and value in PLATFORM_CHOICES:
                override_platform = value
                break
    if override_platform is None and isinstance(data, dict):
        for key in PLATFORM_OVERRIDE_KEYS:
            if key in data and data.get(key) not in (None, ''):
                if key != 'platform':
                    override_platform = data.get(key)
                    break
    # Fall back to a generic scan: any body field (other than "platform")
    # whose value is a valid platform choice also acts as an override.
    if override_platform is None and isinstance(data, dict):
        for key, value in data.items():
            if key == 'platform':
                continue
            key_l = str(key).lower()
            if not isinstance(value, str) or value not in PLATFORM_CHOICES:
                continue
            # Only treat a field as a platform override when its name suggests
            # that intent, to avoid misreading ordinary fields (e.g. appname)
            # whose value happens to be a platform name.
            if ('platform' in key_l or 'override' in key_l or 'set' in key_l
                    or key_l in ('os', 'target', 'targetos')):
                override_platform = value
                break

    if override_platform is not None:
        if override_platform not in PLATFORM_CHOICES:
            return JsonResponse({
                "success": False,
                "error": "Validation errors",
                "details": {"platform": f"Invalid choice. Must be one of: {PLATFORM_CHOICES}"}
            }, status=400)
        # Make validation + generation honour the override instead of (or
        # in addition to) the platform already present in the JSON body.
        if isinstance(data, dict):
            data = dict(data)
            data['platform'] = override_platform

    # Optional version override, mirroring the optional platform override.
    # Any value must be one of VERSION_CHOICES.
    VERSION_OVERRIDE_KEYS = (
        'version', 'set_version', 'setVersion', 'version_override',
        'override_version', 'versionOverride', 'overrideVersion',
        'version_setting', 'versionSetting',
    )
    override_version = None
    for key in VERSION_OVERRIDE_KEYS:
        value = request.GET.get(key)
        if value is not None and value != '':
            override_version = value
            break
    if override_version is None:
        for key, value in request.GET.items():
            if isinstance(value, str) and value in VERSION_CHOICES:
                override_version = value
                break
    if override_version is None and isinstance(data, dict):
        for key in VERSION_OVERRIDE_KEYS:
            if key in data and data.get(key) not in (None, ''):
                if key != 'version':
                    override_version = data.get(key)
                    break
    if override_version is None and isinstance(data, dict):
        for key, value in data.items():
            if key == 'version':
                continue
            if not isinstance(value, str) or value not in VERSION_CHOICES:
                continue
            key_l = str(key).lower()
            if not ('version' in key_l or 'ver' in key_l or 'set' in key_l
                    or 'override' in key_l or 'release' in key_l):
                continue
            override_version = value
            break

    if override_version is not None:
        if override_version not in VERSION_CHOICES:
            return JsonResponse({
                "success": False,
                "error": "Validation errors",
                "details": {"version": f"Invalid choice. Must be one of: {VERSION_CHOICES}"}
            }, status=400)
        if isinstance(data, dict):
            data = dict(data)
            data['version'] = override_version

    cleaned, errors = validate_generate_params(data)
    if errors:
        return JsonResponse({
            "success": False,
            "error": "Validation errors",
            "details": errors
        }, status=400)

    # Build full_url the same way as generator_view
    full_url = f"{_settings.PROTOCOL}://{request.get_host()}" if _settings.GENURL else f"{_settings.PROTOCOL}://{request.get_host()}"

    result = generate_custom_client(cleaned, full_url)

    if result['success']:
        # Add convenience URLs for the API consumer
        result['status_url'] = f"/api/status?uuid={result['uuid']}&platform={result['platform']}&filename={result['filename']}"
        return JsonResponse(result)
    else:
        return JsonResponse({"success": False, "error": result['error']}, status=result.get('status_code', 500))


def api_status(request):
    """
    GET /api/status

    Checks the generation status for a given UUID.
    Returns JSON with status, uuid, and optional log_url/filename/platform.
    On a success status, also returns "files": a list of filenames that were
    created/saved for this run.
    """
    if request.method != 'GET':
        return JsonResponse({"success": False, "error": "Method not allowed. Use GET."}, status=405)

    uuid_val = request.GET.get('uuid')
    if not uuid_val:
        return JsonResponse({"error": "Missing required parameter: uuid"}, status=400)

    filename = request.GET.get('filename', '')
    platform = request.GET.get('platform', '')

    result = _get_run_status(uuid_val)

    if not result['found']:
        return JsonResponse({"error": "Run not found"}, status=404)

    response_data = {
        "status": result['status'],
        "uuid": uuid_val,
        "log_url": result['github_log_url'],
    }
    if filename:
        response_data['filename'] = filename
    if platform:
        response_data['platform'] = platform

    # Expose the filenames that were actually uploaded/saved for this run so
    # API consumers can download them. The directory is scanned regardless of
    # the run status so that any (possibly partial) files are still reported,
    # including on failure.
    created_files = []
    if _UUID_RE.match(uuid_val or ''):
        run_dir = os.path.join('exe', uuid_val)
        if os.path.isdir(run_dir):
            for name in sorted(os.listdir(run_dir)):
                full_path = os.path.join(run_dir, name)
                if os.path.isfile(full_path):
                    created_files.append(name)
    response_data['files'] = created_files

    return JsonResponse(response_data)
