import json
from django.http import JsonResponse
from django.conf import settings as _settings
from .views import generate_custom_client, _get_run_status


# Field validation constraints (mirrored from GenerateForm)
PLATFORM_CHOICES = ['windows', 'windows-x86', 'linux', 'android', 'macos']
VERSION_CHOICES = ['master', '1.4.9', '1.4.8', '1.4.7', '1.4.6', '1.4.5', '1.4.4', '1.4.3', '1.4.2', '1.4.1', '1.4.0']
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
    'sh_secret_field', 'serverIP', 'key', 'apiServer', 'urlLink', 'downloadLink',
    'appname', 'compname', 'androidappid', 'permanentPassword',
    'defaultManual', 'overrideManual',
    'iconbase64', 'logobase64', 'privacybase64',
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
        if not isinstance(value, bool):
            errors[field] = 'Must be a boolean value.'
        else:
            cleaned[field] = value

    # Optional string fields
    for field in OPTIONAL_STR_FIELDS:
        cleaned[field] = data.get(field, '')

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

    return JsonResponse(response_data)
