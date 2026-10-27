from pathlib import Path
import tempfile,subprocess,plistlib
root=Path(__file__).resolve().parents[1]
shared=root.parent/'开源发布/mac-desktop-widgets/shared/toolbox'
if not shared.exists():shared=root.parents[1]/'shared/toolbox'
stage=Path(tempfile.mkdtemp(prefix='toolbox-bridge-test-'));app=stage/'Harness.app';exe=app/'Contents/MacOS/Harness';exe.parent.mkdir(parents=True)
s=(shared/'ToolboxShared.swift').read_text().replace('local.homeatlas.HomeEnergy','local.homeatlas.ToolboxTest')
s=s.replace('FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HomeAtlasToolbox")','URL(fileURLWithPath:"'+str(stage/'state')+'")')
(stage/'ToolboxShared.swift').write_text(s)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.homeatlas.ToolboxTest','CFBundleExecutable':'Harness','CFBundlePackageType':'APPL','LSUIElement':True}))
subprocess.run(['xcrun','swiftc','-parse-as-library',str(stage/'ToolboxShared.swift'),str(shared/'ToolboxBridge.swift'),str(root/'Tests/BridgeHarness.swift'),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True,timeout=15)
