#!/usr/bin/env python3
from pathlib import Path
import updater_build
import subprocess,plistlib,datetime,shutil,tempfile,json
root=Path(__file__).resolve().parent
out=root/'交付';out.mkdir(exist_ok=True)
stage=Path(tempfile.mkdtemp(prefix='homeatlas-toolbox-build-'));app=stage/'桌面工具箱.app';contents=app/'Contents';binary=contents/'MacOS';resources=contents/'Resources'
binary.mkdir(parents=True,exist_ok=True);resources.mkdir(exist_ok=True)
def run(*args):subprocess.run(list(map(str,args)),check=True)
run('xcrun','swiftc','-parse-as-library','-O','-target','arm64-apple-macos14.0',*sorted((root/'Sources').glob('*.swift')),'-o',binary/'HomeAtlasToolbox','-framework','AppKit','-framework','SwiftUI',*updater_build.compile_flags(root))
iconset=stage/'AppIcon.iconset'
run('xcrun','swift',root/'Assets/GenerateIcon.swift',iconset)
run('iconutil','-c','icns',iconset,'-o',resources/'AppIcon.icns')
info=dict(CFBundleIdentifier='local.homeatlas.Toolbox',CFBundleExecutable='HomeAtlasToolbox',CFBundleName='桌面工具箱',CFBundleDisplayName='桌面工具箱',CFBundlePackageType='APPL',CFBundleShortVersionString='1.1.0',CFBundleVersion=datetime.datetime.now().strftime('%Y%m%d%H%M%S'),CFBundleIconFile='AppIcon',LSMinimumSystemVersion='14.0',LSUIElement=True,NSHighResolutionCapable=True)
(contents/'Info.plist').write_bytes(plistlib.dumps(info))
run('xattr','-cr',app)
run('codesign','--force','--sign','-',app)
updater_build.finish(root,app)
run('ditto','-c','-k','--norsrc','--keepParent',app,out/'HomeAtlasToolbox-1.1.0-macOS.zip')
(out/'build-result.json').write_text(json.dumps({'app':str(app),'archive':str(out/'HomeAtlasToolbox-1.1.0-macOS.zip')},ensure_ascii=False))
print(app)
