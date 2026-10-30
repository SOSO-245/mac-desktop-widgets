#!/usr/bin/env python3
"""Audit and sign only API Usage releases; the private key stays in Keychain."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, plistlib, re, subprocess, tempfile, zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
REPO = 'https://github.com/SOSO-245/mac-desktop-widgets'
ET.register_namespace('sparkle', SPARKLE)


def audit(assets):
    rows = json.loads((assets / 'manifest.json').read_text())
    if not isinstance(rows, list) or len(rows) != 1 or rows[0].get('project') != 'api-usage':
        raise ValueError('Expected exactly one API Usage release')
    row = rows[0]
    if row.get('archive') != 'api-usage-macos.zip':
        raise ValueError('Unexpected archive filename')
    archive = assets / row['archive']
    if hashlib.sha256(archive.read_bytes()).hexdigest() != row.get('sha256'):
        raise ValueError('Archive changed after build audit')
    config = json.loads((ROOT / 'projects/api-usage/Updater/config.json').read_text())
    with zipfile.ZipFile(archive) as package:
        if package.testzip() is not None:
            raise ValueError('Archive CRC mismatch')
        paths = [n for n in package.namelist() if n.count('/') == 2 and n.endswith('.app/Contents/Info.plist')]
        if len(paths) != 1 or any('.appex/' in n for n in package.namelist()):
            raise ValueError('Expected one application and no widget extensions')
        info = plistlib.loads(package.read(paths[0]))
        if info.get('CFBundleIdentifier') != 'local.homeatlas.APIUsage':
            raise ValueError('Application identity mismatch')
        for name, pattern in [('CFBundleShortVersionString', r'\d+\.\d+\.\d+'), ('CFBundleVersion', r'\d{14}')]:
            if not re.fullmatch(pattern, info.get(name, '')):
                raise ValueError('Invalid version/build')
        if config['feed_url'] != 'https://raw.githubusercontent.com/SOSO-245/mac-desktop-widgets/main/updates/api-usage.xml':
            raise ValueError('Unexpected feed URL')
        if info.get('SUFeedURL') != config['feed_url'] or info.get('SUPublicEDKey') != config['public_key']:
            raise ValueError('Embedded feed/key mismatch')
        if any(info.get(k) is not True for k in ['SURequireSignedFeed', 'SUVerifyUpdateBeforeExtraction']):
            raise ValueError('Update verification disabled')
        for name, key in [('version', 'CFBundleShortVersionString'), ('build', 'CFBundleVersion')]:
            if name in row and row[name] != info[key]:
                raise ValueError('Manifest version/build mismatch')
    with tempfile.TemporaryDirectory(prefix='api-release-audit-') as temp:
        subprocess.run(['ditto', '--norsrc', '-x', '-k', str(archive), temp], check=True)
        apps = list(Path(temp).glob('*.app'))
        if len(apps) != 1:
            raise ValueError('Invalid extracted application count')
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(apps[0])], check=True)
    return rows, row, archive, info, config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--tag')
    parser.add_argument('--account')
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    rows, row, archive, info, config = audit(args.assets)
    if args.check_only:
        print('CHECKED API Usage', info['CFBundleShortVersionString'], info['CFBundleVersion'])
        return
    if not args.account or not args.tag or not re.fullmatch(r'v[A-Za-z0-9.-]+', args.tag):
        parser.error('Signing requires --account and a valid --tag')
    spec = importlib.util.spec_from_file_location('helper', ROOT / 'projects/api-usage/updater_build.py')
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    binaries = helper.prepare(ROOT / 'projects/api-usage') / 'bin'
    public = subprocess.check_output([str(binaries / 'generate_keys'), '--account', args.account, '-p'], text=True).strip()
    if public != config['public_key']:
        raise ValueError('Signing account does not match embedded public key')
    def sign(path, *extra):
        return subprocess.check_output([str(binaries / 'sign_update'), '--account', args.account, *extra, str(path)], text=True).strip()
    signature = sign(archive, '-p')
    if hashlib.sha256(archive.read_bytes()).hexdigest() != row['sha256']:
        raise ValueError('Archive changed during signing')
    rss = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'API 用量卡片 软件更新'
    ET.SubElement(channel, 'link').text = REPO + '/releases'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = info['CFBundleShortVersionString']
    for name, value in [('version', info['CFBundleVersion']), ('shortVersionString', info['CFBundleShortVersionString']), ('minimumSystemVersion', '14.0')]:
        ET.SubElement(item, '{' + SPARKLE + '}' + name).text = value
    ET.SubElement(item, 'description').text = '新增硅基流动独立网页登录与手动账单缓存，安全登录会话仅存本机钥匙串。大号上下分区、中号左图表右余额，统一余额字体与连续圆角边框。保留原 API 连接与软件更新。应用仍未经过 Apple 公证。'
    ET.SubElement(item, 'enclosure', {'url': f'{REPO}/releases/download/{args.tag}/{archive.name}', 'length': str(archive.stat().st_size), 'type': 'application/octet-stream', '{' + SPARKLE + '}edSignature': signature})
    output = ROOT / 'updates'; output.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.signed-api-', dir=output) as temp:
        feed = Path(temp) / 'api-usage.xml'
        ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
        sign(feed); sign(feed, '--verify')
        feed.replace(output / feed.name)
    row.update(version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'])
    (args.assets / 'manifest.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
    print('SIGNED API Usage; upload and verify release assets before publishing the feed.')


if __name__ == '__main__':
    main()
