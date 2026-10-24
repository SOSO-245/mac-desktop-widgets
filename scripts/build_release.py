#!/usr/bin/env python3
"""Build public apps in a clean temporary tree; never install or launch them."""
import argparse,concurrent.futures,hashlib,json,shutil,subprocess,tempfile,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ARCHIVES={'home-overview':'家庭概览-Mac.zip','lunar-calendar':'万年历-Mac.zip','codex-resets':'Codex重置-Mac.zip','vpn-card':'FlClash实时卡片-Mac.zip','nikki-card':'Nikki实时卡片-Mac.zip','mac-vitals':'Mac实时监测-Mac.zip'}
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--projects',nargs='*',choices=list(ARCHIVES));args=parser.parse_args()
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    stage=Path(tempfile.mkdtemp(prefix='mac-desktop-kit-public-'))
    shutil.copytree(ROOT/'projects',stage/'projects',ignore=shutil.ignore_patterns('交付','__pycache__','*.xcodeproj','build-products.json','build-result.json'))
    def build(slug):
        project=stage/'projects'/slug
        r=subprocess.run(['python3','build.py'],cwd=project,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        (output/(slug+'.build.log')).write_text(r.stdout)
        if r.returncode:raise RuntimeError('Build failed: '+slug)
        record_path=project/('build-products.json' if slug=='home-overview' else '交付/build-result.json')
        record=json.loads(record_path.read_text());app=Path(record['app'])
        subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
        # Temporary Xcode build products must not replace installed widget registrations.
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister','-u',str(app)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        plugins=app/'Contents/PlugIns'
        if plugins.exists():
            for widget in plugins.glob('*.appex'):subprocess.run(['pluginkit','-r',str(widget)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        archive=project/'交付'/ARCHIVES[slug]
        with zipfile.ZipFile(archive,'a',zipfile.ZIP_DEFLATED) as z:
            z.write(ROOT/'LICENSE','LICENSE.txt')
            z.write(ROOT/'THIRD-PARTY-NOTICES.md','THIRD-PARTY-NOTICES.md')
        with zipfile.ZipFile(archive) as z:
            assert z.testzip() is None
            for name in z.namelist():
                data=z.read(name)
                # No developer home paths, device IDs, actual household network or known private alias.
                for marker in [b'/Users/',b'iot_cn_',b'miaomiaoc_cn_',b'zhimi_cn_',b'192.168.50.',b'big_max_']:
                    if slug=='mac-vitals' and name.endswith('/Resources/macmon') and marker==b'/Users/':
                        assert ('/Users/'+Path.home().name+'/').encode() not in data, 'local path in collector'
                        continue # pinned upstream binary embeds upstream build paths
                    assert marker not in data, 'private marker in '+slug+':'+name
        shutil.copy2(archive,output/(slug+'-macos.zip'))
        return {'project':slug,'archive':slug+'-macos.zip','sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
    rows=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for row in pool.map(build,args.projects or ARCHIVES):rows.append(row);print('BUILT',row['project'],flush=True)
    if args.projects and (output/'manifest.json').exists():
        old=json.loads((output/'manifest.json').read_text());rows=[r for r in old if r['project'] not in args.projects]+rows
    (output/'manifest.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
    (output/'SHA256SUMS').write_text(''.join(row['sha256']+'  '+row['archive']+'\n' for row in rows))
    print('Release app archives verified. Logs are local-only, not release assets.')
if __name__=='__main__':main()
