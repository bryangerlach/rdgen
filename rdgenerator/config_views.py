"""
Views for the saved-config console: list, create, edit, duplicate, delete.

Building a config and its history arrive in later phases; this module is the
config CRUD + table. It reuses the existing GenerateForm and generator.html
(rendered in "save mode") so the editor UI stays a single source of truth.
"""
from django.http import Http404, HttpResponseBadRequest
from django.shortcuts import redirect, render

from . import config_store as store
from .forms import GenerateForm


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


def configs_list(request):
    return render(request, 'configs_list.html', {'configs': store.list_configs()})


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
    return render(request, 'generator.html', {
        'form': GenerateForm(initial=record.get('params', {})),
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
