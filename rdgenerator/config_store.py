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


def load_asset_b64(cfg, name):
    """Return a persisted asset as a data-URI base64 string, or None."""
    path = os.path.join(assets_dir(cfg), f'{name}.png')
    if not os.path.isfile(path):
        return None
    with open(path, 'rb') as f:
        return 'data:image/png;base64,' + base64.b64encode(f.read()).decode('ascii')


def latest_build(cfg):
    """Newest build.json summary for a config, or None."""
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


# --- Builds (Phase 2) -------------------------------------------------------
#
# A build is a timestamped subdir of a config. Each carries a build.json and,
# once the workflow reports back, its artifacts. The workflow only knows the
# build_uuid (Option A: it POSTs `uuid` unchanged), so build_uuid -> dir is
# resolved server-side via a small index file, falling back to a scan.

INDEX_DIRNAME = '.index'


def new_build_dir(cfg):
    """Create and return a fresh, unique build timestamp for a config."""
    base = utc_stamp()
    ts, n = base, 2
    while os.path.exists(build_dir(cfg, ts)):
        ts, n = f'{base}-{n}', n + 1
    Path(build_dir(cfg, ts)).mkdir(parents=True, exist_ok=True)
    return ts


def _build_json_path(cfg, ts):
    return os.path.join(build_dir(cfg, ts), 'build.json')


def read_build(cfg, ts):
    path = _build_json_path(cfg, ts)
    if not os.path.isfile(path):
        return None
    with open(path, 'r') as f:
        return json.load(f)


def write_build(cfg, ts, data):
    Path(build_dir(cfg, ts)).mkdir(parents=True, exist_ok=True)
    with open(_build_json_path(cfg, ts), 'w') as f:
        json.dump(data, f, indent=2)


def _index_path(build_uuid):
    # build_uuid is a uuid4 — same shape as a config id.
    if not is_valid_config_id(build_uuid):
        raise ValueError(f'invalid build uuid: {build_uuid!r}')
    return os.path.join(builds_root(), INDEX_DIRNAME, build_uuid)


def register_build(build_uuid, cfg, ts):
    """Record build_uuid -> '<cfg>/<ts>' so callbacks can find the build dir."""
    Path(os.path.join(builds_root(), INDEX_DIRNAME)).mkdir(parents=True, exist_ok=True)
    with open(_index_path(build_uuid), 'w') as f:
        f.write(f'{cfg}/{ts}')


def resolve_build(build_uuid):
    """Return (cfg, ts, abs_dir) for a build_uuid, or None. Index first, then scan."""
    if not is_valid_config_id(build_uuid):
        return None
    idx = _index_path(build_uuid)
    if os.path.isfile(idx):
        with open(idx, 'r') as f:
            cfg, _, ts = f.read().strip().partition('/')
        if is_valid_config_id(cfg) and is_valid_build_id(ts) and os.path.isdir(build_dir(cfg, ts)):
            return cfg, ts, build_dir(cfg, ts)
    # Fallback: scan every build.json for a matching build_uuid.
    root = builds_root()
    if not os.path.isdir(root):
        return None
    for cfg_entry in os.scandir(root):
        if not cfg_entry.is_dir() or not is_valid_config_id(cfg_entry.name):
            continue
        for b in os.scandir(cfg_entry.path):
            if not b.is_dir() or not is_valid_build_id(b.name):
                continue
            data = read_build(cfg_entry.name, b.name)
            if data and data.get('build_uuid') == build_uuid:
                return cfg_entry.name, b.name, b.path
    return None


def start_build(cfg, ts, build_uuid, github_run_id, platform, version):
    """Mark a build in-progress once its workflow has been dispatched."""
    now = utc_stamp()
    write_build(cfg, ts, {
        'build_uuid': build_uuid,
        'github_run_id': github_run_id,
        'status': 'in_progress',
        'platform': platform,
        'version': version,
        'started_at': now,
        'updated_at': now,
        'artifacts': [],
    })
    register_build(build_uuid, cfg, ts)


def fail_build(cfg, ts, error):
    """Record a build that could not be dispatched."""
    data = read_build(cfg, ts) or {'artifacts': []}
    data.update({'status': 'failure', 'error': str(error), 'updated_at': utc_stamp()})
    write_build(cfg, ts, data)


def update_build_status(build_uuid, status):
    """Update a build's status by build_uuid (called from the /updategh callback)."""
    resolved = resolve_build(build_uuid)
    if not resolved:
        return False
    cfg, ts, _ = resolved
    data = read_build(cfg, ts) or {'artifacts': []}
    data.update({'status': status, 'updated_at': utc_stamp()})
    write_build(cfg, ts, data)
    return True


def record_artifact(build_uuid, filename):
    """Append an artifact filename to a build's build.json. Returns the build dir or None."""
    resolved = resolve_build(build_uuid)
    if not resolved:
        return None
    cfg, ts, bdir = resolved
    data = read_build(cfg, ts) or {'artifacts': []}
    artifacts = data.get('artifacts', [])
    if filename not in artifacts:
        artifacts.append(filename)
    data['artifacts'] = artifacts
    data['updated_at'] = utc_stamp()
    write_build(cfg, ts, data)
    return bdir


def build_artifact_path(cfg, ts, filename):
    """Absolute path to an artifact, validated to stay inside the build dir."""
    bdir = build_dir(cfg, ts)
    path = os.path.abspath(os.path.join(bdir, filename))
    if path != os.path.join(bdir, os.path.basename(filename)):
        raise ValueError(f'artifact escapes build dir: {filename!r}')
    return path
