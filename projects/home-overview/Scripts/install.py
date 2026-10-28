#!/usr/bin/env python3
"""Explicit, local-only installation with verified app backups and automatic rollback.

Usage: python3 Scripts/install.py --app /path/to/家庭概览.app
       python3 Scripts/install.py --rollback /path/to/installation-backup

HomeEnergy settings, Keychain items and desktop widget placements are never edited.
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
APPLICATIONS = pathlib.Path.home() / 'Applications'
DESTINATION = APPLICATIONS / '家庭概览.app'
BUNDLE_ID = 'local.homeatlas.HomeEnergy'
WIDGET_ID = BUNDLE_ID + '.Widget'
LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
ALLOWED = {
    '家庭用电.app': BUNDLE_ID,
    '家庭概览.app': BUNDLE_ID,
    '家庭概览预览.app': 'local.homeatlas.tvpreview.mac',
}


def run(args, *, check=True):
    return subprocess.run([str(arg) for arg in args], check=check)


def metadata(app):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        return plistlib.load(stream)


def verify_identity(app, bundle_id):
    if app.is_symlink() or not app.is_dir():
        raise RuntimeError(f'Expected a real app directory: {app}')
    if metadata(app).get('CFBundleIdentifier') != bundle_id:
        raise RuntimeError(f'Unexpected application identity; leaving it untouched: {app}')


def verify(app, bundle_id):
    verify_identity(app, bundle_id)
    run(['codesign', '--verify', '--deep', '--strict', app])


def widget(app):
    return app / 'Contents/PlugIns/HomeEnergyWidget.appex'


def unregister(app):
    # Missing registrations are normal for a never-launched build or staging copy.
    subprocess.run([LSREGISTER, '-u', str(app)], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if widget(app).is_dir():
        subprocess.run(['pluginkit', '-r', str(widget(app))], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def register(app):
    run([LSREGISTER, '-f', app])
    if widget(app).is_dir():
        run(['pluginkit', '-a', widget(app)])


def processes(apps):
    """Only same-user processes whose executable lives in an exact selected app."""
    result = subprocess.run(['/bin/ps', '-axo', 'uid=,pid=,comm='],
                            check=True, text=True, capture_output=True)
    matches = {}
    for line in result.stdout.splitlines():
        fields = line.strip().split(maxsplit=2)
        if len(fields) != 3 or not fields[0].isdigit() or not fields[1].isdigit():
            continue
        if int(fields[0]) != os.getuid():
            continue
        executable = pathlib.Path(fields[2])
        for app in apps:
            if executable.is_relative_to(app / 'Contents'):
                matches[int(fields[1])] = app.name
    return matches


def stop(apps):
    running = processes(apps)
    for pid in running:
        # Refresh PID/path membership before sending a signal to avoid PID reuse.
        if pid in processes(apps):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.monotonic() + 10
    while processes(apps):
        if time.monotonic() > deadline:
            raise RuntimeError('An application did not exit. No force kill was attempted.')
        time.sleep(0.2)
    return sorted(set(running.values()))


def write_manifest(folder, manifest):
    temporary = folder / '.manifest.pending.json'
    temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(folder / 'manifest.json')


def check_archive(path, digest):
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise RuntimeError(f'Backup checksum mismatch: {path}')
    run(['unzip', '-tqq', path])


def load_rollback(folder):
    folder = folder.resolve()
    manifest = json.loads((folder / 'manifest.json').read_text())
    if manifest.get('applications_directory') != str(APPLICATIONS):
        raise RuntimeError('This backup belongs to a different Applications directory.')
    originals = manifest.get('originals', [])
    names = [entry.get('name') for entry in originals]
    if len(names) != len(set(names)):
        raise RuntimeError('Duplicate backup entries.')
    for entry in originals:
        if entry.get('name') not in ALLOWED or entry.get('bundle_id') != ALLOWED[entry['name']]:
            raise RuntimeError('Unexpected backup application.')
        if entry.get('archive') != entry['name'] + '.zip':
            raise RuntimeError('Unexpected archive path.')
        check_archive(folder / entry['archive'], entry['sha256'])
    return manifest


def rollback(folder, *, launch=True):
    manifest = load_rollback(folder)
    # Fully extract and validate all originals before removing the replacement.
    with tempfile.TemporaryDirectory(prefix='homeatlas-restore-') as scratch:
        scratch = pathlib.Path(scratch)
        for entry in manifest['originals']:
            run(['ditto', '-x', '-k', folder / entry['archive'], scratch])
            verify(scratch / entry['name'], entry['bundle_id'])
        current = [APPLICATIONS / name for name in ALLOWED if (APPLICATIONS / name).exists()]
        for app in current:
            # The replacement itself may have failed strict signature verification.
            # Only an exact allowlisted path with the expected bundle identity may
            # be removed; recovered originals above must still pass strict signing.
            verify_identity(app, ALLOWED[app.name])
        stop(current)
        for app in current:
            unregister(app)
            shutil.rmtree(app)
        for entry in manifest['originals']:
            app = APPLICATIONS / entry['name']
            run(['ditto', '--norsrc', scratch / entry['name'], app])
            run(['xattr', '-cr', app])
            verify(app, entry['bundle_id'])
            unregister(scratch / entry['name'])
            register(app)
    manifest['status'] = 'rolled_back'
    write_manifest(folder, manifest)
    if launch:
        original_names = {entry['name'] for entry in manifest['originals']}
        for name in manifest.get('previously_running', []):
            if name in original_names:
                run(['open', APPLICATIONS / name])
    print('Restored original applications from:', folder)


def install(source, *, launch=True):
    source = source.resolve()
    if any(source.is_relative_to(APPLICATIONS / name) for name in ALLOWED):
        raise RuntimeError('Build output must be outside the installed application paths.')
    verify(source, BUNDLE_ID)
    verify(widget(source), WIDGET_ID)
    if metadata(source).get('CFBundleShortVersionString') not in {'2.0.0', '2.0.1', '2.0.2', '2.0.3', '2.0.4', '2.0.5', '2.1.0', '2.1.1', '2.2.0', '2.2.1', '2.2.2', '2.2.3', '2.3.0', '2.3.1', '2.3.2', '2.3.9', '2.3.10', '2.4.0', '2.4.1', '2.4.2', '2.4.3'}:
        raise RuntimeError('Expected a supported merged 2.0.x application.')
    if set(metadata(source).get('CFBundleURLTypes', [{}])[0].get('CFBundleURLSchemes', [])) != {'homeenergy', 'homeatlas'}:
        raise RuntimeError('The merged application must handle both existing URL schemes.')
    originals = [APPLICATIONS / name for name in ALLOWED if (APPLICATIONS / name).exists()]
    for app in originals:
        verify(app, ALLOWED[app.name])
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8]
    backup = ROOT / '备份' / ('合并安装前-' + stamp)
    backup.mkdir(parents=True)
    manifest = {'format': 1, 'applications_directory': str(APPLICATIONS),
                'created': datetime.datetime.now().isoformat(timespec='seconds'),
                'status': 'preparing', 'originals': [], 'previously_running': []}
    for app in originals:
        archive = backup / (app.name + '.zip')
        run(['ditto', '-c', '-k', '--norsrc', '--keepParent', app, archive])
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        check_archive(archive, digest)
        manifest['originals'].append({'name': app.name, 'bundle_id': ALLOWED[app.name],
                                      'archive': archive.name, 'sha256': digest})
    manifest['status'] = 'backed_up'
    write_manifest(backup, manifest)
    print('Verified rollback backup:', backup)
    staging = APPLICATIONS / ('.家庭概览-install-' + uuid.uuid4().hex + '.app')
    mutation_started = False
    try:
        run(['ditto', '--norsrc', source, staging])
        run(['xattr', '-cr', staging])
        verify(staging, BUNDLE_ID)
        # Record running apps before any termination for both automatic/manual recovery.
        manifest['previously_running'] = sorted(set(processes(originals).values()))
        write_manifest(backup, manifest)
        mutation_started = True
        stop(originals)
        for app in originals:
            unregister(app)
            shutil.rmtree(app)
        unregister(source)
        unregister(staging)
        staging.rename(DESTINATION)
        verify(DESTINATION, BUNDLE_ID)
        register(DESTINATION)
        if launch:
            run(['open', DESTINATION])
        manifest['status'] = 'installed'
        manifest['installed_app'] = str(DESTINATION)
        write_manifest(backup, manifest)
        print('Installed:', DESTINATION)
        print('Rollback: python3 Scripts/install.py --rollback', backup)
    except BaseException:
        if mutation_started:
            try:
                rollback(backup, launch=launch)
            except Exception as recovery_error:
                print('Automatic rollback could not complete:', recovery_error)
                print('Verified backups are retained at:', backup)
        raise
    finally:
        if staging.exists():
            unregister(staging)
            shutil.rmtree(staging)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--app', type=pathlib.Path, help='Install this verified build output.')
    action.add_argument('--rollback', type=pathlib.Path, help='Restore an installation backup.')
    parser.add_argument('--no-launch', action='store_true', help='Leave apps closed after installation/restoration.')
    args = parser.parse_args()
    APPLICATIONS.mkdir(exist_ok=True)
    # Serialize cooperating installers. No per-user configuration is touched.
    with (ROOT / '.installation.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.rollback:
            rollback(args.rollback.resolve(), launch=not args.no_launch)
        else:
            install(args.app, launch=not args.no_launch)


if __name__ == '__main__':
    main()
