"""Pinned Sparkle dependency and bundle metadata. No private signing keys here."""
from pathlib import Path
import fcntl
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import tempfile

VERSION = '2.10.0'
SHA256 = 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c'
URL = 'https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz'

def prepare(root):
    cache = Path.home() / 'Library/Caches/mac-desktop-widgets-build'
    cache.mkdir(parents=True, exist_ok=True)
    unpacked = cache / ('Sparkle-' + VERSION)
    with (cache / 'download.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        archive = cache / ('Sparkle-' + VERSION + '.tar.xz')
        if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
            with tempfile.TemporaryDirectory(dir=cache) as tmp:
                candidate = Path(tmp) / archive.name
                subprocess.run(['curl', '-fL', '--retry', '2', '--max-time', '120', URL, '-o', str(candidate)], check=True)
                if hashlib.sha256(candidate.read_bytes()).hexdigest() != SHA256:
                    raise RuntimeError('Sparkle archive checksum mismatch')
                candidate.replace(archive)
        if not (unpacked / 'Sparkle.framework').is_dir():
            with tempfile.TemporaryDirectory(dir=cache) as tmp:
                target = Path(tmp) / 'unpacked'; target.mkdir()
                subprocess.run(['tar', '-xf', str(archive), '-C', str(target)], check=True)
                subprocess.run(['codesign', '--verify', '--deep', '--strict', str(target/'Sparkle.framework')], check=True)
                target.rename(unpacked)
    return unpacked

def compile_flags(root):
    return ['-F', str(prepare(root)), '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks']

def xcode_settings(root, quote):
    return {'FRAMEWORK_SEARCH_PATHS':quote('$(inherited) "' + str(prepare(root)) + '"'),
            'OTHER_LDFLAGS':quote('$(inherited) -framework Sparkle')}

def finish(root, app):
    root, app = Path(root), Path(app)
    config = json.loads((root/'Updater/config.json').read_text())
    if not config['feed_url'].startswith('https://raw.githubusercontent.com/SOSO-245/mac-desktop-widgets/main/updates/'):
        raise ValueError('Unexpected update feed')
    framework = app/'Contents/Frameworks/Sparkle.framework'; framework.parent.mkdir(exist_ok=True)
    if framework.exists(): shutil.rmtree(framework)
    subprocess.run(['ditto', '--norsrc', str(prepare(root)/'Sparkle.framework'), str(framework)], check=True)
    info_path = app/'Contents/Info.plist'; info = plistlib.loads(info_path.read_bytes())
    info.update(SUFeedURL=config['feed_url'], SUPublicEDKey=config['public_key'],
                SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=False,
                SUScheduledCheckInterval=86400, SUAllowsAutomaticUpdates=True,
                SUEnableSystemProfiling=False, SURequireSignedFeed=True,
                SUVerifyUpdateBeforeExtraction=True)
    info_path.write_bytes(plistlib.dumps(info))
    # Unsigned local builds use ad-hoc identity. Public Developer ID signing and
    # notarization are a separate release step when that certificate is available.
    identity = os.environ.get('WIDGET_CODE_SIGN_IDENTITY', '-')
    subprocess.run(['xattr', '-cr', str(app)], check=True)
    subprocess.run(['codesign', '--force', '--sign', identity, str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
