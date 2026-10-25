"""Real Sparkle update of throwaway apps on loopback, never a user's tool."""
from pathlib import Path
import argparse
import functools
import importlib.util
import http.server
import json
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('helper',HERE.parent/'updater_build.py')
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
SPARKLE=helper.prepare(HERE.parent)
ROOT=Path(tempfile.mkdtemp(prefix='widget-update-integration-'))
parser=argparse.ArgumentParser();parser.add_argument('--account',default='mac-desktop-widgets-integration-test');ACCOUNT=parser.parse_args().account
def run(*cmd):return subprocess.check_output([str(c) for c in cmd],stderr=subprocess.STDOUT,text=True).strip()
run(SPARKLE/'bin/generate_keys','--account',ACCOUNT)
KEY=run(SPARKLE/'bin/generate_keys','--account',ACCOUNT,'-p')
FIXTURE=ROOT/'WidgetUpdateFixture'
run('xcrun','clang','-fobjc-arc','-F',SPARKLE,'-framework','AppKit','-framework','Sparkle','-Wl,-rpath,@executable_path/../Frameworks',HERE/'UpdateFixture.m','-o',FIXTURE)
class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*args):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(QuietHandler,directory=ROOT))
threading.Thread(target=server.serve_forever,daemon=True).start()
port=server.server_address[1]
for scenario in ['valid','tampered-archive','tampered-feed']:
    folder=ROOT/scenario;folder.mkdir()
    bid='local.homeatlas.UpdaterFixture.'+uuid.uuid4().hex
    def app(version,parent):
        a=parent/'UpdateFixture.app';(a/'Contents/MacOS').mkdir(parents=True)
        shutil.copy2(FIXTURE,a/'Contents/MacOS/Fixture')
        (a/'Contents/Frameworks').mkdir();run('ditto',SPARKLE/'Sparkle.framework',a/'Contents/Frameworks/Sparkle.framework')
        info=dict(CFBundleIdentifier=bid,CFBundleName='UpdateFixture',CFBundleExecutable='Fixture',CFBundlePackageType='APPL',CFBundleVersion=str(version),CFBundleShortVersionString=str(version)+'.0',LSUIElement=True,FixtureRoot=str(folder),SUFeedURL=f'http://127.0.0.1:{port}/{scenario}/appcast.xml',SUPublicEDKey=KEY,SUEnableAutomaticChecks=False,SUAutomaticallyUpdate=False,SURequireSignedFeed=True,SUVerifyUpdateBeforeExtraction=True,NSAppTransportSecurity={'NSAllowsLocalNetworking':True})
        (a/'Contents/Info.plist').write_bytes(plistlib.dumps(info));run('codesign','--force','--sign','-',a);return a
    old=app(1,folder/'installed');new=app(2,folder/'download')
    archive=folder/'update.zip';run('ditto','-c','-k','--norsrc','--keepParent',new,archive)
    signature=run(SPARKLE/'bin/sign_update','--account',ACCOUNT,'-p',archive)
    feed=folder/'appcast.xml'
    feed.write_text(f'''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Isolated test</title><item><title>2.0</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion><enclosure url="http://127.0.0.1:{port}/{scenario}/update.zip" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature}"/></item></channel></rss>''')
    run(SPARKLE/'bin/sign_update','--account',ACCOUNT,feed)
    if scenario=='tampered-archive':
        b=bytearray(archive.read_bytes());b[len(b)//2]^=1;archive.write_bytes(b)
    if scenario=='tampered-feed':feed.write_text(feed.read_text().replace('Isolated test','Modified test'))
    marker=folder/'user-config.txt';marker.write_text('preserved')
    run('open','-n',old)
    result=folder/'result.txt';deadline=time.monotonic()+90
    while time.monotonic()<deadline:
        value=result.read_text() if result.exists() else ''
        if value.startswith(('UPDATED_2','REJECTED:','START_ERROR:','NO_UPDATE')):break
        time.sleep(0.5)
    version=plistlib.loads((old/'Contents/Info.plist').read_bytes())['CFBundleVersion']
    expected=version=='2' and value=='UPDATED_2' if scenario=='valid' else version=='1' and value.startswith('REJECTED:')
    assert expected,(scenario,version,value,str(folder))
    assert marker.read_text()=='preserved'
    print('PASS',scenario,'installed version',version,flush=True)
    run('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister','-u',old)
print('Evidence:',ROOT)
server.shutdown()
