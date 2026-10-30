from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix='api-card-tests-') as d:
    exe=Path(d)/'tests'
    subprocess.run(['xcrun','swiftc','-parse-as-library',str(r/'Sources/Core.swift'),str(r/'Tests/CoreTests.swift'),'-o',str(exe)],check=True)
    subprocess.run([str(exe)],check=True)
with tempfile.TemporaryDirectory(prefix='api-toolbox-tests-') as d:
    stage=Path(d)
    shared=(r/'Sources/ToolboxShared.swift').read_text().replace('FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HomeAtlasToolbox")','URL(fileURLWithPath:"'+str(stage/'state')+'")')
    bridge=(r/'Sources/ToolboxBridge.swift').read_text().replace('let d = UserDefaults.standard','let d = UserDefaults(suiteName: "APIUsageIsolatedTests")!')
    tests=(r/'Tests/BridgeTests.swift').read_text().replace('let d = UserDefaults.standard','let d = UserDefaults(suiteName: "APIUsageIsolatedTests")!')
    for name,content in [('Shared.swift',shared),('Bridge.swift',bridge),('Tests.swift',tests)]: (stage/name).write_text(content)
    subprocess.run(['xcrun','swiftc','-parse-as-library',str(stage/'Shared.swift'),str(stage/'Bridge.swift'),str(stage/'Tests.swift'),'-o',str(stage/'test')],check=True)
    subprocess.run([str(stage/'test')],check=True,timeout=20)
