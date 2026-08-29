"""
Server-side store for saved generator configs and their builds.

Layout under settings.BUILDS_ROOT (mounted at /opt/rdgen/builds):

    builds/
      <config-uuid>/
        config.json                 # saved GenerateForm params (source of truth)
        assets/                     # persisted icon/logo/privacy PNGs
          icon.png  logo.png  privacy.png
        <UTC-timestamp>/            # one dir per build (Phase 2)
          build.json
          <artifacts>

Everything here is filesystem-only; there is no database row for a config. The
config uuid is the stable directory name; each build gets a UTC timestamp
subdir. Only these two id shapes are ever joined onto the builds root, and every
join is validated to stay inside it — see is_valid_config_id / is_valid_build_id.
"""
import base64
import json
import os
import re
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path

from django.conf import settings

CONFIG_ID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
BUILD_ID_RE = re.compile(r'^\d{8}T\d{6}Z(?:-\d+)?$')

# GenerateForm keys that must NOT go into config.json: file objects can't be
# serialized, and the base64 blobs are persisted as PNG files under assets/.
_NON_PARAM_FIELDS = {
    'iconfile', 'logofile', 'privacyfile',
    'iconbase64', 'logobase64', 'privacybase64',
}

# Maps the config-store asset name to (upload field, base64 field) on the form.
ASSETS = {
    'icon': ('iconfile', 'iconbase64'),
    'logo': ('logofile', 'logobase64'),
    'privacy': ('privacyfile', 'privacybase64'),
}


def builds_root():
    return os.path.abspath(settings.BUILDS_ROOT)


def is_valid_config_id(cfg):
    return isinstance(cfg, str) and bool(CONFIG_ID_RE.match(cfg))


def is_valid_build_id(ts):
    return isinstance(ts, str) and bool(BUILD_ID_RE.match(ts))


def new_config_id():
    return str(uuid.uuid4())


def utc_stamp():
    return datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')


def config_dir(cfg):
    """Absolute path to a config dir, guaranteed to sit inside builds_root."""
    if not is_valid_config_id(cfg):
        raise ValueError(f'invalid config id: {cfg!r}')
    root = builds_root()
    path = os.path.abspath(os.path.join(root, cfg))
    if path != os.path.join(root, cfg):
        raise ValueError(f'config id escapes builds root: {cfg!r}')
    return path


def config_json_path(cfg):
    return os.path.join(config_dir(cfg), 'config.json')


def assets_dir(cfg):
    return os.path.join(config_dir(cfg), 'assets')


def build_dir(cfg, ts):
    if not is_valid_build_id(ts):
        raise ValueError(f'invalid build id: {ts!r}')
    return os.path.join(config_dir(cfg), ts)


def exists(cfg):
    return is_valid_config_id(cfg) and os.path.isfile(config_json_path(cfg))


def read_config(cfg):
    """Return the parsed config.json dict, or None if it doesn't exist."""
    if not exists(cfg):
        return None
    with open(config_json_path(cfg), 'r') as f:
        return json.load(f)


def write_config(cfg, params, note='', created_at=None):
    """Create or overwrite a config. `params` is JSON-serializable form data."""
    Path(config_dir(cfg)).mkdir(parents=True, exist_ok=True)
    now = utc_stamp()
    record = {
        'version': 1,
        'id': cfg,
        'created_at': created_at or now,
        'updated_at': now,
        'note': note or '',
        'params': {k: v for k, v in params.items() if k not in _NON_PARAM_FIELDS},
    }
    with open(config_json_path(cfg), 'w') as f:
        json.dump(record, f, indent=2)
    return record


def delete_config(cfg):
    path = config_dir(cfg)
    if os.path.isdir(path):
        shutil.rmtree(path)


def duplicate_config(cfg):
    """Copy an existing config dir (config + assets, not builds) to a new id."""
    src = read_config(cfg)
    if src is None:
        return None
    new_id = new_config_id()
    Path(config_dir(new_id)).mkdir(parents=True, exist_ok=True)
    # Copy persisted assets, if any.
    src_assets = assets_dir(cfg)
    if os.path.isdir(src_assets):
        shutil.copytree(src_assets, assets_dir(new_id))
    params = dict(src.get('params', {}))
    name = params.get('exename', '')
    if name:
        params['exename'] = f'{name}-copy'
    write_config(new_id, params, note=src.get('note', ''))
    return new_id


def save_asset_from_upload(cfg, name, django_file):
    """Persist an uploaded PNG (icon/logo/privacy) into assets/."""
    Path(assets_dir(cfg)).mkdir(parents=True, exist_ok=True)
    dest = os.path.join(assets_dir(cfg), f'{name}.png')
    with open(dest, 'wb+') as f:
        for chunk in django_file.chunks():
            f.write(chunk)


def save_asset_from_b64(cfg, name, data):
    """Persist a base64 data URI (or bare base64) PNG into assets/."""
    if not data:
        return
    if ';base64,' in data:
        data = data.split(';base64,', 1)[1]
    Path(assets_dir(cfg)).mkdir(parents=True, exist_ok=True)
    dest = os.path.join(assets_dir(cfg), f'{name}.png')
    with open(dest, 'wb+') as f:
        f.write(base64.b64decode(data))


def has_asset(cfg, name):
    return os.path.isfile(os.path.join(assets_dir(cfg), f'{name}.png'))


def latest_build(cfg):
    """Newest build.json summary for a config, or None. (Builds arrive in Phase 2.)"""
    builds = list_builds(cfg)
    return builds[0] if builds else None


def list_builds(cfg):
    """All builds for a config, newest first. Reads each build.json if present."""
    cdir = config_dir(cfg)
    if not os.path.isdir(cdir):
        return []
    out = []
    for entry in os.scandir(cdir):
        if not entry.is_dir() or not is_valid_build_id(entry.name):
            continue
        summary = {'timestamp': entry.name, 'status': 'unknown', 'artifacts': []}
        bj = os.path.join(entry.path, 'build.json')
        if os.path.isfile(bj):
            try:
                with open(bj, 'r') as f:
                    summary.update(json.load(f))
            except (OSError, ValueError):
                pass
        out.append(summary)
    out.sort(key=lambda b: b['timestamp'], reverse=True)
    return out


def list_configs():
    """All saved configs as table rows, newest-updated first."""
    root = builds_root()
    if not os.path.isdir(root):
        return []
    rows = []
    for entry in os.scandir(root):
        if not entry.is_dir() or not is_valid_config_id(entry.name):
            continue
        record = read_config(entry.name)
        if record is None:
            continue
        params = record.get('params', {})
        last = latest_build(entry.name)
        rows.append({
            'id': entry.name,
            'name': params.get('exename', '(unnamed)'),
            'appname': params.get('appname') or 'rustdesk',
            'platform': params.get('platform', ''),
            'note': record.get('note', ''),
            'updated_at': record.get('updated_at', ''),
            'last_build': last,
        })
    rows.sort(key=lambda r: r['updated_at'], reverse=True)
    return rows
