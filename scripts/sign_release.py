#!/usr/bin/env python3
"""Sign all six audited Mac feeds; Scriptable changes require an explicit flag.

Private keys remain in the macOS Keychain. Never pass/export key contents.
--check-only validates release metadata without signing or changing any files.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import plistlib
import re
import subprocess
import tempfile
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
REPOSITORY = 'https://github.com/SOSO-245/mac-desktop-widgets'
RAW = 'https://raw.githubusercontent.com/SOSO-245/mac-desktop-widgets'
ET.register_namespace('sparkle', SPARKLE)
PRODUCTS = {
    'home-overview': 'local.homeatlas.HomeEnergy',
    'lunar-calendar': 'local.homeatlas.LunarCalendar',
    'codex-resets': 'local.homeatlas.CodexResets',
    'vpn-card': 'local.homeatlas.FlClashMonitor',
    'nikki-card': 'local.homeatlas.NikkiMonitor',
    'mac-vitals': 'local.homeatlas.MacVitals',
}
NOTES = {
    'home-overview': '家庭概览重新公开：原生与动画皮肤、黄鸭与白天鹅、生日和天气装扮、平滑水面互动；需要填写自己的 HA 连接。',
    'lunar-calendar': '新增贴边霜纹、蒲公英大风与间歇雷雨闪电；保留日期天气卡片、生日提醒、日程和可选 iCloud 文件夹同步。',
    'codex-resets': '小号经过天数下展示最近重置时间，X 图标打开对应公告原帖；保留感谢互动、电纹提醒、官网入口与独立刷新；跨卡片闪电落水触发鸭子短闪。',
    'vpn-card': '统一桌面、菜单栏、数据与更新设置；新增节点选择与测速。切换图标左键仍切换来源并打开客户端，右键选节点；过滤套餐提示和重名歧义，关闭窗口取消未完成请求，不启停 VPN。',
    'nikki-card': '套餐定时更新默认每小时，可关闭、调整或立即刷新；只更新当前匹配的 HTTP 订阅，不主动切换节点。',
    'mac-vitals': '真实功率曲线采用顺滑弧线和柔和辉光；网速轻量双向动画，新增五档温度表情与实际风扇 RPM，90°C 起进入红色档。',
}


def audit_assets(assets):
    rows = json.loads((assets / 'manifest.json').read_text())
    if not isinstance(rows, list):
        raise ValueError('Expected all six audited apps')
    feeds = [row for row in rows if row.get('project') not in ['desktop-toolbox','api-usage']]
    if len(feeds) != len(PRODUCTS) or {row.get('project') for row in feeds} != set(PRODUCTS) or len(rows)-len(feeds)>2:
        raise ValueError('Expected one entry for each known app')
    toolbox = [row for row in rows if row.get('project') in ['desktop-toolbox','api-usage']]
    if len({row['project'] for row in toolbox}) != len(toolbox):
        raise ValueError('Duplicate manual app')
    for row in toolbox:
        if row.get('archive') != row['project'] + '-macos.zip':
            raise ValueError('Unexpected toolbox archive')
        path = assets / row['archive']
        if hashlib.sha256(path.read_bytes()).hexdigest() != row.get('sha256'):
            raise ValueError('Toolbox archive changed after audit')
        with zipfile.ZipFile(path) as package:
            if package.testzip() is not None:
                raise ValueError('Toolbox CRC mismatch')
            names = [n for n in package.namelist() if n.count('/') == 2 and n.endswith('.app/Contents/Info.plist')]
            if len(names) != 1:
                raise ValueError('Expected one toolbox app')
            info = plistlib.loads(package.read(names[0]))
            if info['CFBundleIdentifier'] != {'desktop-toolbox':'local.homeatlas.Toolbox','api-usage':'local.homeatlas.APIUsage'}[row['project']]:
                raise ValueError('Toolbox identity mismatch')
            for key, source in [('version','CFBundleShortVersionString'),('build','CFBundleVersion')]:
                if row.get(key) != info[source]:
                    raise ValueError('Toolbox version mismatch')
    audited = []
    for row in feeds:
        slug = row['project']
        if row.get('archive') != slug + '-macos.zip':
            raise ValueError('Unexpected archive filename: ' + slug)
        archive = assets / row['archive']
        if hashlib.sha256(archive.read_bytes()).hexdigest() != row.get('sha256'):
            raise ValueError('Archive changed after audit: ' + slug)
        with zipfile.ZipFile(archive) as package:
            if package.testzip() is not None:
                raise ValueError('Archive CRC check failed: ' + slug)
            names = [name for name in package.namelist() if name.count('/') == 2 and name.endswith('.app/Contents/Info.plist')]
            if len(names) != 1:
                raise ValueError('Expected one top-level application: ' + slug)
            info = plistlib.loads(package.read(names[0]))
            version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
            if info['CFBundleIdentifier'] != PRODUCTS[slug]:
                raise ValueError('Application identity mismatch: ' + slug)
            if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'\d{14}', build):
                raise ValueError('Invalid application version/build: ' + slug)
            for key, value in (('version', version), ('build', build)):
                if key in row and row[key] != value:
                    raise ValueError('Manifest ' + key + ' differs from bundle: ' + slug)
            config = json.loads((ROOT / 'projects' / slug / 'Updater/config.json').read_text())
            expected_feed = RAW + '/main/updates/' + slug + '.xml'
            if info.get('SUPublicEDKey') != config['public_key'] or info.get('SUFeedURL') != config['feed_url'] or config['feed_url'] != expected_feed:
                raise ValueError('Embedded updater key/feed mismatch: ' + slug)
            if info.get('SURequireSignedFeed') is not True or info.get('SUVerifyUpdateBeforeExtraction') is not True:
                raise ValueError('Required update verification is disabled: ' + slug)
            widgets = [name for name in package.namelist() if name.endswith('.appex/Contents/Info.plist')]
            if len(widgets) != (0 if slug == 'vpn-card' else 1):
                raise ValueError('Unexpected WidgetKit extension count: ' + slug)
            for name in widgets:
                widget = plistlib.loads(package.read(name))
                if (widget['CFBundleIdentifier'], widget['CFBundleShortVersionString'], widget['CFBundleVersion']) != (PRODUCTS[slug] + '.Widget', version, build):
                    raise ValueError('Host/widget version mismatch: ' + slug)
        audited.append((row, archive, info))
    return rows, audited


def scriptable_manifest(tag):
    phone = ROOT / 'projects/codex-resets/scriptable/CodexResets.js'
    source = phone.read_bytes()
    versions = re.findall(rb'^const SCRIPT_VERSION = "(\d+\.\d+\.\d+)";', source, flags=re.MULTILINE)
    if len(versions) != 1:
        raise ValueError('Expected one explicit Scriptable version')
    return dict(product='codex-resets-scriptable', version=versions[0].decode(),
                sha256=hashlib.sha256(source).hexdigest(),
                url=f'{RAW}/{tag}/projects/codex-resets/scriptable/CodexResets.js',
                notes='在 Scriptable 中手动检查并确认更新，校验下载后保留旧版备份。')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--tag')
    parser.add_argument('--account')
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--include-scriptable', action='store_true', help='Also rewrite the unchanged-by-default phone feed for this tag')
    args = parser.parse_args()
    if not args.check_only and (not args.tag or not args.account):
        parser.error('--tag and --account are required when signing')
    if args.tag is not None and not re.fullmatch(r'v[A-Za-z0-9.-]+', args.tag):
        raise ValueError('Invalid tag')
    if args.include_scriptable and not args.tag:
        parser.error('--include-scriptable requires --tag')
    rows, audited = audit_assets(args.assets)
    phone = scriptable_manifest(args.tag) if args.include_scriptable else None
    if args.check_only:
        for row, _, info in audited:
            print('CHECKED', row['project'], info['CFBundleShortVersionString'], info['CFBundleVersion'])
        print('No files changed; no signing tools or Keychain access used.')
        return

    spec = importlib.util.spec_from_file_location('updater_build', ROOT / 'projects/codex-resets/updater_build.py')
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    tool = helper.prepare(ROOT / 'projects/codex-resets') / 'bin/sign_update'

    def sign(path, *extra):
        return subprocess.check_output([str(tool), '--account', args.account, *extra, str(path)], text=True).strip()

    output = ROOT / 'updates'
    output.mkdir(exist_ok=True)
    # Validate all six inputs first, then sign/verify staged feeds before replacing
    # any existing feed. A missing key or failed signature leaves published files.
    with tempfile.TemporaryDirectory(prefix='.signed-feeds-', dir=output) as temporary:
        stage = Path(temporary)
        for row, archive, info in audited:
            slug = row['project']
            if hashlib.sha256(archive.read_bytes()).hexdigest() != row['sha256']:
                raise ValueError('Archive changed before signing: ' + slug)
            signature = sign(archive, '-p')
            if hashlib.sha256(archive.read_bytes()).hexdigest() != row['sha256']:
                raise ValueError('Archive changed while signing: ' + slug)
            rss = ET.Element('rss', {'version': '2.0'})
            channel = ET.SubElement(rss, 'channel')
            ET.SubElement(channel, 'title').text = info['CFBundleName'] + ' 软件更新'
            ET.SubElement(channel, 'link').text = REPOSITORY + '/releases'
            item = ET.SubElement(channel, 'item')
            ET.SubElement(item, 'title').text = info['CFBundleShortVersionString']
            for name, value in (('version', info['CFBundleVersion']), ('shortVersionString', info['CFBundleShortVersionString']), ('minimumSystemVersion', '14.0')):
                ET.SubElement(item, '{' + SPARKLE + '}' + name).text = value
            ET.SubElement(item, 'description').text = NOTES[slug] + ' 各款软件保持独立。应用仍未经过 Apple 公证，macOS 可能要求确认已有读取权限。'
            ET.SubElement(item, 'enclosure', {'url': f'{REPOSITORY}/releases/download/{args.tag}/{archive.name}',
                'length': str(archive.stat().st_size), 'type': 'application/octet-stream', '{' + SPARKLE + '}edSignature': signature})
            feed = stage / (slug + '.xml')
            ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
            sign(feed)
            sign(feed, '--verify')
            row.update(version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'])
        if phone is not None:
            (stage / 'codex-resets-scriptable.json').write_text(json.dumps(phone, ensure_ascii=False, indent=2) + '\n')
        for feed in sorted(stage.iterdir()):
            feed.replace(output / feed.name)
    (args.assets / 'manifest.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
    for row in rows:
        if row['project'] in PRODUCTS: print('SIGNED', row['project'], row['version'])
    print('Scriptable feed updated.' if phone is not None else 'Scriptable feed left unchanged.')
    print('Signed feeds created; publication is a separate operation.')


if __name__ == '__main__':
    main()
