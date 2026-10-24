#!/usr/bin/env python3
"""Build the native live card with Command Line Tools; --install installs it locally."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent
NAME = 'Mac 实时监测'
BUNDLE = 'local.homeatlas.MacVitals'

def run(*args):
    subprocess.run([str(x) for x in args], check=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true')
    args = parser.parse_args()
    stage = Path(tempfile.mkdtemp(prefix='mac-vitals-build-'))
    app = stage / (NAME + '.app')
    macos = app / 'Contents/MacOS'
    resources = app / 'Contents/Resources'
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    info = dict(CFBundleDevelopmentRegion='zh_CN', CFBundleName=NAME,
                CFBundleDisplayName=NAME, CFBundleExecutable='MacVitals',
                CFBundleIdentifier=BUNDLE, CFBundlePackageType='APPL',
                CFBundleShortVersionString='1.0.0',
                CFBundleVersion=datetime.datetime.now().strftime('%Y%m%d%H%M%S'),
                LSMinimumSystemVersion='14.0', LSUIElement=True,
                NSHighResolutionCapable=True, NSPrincipalClass='NSApplication',
                NSLocalNetworkUsageDescription='供桌面小组件读取本机只读状态快照。')
    info['CFBundleURLTypes'] = [dict(CFBundleURLName=BUNDLE+'.navigation',CFBundleURLSchemes=['macvitals'])]
    icon = ROOT / 'Assets/AppIcon.icns'
    if icon.exists():
        run('ditto', '--norsrc', icon, resources / 'AppIcon.icns')
        info['CFBundleIconFile'] = 'AppIcon'
    run('ditto', '--norsrc', ROOT / 'Vendor/macmon', resources / 'macmon')
    run('ditto', '--norsrc', ROOT / 'Vendor/LICENSE', resources / 'macmon-LICENSE')
    run('codesign', '--force', '--sign', '-', resources / 'macmon')
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    sources = sorted((ROOT / 'Sources').glob('*.swift'))
    binaries = []
    for arch in ('arm64',):
        binary = stage / ('MacVitals-' + arch)
        run('xcrun', 'swiftc', '-swift-version', '5', '-O', '-parse-as-library',
            '-target', arch + '-apple-macosx14.0', '-sdk', sdk,
            *sources, '-o', binary)
        binaries.append(binary)
    run('lipo', '-create', *binaries, '-output', macos / 'MacVitals')
    run('python3', ROOT / 'Widget/build_widget.py', app)
    run('xattr', '-cr', app)
    run('codesign', '--force', '--sign', '-', app)
    run('codesign', '--verify', '--deep', '--strict', app)
    output = app
    if args.install:
        output = Path.home() / 'Applications' / app.name
        if output.exists():
            raise RuntimeError('Installed copy exists: preserve it and stop its process before updating.')
        output.parent.mkdir(parents=True, exist_ok=True)
        run('ditto', '--norsrc', app, output)
        run('xattr', '-cr', output)
        run('codesign', '--verify', '--deep', '--strict', output)
        run('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-f', output)
    delivery = ROOT / '交付'
    delivery.mkdir(exist_ok=True)
    archive = delivery / 'Mac实时监测-Mac.zip'
    run('ditto', '-c', '-k', '--norsrc', '--keepParent', output, archive)
    sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    source_archive = delivery / 'Mac实时监测-源码.zip'
    with zipfile.ZipFile(source_archive, 'w', compression=zipfile.ZIP_DEFLATED) as package:
        for folder in ('Sources', 'Tests', 'Assets', 'Widget'):
            for file in sorted((ROOT / folder).rglob('*')):
                if file.is_file():
                    package.write(file, Path(ROOT.name) / file.relative_to(ROOT))
        for file in (ROOT/'Vendor/macmon', ROOT/'Vendor/LICENSE'):
            package.write(file, Path(ROOT.name)/file.relative_to(ROOT))
        for name in ('项目说明.md', '注意要点.md', 'build.py'):
            package.write(ROOT / name, Path(ROOT.name) / name)
    source_sha = hashlib.sha256(source_archive.read_bytes()).hexdigest()
    (delivery / 'SHA256SUMS').write_text(sha + '  ' + archive.name + '\n' +
                                       source_sha + '  ' + source_archive.name + '\n')
    record = dict(app=str(output), build_app=str(app), installed=args.install, sha256=sha)
    (delivery / 'build-result.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(record, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
