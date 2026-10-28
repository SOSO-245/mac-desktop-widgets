#!/usr/bin/env python3
import http.server, json, pathlib, subprocess, tempfile, threading
ROOT=pathlib.Path(__file__).resolve().parent.parent
requests=[]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        requests.append(self.path)
        assert self.headers['Authorization']=='Bearer local-test-only'
        entity=self.path.rsplit('/',1)[-1]
        code={'sensor.unauthorized':401,'sensor.missing':404,'sensor.redirect':302}.get(entity,200)
        self.send_response(code)
        if code==302:self.send_header('Location','http://127.0.0.1:1/should-not-follow')
        self.end_headers()
        obj={'state':'1234','attributes':{'unit_of_measurement':'W'}}
        if entity=='sensor.cpu':obj={'state':'12.5','attributes':{'unit_of_measurement':'%'}}
        if entity=='sensor.pm':obj={'state':'4','attributes':{'unit_of_measurement':'μg/m³','device_class':'pm25'}}
        self.wfile.write(json.dumps(obj).encode())
    def log_message(self,*args):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
with tempfile.TemporaryDirectory(prefix='home-energy-tests-') as tmp:
    binary=pathlib.Path(tmp)/'tests'
    subprocess.run(['xcrun','swiftc','-D','HOME_ENERGY_TESTING','-parse-as-library',str(ROOT/'Sources/Model.swift'),str(ROOT/'Sources/Garage.swift'),str(ROOT/'Tests/ModelTests.swift'),'-o',str(binary)],check=True)
    subprocess.run([str(binary),f'http://127.0.0.1:{server.server_port}',str(ROOT/'Resources/charging-model.js')],check=True)
    assert len(requests)==6,requests
    assert all(p.startswith('/api/states/sensor.') for p in requests)
server.shutdown()
print('PASS: exactly six state GETs, no redirects followed; no real HA account used')
