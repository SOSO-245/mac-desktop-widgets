#!/usr/bin/env python3
import http.server,threading,json,urllib.parse,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
class Mock(http.server.BaseHTTPRequestHandler):
    node='初始';writes=0;redirected=0
    def log_message(self,*a): pass
    def reply(self,code,obj=None):
        self.send_response(code);self.end_headers()
        if obj is not None:self.wfile.write(json.dumps(obj).encode())
    def do_GET(self):
        if self.headers.get('Authorization')!='Bearer mock-only':return self.reply(401)
        url=urllib.parse.urlsplit(self.path)
        p=urllib.parse.unquote(url.path)
        if p=='/proxies':
            return self.reply(200,{'proxies':{'组 / # ?':{'type':'Selector','now':Mock.node,'all':['初始','目标 🇯🇵 / #']},'初始':{'type':'Vless'}}})
        if p=='/providers/proxies':
            return self.reply(200,{'providers':{'套餐 / #':{'proxies':[{'type':'Vless','name':'目标 🇯🇵 / #'}]}}})
        if p in ['/proxies/初始/delay','/providers/proxies/套餐 / #/目标 🇯🇵 / #/healthcheck']:
            assert urllib.parse.parse_qs(url.query)=={'url':['https://www.gstatic.com/generate_204'],'timeout':['8000']}
            return self.reply(200,{'delay':111 if p.startswith('/proxies/') else (224 if Mock.writes else 223)})
        if p=='/connections' and not url.query: return self.reply(200,{'connections':[]})
        if p=='/redirect':
            self.send_response(302);self.send_header('Location','/leak');self.end_headers();return
        if p=='/leak':Mock.redirected+=1;return self.reply(200,{})
        if p=='/stats':return self.reply(200,dict(writes=Mock.writes,redirected=Mock.redirected))
        if p=='/proxies/组 / # ?':return self.reply(200,dict(type='Selector',now=Mock.node,all=['初始','目标 🇯🇵 / #']))
        self.reply(404)
    def do_PUT(self):
        assert self.headers.get('Authorization')=='Bearer mock-only'
        assert urllib.parse.unquote(self.path)=='/proxies/组 / # ?'
        body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert body=={'name':'目标 🇯🇵 / #'}
        Mock.node=body['name'];Mock.writes+=1;self.reply(204)
with tempfile.TemporaryDirectory(prefix='nikki-tests-') as tmp:
    binary=Path(tmp)/'tests'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',str(root/'Sources/Model.swift'),str(root/'Sources/Controller.swift'),str(root/'Sources/MenuBarDisplay.swift'),*[str(root/'Sources'/name) for name in ('MonitorCoordinator.swift','TrafficScope.swift','SubscriptionRefresh.swift')],str(root/'Tests/CoreTests.swift'),'-o',str(binary)],check=True)
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Mock)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    try:subprocess.run([str(binary),str(server.server_port)],check=True)
    finally:server.shutdown()
