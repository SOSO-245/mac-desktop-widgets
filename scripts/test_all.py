#!/usr/bin/env python3
"""Run source tests only. No installation or production server writes."""
from pathlib import Path
import subprocess,tempfile,concurrent.futures
ROOT=Path(__file__).resolve().parents[1]
def run(slug):
    p=ROOT/'projects'/slug
    with tempfile.TemporaryDirectory(prefix='desktop-kit-test-') as tmp:
        commands={
            'mac-vitals':[['xcrun','swiftc','-parse-as-library','Sources/Metrics.swift','Tests/CoreTests.swift','-o',str(Path(tmp)/'core')],[str(Path(tmp)/'core')]],
            'home-overview':[['python3','Tests/run.py'],['zsh','Tests/run-overview-tests.sh'],['python3','-m','unittest','discover','-s','Tests','-p','test_install.py']],
            'codex-resets':[['bash','Tests/run-tests.sh']],
            'vpn-card':[['bash','Tests/run-tests.sh'],['bash','Tests/run-shadowrocket-tests.sh'],['bash','Tests/run-site-tests.sh'],['bash','Tests/run-traffic-tests.sh']],
            'nikki-card':[['python3','Tests/run.py'],['bash','Tests/run-traffic-tests.sh'],['bash','Tests/run-preview-tests.sh']],
            'lunar-calendar':[['xcrun','swiftc','-parse-as-library','Sources/Model.swift','Sources/SolarTerms.swift','Sources/SharedState.swift','Tests/ModelTests.swift','-o',str(Path(tmp)/'tests')],[str(Path(tmp)/'tests')]],
        }[slug]
        if slug in ['nikki-card','vpn-card']:
            commands += [['xcrun','swiftc','-parse-as-library','Sources/MenuBarDisplay.swift','Tests/MenuBarTests.swift','-o',str(Path(tmp)/'menu-tests')],[str(Path(tmp)/'menu-tests')]]
        commands += [['xcrun','swiftc','-swift-version','5','-parse-as-library','Sources/MenuCustomization.swift','Tests/MenuCustomizationTests.swift','-o',str(Path(tmp)/'custom-menu-tests')],[str(Path(tmp)/'custom-menu-tests')]]
        if slug=='nikki-card':
            commands += [['xcrun','swiftc','-parse-as-library','Sources/Model.swift','Sources/WidgetData.swift','Tests/WidgetTests.swift','-o',str(Path(tmp)/'widget-tests')],[str(Path(tmp)/'widget-tests')]]
        if (p/'Sources/WidgetSelfRepair.swift').exists():
            commands += [['xcrun','swiftc','-swift-version','5','-parse-as-library','Sources/WidgetSelfRepair.swift','Tests/RepairTests.swift','-o',str(Path(tmp)/'repair')],[str(Path(tmp)/'repair')]]
        logs=[]
        for command in commands:
            r=subprocess.run(command,cwd=p,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            logs.append(r.stdout)
            if r.returncode:return slug,False,'\n'.join(logs)
        return slug,True,'\n'.join(logs)
def main():
    failed=False
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for slug,ok,log in pool.map(run,['home-overview','codex-resets','vpn-card','lunar-calendar','nikki-card','mac-vitals']):
            print(('PASS ' if ok else 'FAIL ')+slug,flush=True);print(log,flush=True);failed |= not ok
    raise SystemExit(1 if failed else 0)
if __name__=='__main__':main()
