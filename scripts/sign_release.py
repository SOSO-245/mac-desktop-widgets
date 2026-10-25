#!/usr/bin/env python3
"""Create independently signed Sparkle feeds from already audited release ZIPs.

Private keys remain in the macOS Keychain. Never pass/export key contents.
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json, plistlib, subprocess, zipfile
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
SPARKLE='http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle',SPARKLE)

def main():
    p=argparse.ArgumentParser();p.add_argument('--assets',type=Path,required=True);p.add_argument('--tag',required=True);p.add_argument('--account',required=True);args=p.parse_args()
    if not args.tag.startswith('v') or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-' for c in args.tag):raise ValueError('Invalid tag')
    spec=importlib.util.spec_from_file_location('updater_build',ROOT/'projects/codex-resets/updater_build.py');helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
    tool=helper.prepare(ROOT/'projects/codex-resets')/'bin/sign_update'
    def sign(path,*extra):return subprocess.check_output([str(tool),'--account',args.account,*extra,str(path)],text=True).strip()
    output=ROOT/'updates';output.mkdir(exist_ok=True)
    rows=json.loads((args.assets/'manifest.json').read_text())
    if len(rows)!=6:raise ValueError('Expected all six audited apps')
    for row in rows:
        slug=row['project'];archive=args.assets/row['archive']
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=row['sha256']:raise ValueError('Archive changed after audit: '+slug)
        with zipfile.ZipFile(archive) as z:
            names=[n for n in z.namelist() if n.count('/')==2 and n.endswith('.app/Contents/Info.plist')]
            if len(names)!=1:raise ValueError('Expected one top-level application')
            info=plistlib.loads(z.read(names[0]))
            config=json.loads((ROOT/'projects'/slug/'Updater/config.json').read_text())
            assert info['SUPublicEDKey']==config['public_key'] and info['SUFeedURL']==config['feed_url']
        sig=sign(archive,'-p')
        rss=ET.Element('rss',{'version':'2.0'});channel=ET.SubElement(rss,'channel')
        ET.SubElement(channel,'title').text=info['CFBundleName']+' 软件更新'
        ET.SubElement(channel,'link').text='https://github.com/SOSO-245/mac-desktop-widgets/releases'
        item=ET.SubElement(channel,'item');ET.SubElement(item,'title').text=info['CFBundleShortVersionString']
        for name,value in [('version',info['CFBundleVersion']),('shortVersionString',info['CFBundleShortVersionString']),('minimumSystemVersion','14.0')]:ET.SubElement(item,'{'+SPARKLE+'}'+name).text=value
        ET.SubElement(item,'description').text='新增每天自动检查、更新提示和可选自动安装；保留配置、卡片布局与原登录启动设置。此版本仍未经过 Apple 公证，macOS 可能要求重新确认已有读取权限。'
        ET.SubElement(item,'enclosure',{'url':f'https://github.com/SOSO-245/mac-desktop-widgets/releases/download/{args.tag}/{archive.name}','length':str(archive.stat().st_size),'type':'application/octet-stream','{'+SPARKLE+'}edSignature':sig})
        feed=output/(slug+'.xml');ET.ElementTree(rss).write(feed,encoding='utf-8',xml_declaration=True)
        sign(feed);sign(feed,'--verify')
        row.update(version=info['CFBundleShortVersionString'],build=info['CFBundleVersion'])
        print('SIGNED',slug,row['version'])
    (args.assets/'manifest.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
    phone=ROOT/'projects/codex-resets/scriptable/CodexResets.js'
    (output/'codex-resets-scriptable.json').write_text(json.dumps(dict(product='codex-resets-scriptable',version='1.1.0',sha256=hashlib.sha256(phone.read_bytes()).hexdigest(),url=f'https://raw.githubusercontent.com/SOSO-245/mac-desktop-widgets/{args.tag}/projects/codex-resets/scriptable/CodexResets.js',notes='新增手动检查脚本更新，确认后校验下载并保留旧版备份。'),ensure_ascii=False,indent=2)+'\n')
    print('Signed feeds created; publication is a separate operation.')

if __name__=='__main__':main()
