const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),crypto=require('crypto'),path=require('path');
const source=fs.readFileSync(path.join(__dirname,'../CodexResets.js'),'utf8');
const code=source.split('// UPDATE START')[1].split('\n').slice(1).join('\n').split('// UPDATE END')[0];
const context=vm.createContext({});vm.runInContext(code,context);let n=0;
function test(label,f){f();n++;console.log('PASS '+label)}
for(const input of ['', 'abc','中文重置⟳',source,'x'.repeat(200000)])test('SHA256 '+input.length,()=>assert.equal(context.sha256(input),crypto.createHash('sha256').update(input).digest('hex')));
test('semantic versions',()=>{assert(context.newerVersion('1.10.0','1.9.0'));assert(!context.newerVersion('1.1.0','1.1.0'));assert(!context.newerVersion('1.0.9','1.1.0'))});
const candidate='// codex-resets-scriptable\nconst SCRIPT_VERSION = "1.2.0";';
const info={product:'codex-resets-scriptable',version:'1.2.0',sha256:context.sha256(candidate),url:'https://raw.githubusercontent.com/SOSO-245/mac-desktop-widgets/v2026.10.25-r5/projects/codex-resets/scriptable/CodexResets.js'};
test('valid manifest',()=>assert(context.validateUpdate(info)));
for(const change of [{url:'http://example.com/a.js'},{url:info.url.replace('SOSO-245','attacker')},{sha256:'bad'},{product:'other'},{version:'bad'}])test('reject untrusted manifest '+JSON.stringify(change),()=>assert.throws(()=>context.validateUpdate({...info,...change})));
async function scenario({cancel=false,tamper=false,moveFailure=false}={}){
 const original='/docs/Codex重置.js',old='// codex-resets-scriptable\nconst SCRIPT_VERSION = "1.1.0";';
 const files=new Map([[original,old]]),messages=[];let calls=0;
 const fm={documentsDirectory:()=>'/docs',joinPath:(a,b)=>a+'/'+b,fileExists:p=>files.has(p),createDirectory:p=>files.set(p,''),readString:p=>files.get(p),writeString:(p,s)=>files.set(p,s),move:(a,b)=>{if(moveFailure&&a.endsWith('-new.txt'))throw Error('simulated move failure');if(files.has(b))throw Error('exists');files.set(b,files.get(a));files.delete(a)}};
 class Request{constructor(url){this.url=url;this.response={statusCode:200};calls++}async loadJSON(){return info}async loadString(){return tamper?candidate+'bad':candidate}}
 class Alert{addAction(){}addCancelAction(){}async presentAlert(){messages.push(this.title);return this.title.includes('更新到')&&cancel?-1:0}}
 const env=vm.createContext({Request,Alert,Script:{name:()=> 'Codex重置'},FileManager:{local:()=>fm,iCloud:()=>fm},SCRIPT_VERSION:'1.1.0'});vm.runInContext(code,env);await env.scriptUpdate();
 return {files,calls,messages,original,old};
}
(async()=>{
 let r=await scenario();test('confirmed update keeps backup',()=>{assert.equal(r.files.get(r.original),candidate);assert([...r.files.values()].includes(r.old))});
 r=await scenario({cancel:true});test('cancel leaves original and avoids download',()=>{assert.equal(r.files.get(r.original),r.old);assert.equal(r.calls,1)});
 r=await scenario({tamper:true});test('bad hash leaves original',()=>assert.equal(r.files.get(r.original),r.old));
 r=await scenario({moveFailure:true});test('failed replacement restores original',()=>assert.equal(r.files.get(r.original),r.old));
 console.log('PASS '+n+' script update checks');
})().catch(e=>{console.error(e);process.exitCode=1});
