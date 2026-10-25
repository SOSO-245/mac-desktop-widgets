const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const root=path.resolve(__dirname,'..'),source=fs.readFileSync(path.join(root,'CodexResets.js'),'utf8');
const fixtures={status:JSON.parse(fs.readFileSync(path.join(__dirname,'Fixtures/status.json'))),history:JSON.parse(fs.readFileSync(path.join(__dirname,'Fixtures/history.json')))};
let count=0;
const check=(name,fn)=>{fn();count++;console.log('PASS '+name)};
const pure=source.split('// MODEL START')[1].split('\n').slice(1).join('\n').split('// MODEL END')[0];
const ctx=vm.createContext({Date,Number,Error,Math,REFRESH_MS:300000,HOUR:3600000});vm.runInContext(pure,ctx);
const t=Date.parse('2026-10-25T10:00:00Z');
const base=()=>({body:structuredClone(fixtures.status),checkedAt:t});
const current=()=>{const s=base();s.body.meta.generated_at=new Date(t).toISOString();s.body.data.scheduled_reset=null;s.body.data.latest_reset.announced_at=new Date(t-50*3600000).toISOString();return s};
check('v1 live envelope accepted',()=>assert.equal(ctx.validate(fixtures.status,'status'),fixtures.status));
check('legacy shape rejected',()=>assert.throws(()=>ctx.validate({events:[]},'status')));
check('missing status rejected',()=>assert.throws(()=>ctx.validate({data:{stats:{total:2}},meta:fixtures.status.meta},'status')));
check('bad date rejected',()=>{const s=current();s.body.data.latest_reset.announced_at='bad';assert.throws(()=>ctx.validate(s.body,'status'))});
check('no plan elapsed days and hours',()=>{const m=ctx.model(current(),null,t);assert.equal(m.phase,'elapsed');assert.equal(ctx.elapsed(t-m.last),'2 天 2 小时')});
check('future plan uses absolute date',()=>{const s=current();s.body.data.scheduled_reset={status:'scheduled',scheduled_for:new Date(t+60000).toISOString()};assert.equal(ctx.model(s,null,t).phase,'scheduled')});
check('deadline waits for confirmation',()=>{const s=current();s.body.data.scheduled_reset={status:'scheduled',scheduled_for:new Date(t).toISOString()};assert.equal(ctx.model(s,null,t).phase,'awaiting')});
check('undated plan not invented',()=>{const s=current();s.body.data.scheduled_reset={status:'scheduled',scheduled_for:null};assert.equal(ctx.model(s,null,t).phase,'undated')});
check('watch is not a scheduled reset',()=>{const s=current();s.body.data.active_watch={expires_at:new Date(t+60000).toISOString()};const m=ctx.model(s,null,t);assert.equal(m.phase,'elapsed');assert.equal(m.watch,true)});
check('expired watch hidden',()=>{const s=current();s.body.data.active_watch={expires_at:new Date(t-1).toISOString()};assert.equal(ctx.model(s,null,t).watch,false)});
check('no cache no false zero',()=>{const m=ctx.model(null,null,t);assert.equal(m.phase,'unavailable');assert.equal(m.total,null)});
check('failed refresh marks cache',()=>{const s=current();s.issue=true;assert.equal(ctx.model(s,null,t).stale,true)});
check('old generated data marked cache',()=>{const s=current();s.body.meta.generated_at=new Date(t-7*3600000).toISOString();assert.equal(ctx.model(s,null,t).stale,true)});
check('count uses server total not history length',()=>{const s=current();s.body.data.stats.total=67;assert.equal(ctx.model(s,{body:fixtures.history},t).total,67)});
check('future last reset not elapsed',()=>{const s=current();s.body.data.latest_reset.announced_at=new Date(t+60000).toISOString();assert.equal(ctx.model(s,null,t).last,null)});
check('429 seconds and HTTP date',()=>{assert.equal(ctx.retryTime('120',t),t+120000);assert.equal(ctx.retryTime(new Date(t+3600000).toUTCString(),t),t+3600000)});
check('refresh requested at imminent deadline',()=>assert.equal(ctx.nextRefresh({phase:'scheduled',deadline:t+45000},t).getTime(),t+45000));
check('invalid history rejected',()=>assert.throws(()=>ctx.validate({data:[{announced_at:'bad'}],meta:fixtures.status.meta},'history')));

// Scriptable adapter: catches unsupported API use; this is not an iPhone renderer.
class Node {
 constructor(kind='column',value=null){this.kind=kind;this.value=value;this.children=[];this.spacing=0}
 addStack(){const n=new Node();this.children.push(n);return n}
 addText(s){assert.equal(typeof s,'string');const n=new Node('text',s);this.children.push(n);return n}
 addDate(d){assert(Number.isFinite(d.getTime()));const n=new Node('date',d);this.children.push(n);return n}
 addSpacer(size=0){this.children.push({kind:'spacer',size})}
 layoutHorizontally(){this.kind='row'} layoutVertically(){this.kind='column'} centerAlignContent(){}
 setPadding(...values){this.padding=values} applyTimerStyle(){this.timer=true}
 async presentSmall(){} async presentMedium(){} async presentLarge(){}
}
function height(n){
 if(n.kind==='text'||n.kind==='date')return n.font.n*1.25;
 if(n.kind==='spacer')return n.size;
 if(n.size?.height)return n.size.height;
 const h=n.children.map(height),gap=n.spacing*Math.max(0,h.length-1);
 return (n.kind==='row'?Math.max(0,...h):h.reduce((a,b)=>a+b,0)+gap)+(n.padding?n.padding[0]+n.padding[2]:0);
}
async function run(family,scenario,store=new Map()){
 const requests=[],widgets=[];let finished=false;
 const fm={documentsDirectory:()=>'/doc',joinPath:(a,b)=>a+'/'+b,fileExists:k=>store.has(k),createDirectory:()=>{},readString:k=>{if(!store.has(k))throw Error();return store.get(k)},writeString:(k,v)=>store.set(k,v)};
 class Request {
  constructor(url){this.url=url;requests.push(url)}
  async loadString(){const kind=this.url.endsWith('status')?'status':'history';const result=scenario(kind,this);
   if(result instanceof Error)throw result;this.response={statusCode:result.code||200,headers:result.headers||{}};return typeof result.body==='string'?result.body:JSON.stringify(result.body)}
 }
 const environment={console,Date,Number,Math,JSON,Error,Promise,FileManager:{local:()=>fm},Request,config:{runsInWidget:true,widgetFamily:family},
 Color:class{constructor(hex,alpha){this.hex=hex;this.alpha=alpha}},LinearGradient:class{},Point:class{},Size:class{constructor(w,h){this.width=w;this.height=h}},
 Font:{boldSystemFont:n=>({n}),mediumSystemFont:n=>({n})},ListWidget:Node,
 Script:{setWidget:w=>widgets.push(w),complete:()=>{finished=true}}};
 await vm.runInNewContext('(async()=>{'+source+'})()',environment);
 assert(finished);assert.equal(widgets.length,1);assert.equal(widgets[0].url,'https://codex-resets.com/zh-CN');
 return {requests,widget:widgets[0],store};
}
(async()=>{
 const fresh=(kind)=>{const b=structuredClone(fixtures[kind]);b.meta.generated_at=new Date().toISOString();return {body:b}};
 for(const family of ['small','medium','large']){
  for(const phase of ['elapsed','scheduled','awaiting','undated','offline']){
   const r=await run(family,(kind)=>{
    if(phase==='offline')return Error('offline');const r=fresh(kind);
    if(kind==='status')r.body.data.scheduled_reset=phase==='elapsed'?null:{status:'scheduled',scheduled_for:phase==='undated'?null:new Date(Date.now()+(phase==='awaiting'?-60000:60000)).toISOString()};return r;
   });
   check(family+' '+phase+' layout budget',()=>assert(height(r.widget)<(family==='large'?329:155),height(r.widget)));
  }
 }
 const first=await run('large',fresh);assert.equal(first.requests.length,2);
 const cached=await run('large',()=>{throw Error('cache should prevent request')},first.store);
 check('fresh cache avoids repeat network',()=>assert.equal(cached.requests.length,0));
 for(const [key,value] of first.store){const d=JSON.parse(value);d.checkedAt=Date.now()-400000;first.store.set(key,JSON.stringify(d))}
 const preserved=await run('large',()=>({body:'<html>bad</html>'}),first.store);
 check('bad response preserves valid cache',()=>{const c=JSON.parse(preserved.store.get('/doc/CodexResetsMobile-v1/status.json'));assert.equal(c.body.data.stats.total,fixtures.status.data.stats.total)});
 const rate=await run('large',()=>({code:429,headers:{'Retry-After':'120'},body:'{}'}));
 const again=await run('large',()=>{throw Error('backoff should prevent request')},rate.store);
 check('429 backoff without old cache',()=>assert.equal(again.requests.length,0));
 const notModified=await run('large',()=>({code:304,body:''}),first.store);
 check('304 reuses validated body',()=>{const c=JSON.parse(notModified.store.get('/doc/CodexResetsMobile-v1/status.json'));assert(c.checkedAt>Date.now()-10000);assert.equal(c.issue,false)});
 console.log(`PASS ${count} checks. Layout budget uses approximate metrics; iPhone visual acceptance pending.`);
})().catch(e=>{console.error(e);process.exitCode=1});
