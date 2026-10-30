"""CLT fallback: preserve a verified public WidgetKit payload with unchanged source."""
from pathlib import Path
import hashlib, plistlib, subprocess, sys, tempfile
root=Path(__file__).resolve().parents[1]
app, archive = map(Path,sys.argv[1:])
expected='f647430490918a6e6e8531b823b6095e4d6fe891a5e675d195c483c7e589eae7'
if hashlib.sha256(archive.read_bytes()).hexdigest()!=expected:raise ValueError('Unrecognized public widget seed')
for name,digest in {'Sources/Model.swift':'e9dec1106c671e477db0a1dc5707d6c67251237d81bf2aec83e049386e89a4c9','Sources/WidgetData.swift':'e732b38bf9857bdc0325039cdc502b4e0ff8daf471a24760faea13bb674ae3ab','Widget/Widget.swift':'dea3bf3b294efe67424ee67c6f1bd299f03ad95060f84e8f09c80ece9bf1dc17'}.items():
    if hashlib.sha256((root/name).read_bytes()).hexdigest()!=digest:raise ValueError('Widget source changed; requires Xcode: '+name)
with tempfile.TemporaryDirectory(prefix='nikki-public-widget-') as tmp:
    subprocess.run(['ditto','--norsrc','-x','-k',str(archive),tmp],check=True)
    seed=next(Path(tmp).glob('*.app'))
    subprocess.run(['codesign','--verify','--deep','--strict',str(seed)],check=True)
    info=plistlib.loads((seed/'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier']!='local.homeatlas.NikkiMonitor' or info['CFBundleShortVersionString']!='1.3.3':raise ValueError('Seed identity mismatch')
    widget=seed/'Contents/PlugIns/NikkiWidget.appex'
    dest=app/'Contents/PlugIns/NikkiWidget.appex';dest.parent.mkdir(exist_ok=True)
    subprocess.run(['ditto','--norsrc',str(widget),str(dest)],check=True)
    path=dest/'Contents/Info.plist'; wi=plistlib.loads(path.read_bytes()); host=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    for key in ['CFBundleShortVersionString','CFBundleVersion']:wi[key]=host[key]
    path.write_bytes(plistlib.dumps(wi))
    ent=Path(tmp)/'widget.entitlements'
    value=subprocess.run(['codesign','-d','--entitlements',':-',str(widget)],check=True,capture_output=True).stdout
    plistlib.loads(value);ent.write_bytes(value)
    subprocess.run(['codesign','--force','--sign','-','--entitlements',str(ent),str(dest)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(dest)],check=True)
