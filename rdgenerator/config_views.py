"""
Views for the saved-config console: list, create, edit, duplicate, delete.

Building a config and its history arrive in later phases; this module is the
config CRUD + table. It reuses the existing GenerateForm and generator.html
(rendered in "save mode") so the editor UI stays a single source of truth.
"""
import os

from django.conf import settings
from django.http import Http404, HttpResponse, HttpResponseBadRequest, JsonResponse
from django.shortcuts import redirect, render

from . import config_store as store
from .forms import GenerateForm
from .views import generate_custom_client, _get_run_status

# Statuses GitHub won't change again — no need to re-poll.
TERMINAL_STATUSES = {'success', 'failure', 'cancelled', 'timed_out', 'skipped'}


def _persist_assets(cfg, form, request):
    """Write any icon/logo/privacy image supplied on this save into assets/."""
    for name, (upload_field, b64_field) in store.ASSETS.items():
        uploaded = request.FILES.get(upload_field)
        if uploaded:
            store.save_asset_from_upload(cfg, name, uploaded)
            continue
        b64 = form.cleaned_data.get(b64_field)
        if b64:
            store.save_asset_from_b64(cfg, name, b64)


def _reconcile_last_build(row):
    """Refresh a config row's last_build status from GitHub if it's non-terminal.

    Mirrors the check config_history already does per-build: the landing page
    otherwise only shows a stale 'in_progress' until something else (like
    opening History) happens to poll GitHub and write the real status back.
    """
    last = row.get('last_build')
    if not last:
        return
    build_uuid = last.get('build_uuid')
    if not build_uuid or last.get('status') in TERMINAL_STATUSES:
        return
    info = _get_run_status(build_uuid)
    if info.get('found'):
        store.update_build_status(build_uuid, info['status'])
        last['status'] = info['status']


def configs_list(request):
    configs = store.list_configs()
    for row in configs:
        _reconcile_last_build(row)
    return render(request, 'configs_list.html', {'configs': configs})


def config_new(request):
    return render(request, 'generator.html', {
        'form': GenerateForm(),
        'save_mode': True,
        'config_id': '',
        'note': '',
    })


def config_edit(request, cfg):
    record = store.read_config(cfg)
    if record is None:
        raise Http404('Config not found')
    initial = dict(record.get('params', {}))
    # Surface persisted images as base64 so they display and round-trip on the
    # next save (params intentionally omits the image blobs; the PNGs live in
    # assets/). Without this the edit form shows blank image fields.
    for _name, (_upload_field, b64_field) in store.ASSETS.items():
        b64 = store.load_asset_b64(cfg, _name)
        if b64:
            initial[b64_field] = b64
    return render(request, 'generator.html', {
        'form': GenerateForm(initial=initial),
        'save_mode': True,
        'config_id': cfg,
        'note': record.get('note', ''),
    })


def config_save(request):
    if request.method != 'POST':
        return HttpResponseBadRequest('POST required')

    cfg = request.POST.get('config_id', '').strip()
    if cfg and not store.is_valid_config_id(cfg):
        return HttpResponseBadRequest('Invalid config id')

    form = GenerateForm(request.POST, request.FILES)
    if not form.is_valid():
        return render(request, 'generator.html', {
            'form': form,
            'save_mode': True,
            'config_id': cfg,
            'note': request.POST.get('note', ''),
        })

    created_at = None
    if cfg:
        existing = store.read_config(cfg)
        created_at = existing.get('created_at') if existing else None
    else:
        cfg = store.new_config_id()

    store.write_config(cfg, form.cleaned_data,
                       note=request.POST.get('note', ''), created_at=created_at)
    _persist_assets(cfg, form, request)
    return redirect('/configs')


def config_duplicate(request, cfg):
    if request.method != 'POST':
        return HttpResponseBadRequest('POST required')
    if store.duplicate_config(cfg) is None:
        raise Http404('Config not found')
    return redirect('/configs')


def config_delete(request, cfg):
    if request.method != 'POST':
        return HttpResponseBadRequest('POST required')
    if not store.exists(cfg):
        raise Http404('Config not found')
    store.delete_config(cfg)
    return redirect('/configs')


def config_build(request, cfg):
    """Kick off a build for a saved config into builds/<cfg>/<timestamp>/."""
    if request.method != 'POST':
        return HttpResponseBadRequest('POST required')
    record = store.read_config(cfg)
    if record is None:
        raise Http404('Config not found')

    params = dict(record.get('params', {}))
    # Feed persisted images to the generator as base64 (it re-uploads them).
    for name, (_upload_field, b64_field) in store.ASSETS.items():
        b64 = store.load_asset_b64(cfg, name)
        if b64:
            params[b64_field] = b64

    ts = store.new_build_dir(cfg)
    full_url = f"{settings.PROTOCOL}://{request.get_host()}"
    result = generate_custom_client(params, full_url, dest=f'{cfg}/{ts}')
    if not result.get('success'):
        store.fail_build(cfg, ts, result.get('error', 'dispatch failed'))
    return redirect('/configs')


def config_history(request, cfg):
    """JSON list of a config's builds (current + previous), newest first.

    Non-terminal builds are refreshed from GitHub (via the shared GithubRun
    status check) and the fresh status mirrored back onto build.json.
    """
    if store.read_config(cfg) is None:
        raise Http404('Config not found')

    builds = []
    for b in store.list_builds(cfg):
        status = b.get('status', 'unknown')
        build_uuid = b.get('build_uuid')
        run_id = b.get('github_run_id')
        if build_uuid and status not in TERMINAL_STATUSES:
            info = _get_run_status(build_uuid)
            if info.get('found'):
                status = info['status']
                store.update_build_status(build_uuid, status)
        log_url = store.github_run_url(run_id)
        builds.append({
            'timestamp': b.get('timestamp'),
            'status': status,
            'platform': b.get('platform', ''),
            'version': b.get('version', ''),
            'artifacts': b.get('artifacts', []),
            'started_at': b.get('started_at', ''),
            'error': b.get('error', ''),
            'log_url': log_url,
        })
    return JsonResponse({'builds': builds})


def config_build_download(request, cfg, ts):
    """Download a single artifact from builds/<cfg>/<ts>/."""
    if not (store.is_valid_config_id(cfg) and store.is_valid_build_id(ts)):
        raise Http404('Not found')
    filename = request.GET.get('file', '')
    if not filename:
        return HttpResponseBadRequest('Missing file')
    try:
        path = store.build_artifact_path(cfg, ts, filename)
    except ValueError:
        raise Http404('Not found')
    if not os.path.isfile(path):
        raise Http404('Not found')
    with open(path, 'rb') as f:
        content = f.read()
    return HttpResponse(content, headers={
        'Content-Type': 'application/octet-stream',
        'Content-Disposition': f'attachment; filename="{os.path.basename(path)}"',
    })
