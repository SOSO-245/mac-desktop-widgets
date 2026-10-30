#!/usr/bin/env python3
"""Sign explicitly selected suite products; keys stay in the macOS Keychain."""
import argparse,hashlib,importlib.util,json,plistlib,re,subprocess,tempfile,zipfile
from pathlib import Path
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
IDS={'desktop-toolbox':'local.homeatlas.Toolbox','nikki-card':'local.homeatlas.NikkiMonitor'}
NS='http://www.andymatuschak.org/xml-namespaces/sparkle';ET.register_namespace('sparkle',NS)
p=argparse.ArgumentParser();p.add_argument('--assets',type=Path,required=True);p.add_argument('--tag',required=True);p.add_argument('--account',required=True);a=p.parse_args()
assert re.fullmatch(r'v[A-Za-z0-9.-]+',a.tag)
spec=importlib.util.spec_from_file_location('helper',ROOT/'projects/desktop-toolbox/updater_build.py');helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
bin=helper.prepare(ROOT/'projects/desktop-toolbox')/'bin'
public=subprocess.check_output([str(bin/'generate_keys'),'--account',a.account,'-p'],text=True).strip()
rows=json.loads((a.assets/'manifest.json').read_text());assert {r['project'] for r in rows}==set(IDS)
feeds=[]
for row in rows:
 slug=row['project'];zpath=a.assets/row['archive'];assert zpath.name==slug+'-macos.zip';assert hashlib.sha256(zpath.read_bytes()).hexdigest()==row['sha256']
 with zipfile.ZipFile(zpath) as z:
  assert z.testzip() is None
  names=[n for n in z.namelist() if n.count('/')==2 and n.endswith('.app/Contents/Info.plist')];assert len(names)==1
  info=plistlib.loads(z.read(names[0]))
 config=json.loads((ROOT/'projects'/slug/'Updater/config.json').read_text())
 assert info['CFBundleIdentifier']==IDS[slug] and info['SUPublicEDKey']==config['public_key']==public
 assert info['SUFeedURL']==config['feed_url']=='https://raw.githubusercontent.com/SOSO-245/mac-desktop-widgets/main/updates/'+slug+'.xml'
 assert info['SURequireSignedFeed'] and info['SUVerifyUpdateBeforeExtraction']
 with tempfile.TemporaryDirectory() as temp:
  subprocess.run(['ditto','-x','-k',str(zpath),temp],check=True);app=next(Path(temp).glob('*.app'));subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
 row.update(version=info['CFBundleShortVersionString'],build=info['CFBundleVersion'])
 feeds.append((row,zpath))
def sign(path,*extra):return subprocess.check_output([str(bin/'sign_update'),'--account',a.account,*extra,str(path)],text=True).strip()
with tempfile.TemporaryDirectory() as temp:
 for row,zpath in feeds:
  slug=row['project'];rss=ET.Element('rss',{'version':'2.0'});ch=ET.SubElement(rss,'channel');ET.SubElement(ch,'title').text=slug+' 软件更新';i=ET.SubElement(ch,'item');ET.SubElement(i,'title').text=row['version']
  for k,v in [('version',row['build']),('shortVersionString',row['version']),('minimumSystemVersion','14.0')]:ET.SubElement(i,'{'+NS+'}'+k).text=v
  ET.SubElement(i,'description').text='工具箱统一更新与桌面显隐、防重叠；Nikki 双来源监测。保留各应用连接与外观设置。'
  ET.SubElement(i,'enclosure',{'url':f'https://github.com/SOSO-245/mac-desktop-widgets/releases/download/{a.tag}/{zpath.name}','length':str(zpath.stat().st_size),'type':'application/octet-stream','{'+NS+'}edSignature':sign(zpath,'-p')})
  f=Path(temp)/(slug+'.xml');ET.ElementTree(rss).write(f,encoding='utf-8',xml_declaration=True);sign(f);sign(f,'--verify')
 for row,_ in feeds:(ROOT/'updates'/(row['project']+'.xml')).write_bytes((Path(temp)/(row['project']+'.xml')).read_bytes())
(a.assets/'manifest.json').write_text(json.dumps(rows,indent=2)+'\n');print('Selected signed XML and ZIPs verified; publish feeds only after assets are available.')
