from pathlib import Path
import subprocess, tempfile, plistlib, datetime, shutil
import updater_build
root=Path(__file__).resolve().parent
stage=Path(tempfile.mkdtemp(prefix='api-usage-build-'))
app=stage/'API用量卡片.app'; contents=app/'Contents'; binary=contents/'MacOS'; res=contents/'Resources'
binary.mkdir(parents=True); res.mkdir()
def run(*args): subprocess.run([str(a) for a in args],check=True)
run('xcrun','swiftc','-parse-as-library','-O','-target','arm64-apple-macos14.0',*sorted((root/'Sources').glob('*.swift')),'-o',binary/'APIUsageCard','-framework','AppKit','-framework','SwiftUI','-framework','Security','-framework','ServiceManagement',*updater_build.compile_flags(root))
run('xcrun','swift',root/'Assets/GenerateIcon.swift',stage/'AppIcon.iconset')
run('iconutil','-c','icns',stage/'AppIcon.iconset','-o',res/'AppIcon.icns')
info=dict(CFBundleIdentifier='local.homeatlas.APIUsage',CFBundleExecutable='APIUsageCard',CFBundleName='API用量卡片',CFBundleDisplayName='API用量卡片',CFBundlePackageType='APPL',CFBundleShortVersionString='1.2.0',CFBundleVersion=datetime.datetime.now().strftime('%Y%m%d%H%M%S'),CFBundleIconFile='AppIcon',LSMinimumSystemVersion='14.0',LSUIElement=True,NSHighResolutionCapable=True)
(contents/'Info.plist').write_bytes(plistlib.dumps(info))
updater_build.finish(root, app)
out=root/'交付'; out.mkdir(exist_ok=True)
run('ditto','-c','-k','--norsrc','--keepParent',app,out/'API用量卡片-1.2.0-macOS.zip')
import json
(out/'build-result.json').write_text(json.dumps({'app':str(app),'archive':str(out/'API用量卡片-1.2.0-macOS.zip')},ensure_ascii=False))
print(app)
