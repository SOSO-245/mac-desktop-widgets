// Variables used by Scriptable.
// icon-color: teal; icon-glyph: history;
// Codex 重置手机版 · Scriptable · 无需账户、密钥或电脑供数。
// codex-resets-scriptable
const SCRIPT_VERSION = "1.1.0";
// 数据：codex-resets.com 社区公告；不代表个人账户额度。
const WEBSITE = "https://codex-resets.com/zh-CN";
const API = "https://codex-resets.com/api/v1/";
const REFRESH_MS = 5 * 60 * 1000;
const HOUR = 3600000;

// MODEL START — 与离线测试共用，测试数据不进入日常显示。
function timestamp(value) {
  if (typeof value !== "string" || !/(Z|[+-]\d\d:\d\d)$/.test(value)) return null;
  const n = Date.parse(value); return Number.isFinite(n) ? n : null;
}
function validate(body, kind) {
  if (!body || body.meta?.api_version !== "v1" || timestamp(body.meta.generated_at) === null)
    throw new Error("数据版本或时间无效");
  if (kind === "history") {
    if (!Array.isArray(body.data) || body.data.some(e => !e || timestamp(e.announced_at) === null))
      throw new Error("记录格式无效");
  } else {
    const d = body.data;
    if (!d || typeof d !== "object" || !d.stats || !Number.isInteger(d.stats.total) || d.stats.total < 0)
      throw new Error("状态格式无效");
    for (const key of ["scheduled_reset", "latest_reset", "active_watch"]) {
      if (!(key in d) || (d[key] !== null && (typeof d[key] !== "object" || Array.isArray(d[key]))))
        throw new Error("状态字段缺失");
    }
    if (d.latest_reset && timestamp(d.latest_reset.announced_at) === null) throw new Error("记录日期无效");
    if (d.scheduled_reset?.scheduled_for != null && timestamp(d.scheduled_reset.scheduled_for) === null)
      throw new Error("计划日期无效");
  }
  return body;
}
function elapsed(ms) {
  const hours = Math.max(0, Math.floor(ms / HOUR));
  return `${Math.floor(hours / 24)} 天 ${hours % 24} 小时`;
}
function model(status, history, now) {
  const d = status?.body?.data;
  const records = (history?.body?.data || []).filter(e => timestamp(e.announced_at) <= now)
    .sort((a,b) => timestamp(b.announced_at) - timestamp(a.announced_at)).slice(0,3);
  const result = {phase:"unavailable", records, last:null, deadline:null, total:null, average:null,
    checkedAt:status?.checkedAt || null, stale:!d || Boolean(status.issue), watch:false};
  if (!d) return result;
  result.stale = result.stale || now - status.checkedAt > HOUR || now < status.checkedAt ||
    now - timestamp(status.body.meta.generated_at) > 6 * HOUR;
  const last = timestamp(d.latest_reset?.announced_at) ?? timestamp(d.stats.last_reset_at);
  result.last = last !== null && last <= now ? last : null;
  result.total = d.stats.total;
  result.average = typeof d.stats.avg_interval_days === "number" && Number.isFinite(d.stats.avg_interval_days)
    && d.stats.avg_interval_days > 0 ? d.stats.avg_interval_days : null;
  if (d.scheduled_reset?.status === "scheduled") {
    result.deadline = timestamp(d.scheduled_reset.scheduled_for);
    result.phase = result.deadline === null ? "undated" : result.deadline > now ? "scheduled" : "awaiting";
  } else {
    result.phase = result.last === null ? "unknown" : "elapsed";
    const expiry = timestamp(d.active_watch?.expires_at);
    result.watch = expiry !== null && expiry > now;
  }
  return result;
}
function retryTime(header, now) {
  if (!header) return now + REFRESH_MS;
  const seconds = /^\d+$/.test(String(header)) ? Number(header) : null;
  const date = seconds !== null ? now + seconds * 1000 : Date.parse(header);
  return Number.isFinite(date) ? Math.max(now + 60000, date) : now + REFRESH_MS;
}
function nextRefresh(m, now) {
  const dates = [now + REFRESH_MS];
  if (m.phase === "scheduled") dates.push(m.deadline);
  if (m.phase === "elapsed") dates.push(m.last + (Math.floor((now-m.last)/HOUR)+1)*HOUR);
  return new Date(Math.max(now + 1000, Math.min(...dates)));
}
// MODEL END

// UPDATE START — Only an explicit in-app confirmation may replace this script.
function newerVersion(a,b) {
  if(!/^\d+\.\d+\.\d+$/.test(a)||!/^\d+\.\d+\.\d+$/.test(b))return false;
  const x=a.split('.').map(Number),y=b.split('.').map(Number);
  for(let i=0;i<3;i++){if(x[i]!==y[i])return x[i]>y[i]}return false;
}
function sha256(value) {
  const str=unescape(encodeURIComponent(value)),bytes=[];
  for(let i=0;i<str.length;i++)bytes.push(str.charCodeAt(i));
  const bitLength=bytes.length*8;bytes.push(128);
  while(bytes.length%64!==56)bytes.push(0);
  for(let i=7;i>=0;i--)bytes.push(i>=4?0:(bitLength>>>(i*8))&255);
  const K=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
  const H=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
  const ro=(x,n)=>(x>>>n)|(x<<(32-n));
  for(let offset=0;offset<bytes.length;offset+=64){
    const w=new Int32Array(64);
    for(let i=0;i<16;i++)w[i]=(bytes[offset+i*4]<<24)|(bytes[offset+i*4+1]<<16)|(bytes[offset+i*4+2]<<8)|bytes[offset+i*4+3];
    for(let i=16;i<64;i++){const a=w[i-15],b=w[i-2];w[i]=(w[i-16]+(ro(a,7)^ro(a,18)^(a>>>3))+w[i-7]+(ro(b,17)^ro(b,19)^(b>>>10)))|0}
    let [a,b,c,d,e,f,g,h]=H;
    for(let i=0;i<64;i++){const one=(h+(ro(e,6)^ro(e,11)^ro(e,25))+((e&f)^(~e&g))+K[i]+w[i])|0;const two=((ro(a,2)^ro(a,13)^ro(a,22))+((a&b)^(a&c)^(b&c)))|0;h=g;g=f;f=e;e=(d+one)|0;d=c;c=b;b=a;a=(one+two)|0}
    [a,b,c,d,e,f,g,h].forEach((n,i)=>{H[i]=(H[i]+n)|0});
  }
  return H.map(n=>(n>>>0).toString(16).padStart(8,'0')).join('');
}
function validateUpdate(info) {
  if(info?.product!=="codex-resets-scriptable" || !/^\d+\.\d+\.\d+$/.test(info.version) ||
    !/^[a-f0-9]{64}$/.test(info.sha256) || !/^https:\/\/raw\.githubusercontent\.com\/SOSO-245\/mac-desktop-widgets\/(?:v[0-9][\w.-]*|[a-f0-9]{40})\/projects\/codex-resets\/scriptable\/CodexResets\.js$/.test(info.url))
    throw Error("更新信息不符合预期，原脚本保持不变。");
  return info;
}
async function scriptUpdate() {
  async function notice(title,message){const a=new Alert();a.title=title;a.message=message;a.addAction("好");await a.presentAlert()}
  try {
    const req=new Request("https://raw.githubusercontent.com/SOSO-245/mac-desktop-widgets/main/updates/codex-resets-scriptable.json");
    req.timeoutInterval=12;const info=validateUpdate(await req.loadJSON());
    if(req.response?.statusCode!==200)throw Error("暂时无法连接更新源，请稍后重试。");
    if(!newerVersion(info.version,SCRIPT_VERSION)){await notice("已是最新版本",`当前版本 ${SCRIPT_VERSION}`);return}
    const ask=new Alert();ask.title=`更新到 ${info.version}？`;ask.message=String(info.notes||"改进和修复。").slice(0,1200)+"\n\n确认后将从本项目 GitHub 下载、校验并替换当前脚本，保留旧版备份。";
    ask.addAction("更新脚本");ask.addCancelAction("暂不更新");if(await ask.presentAlert()!==0)return;
    const download=new Request(info.url);download.timeoutInterval=20;const code=await download.loadString();
    if(download.response?.statusCode!==200||code.length>200000||sha256(code)!==info.sha256||!code.includes('// codex-resets-scriptable')||!code.includes(`const SCRIPT_VERSION = "${info.version}";`))throw Error("更新文件校验失败，原脚本保持不变。");
    const name=Script.name();if(!name||/[\/\\]/.test(name))throw Error("无法定位当前脚本，请手动替换代码。");
    const candidates=[];
    for(const isCloud of [false,true]){
      try{const manager=isCloud?FileManager.iCloud():FileManager.local();const path=manager.joinPath(manager.documentsDirectory(),name+".js");if(manager.fileExists(path)&&!candidates.some(x=>x.path===path))candidates.push({manager,path,isCloud})}catch(_){}
    }
    if(candidates.length!==1)throw Error("发现多个同名脚本或无法定位。为避免覆盖错误文件，请手动替换当前脚本代码。");
    const {manager,path,isCloud}=candidates[0];if(isCloud)await manager.downloadFileFromiCloud(path);
    const old=manager.readString(path);if(!old.includes('// codex-resets-scriptable'))throw Error("当前文件不匹配，已停止替换。");
    const backupDir=manager.joinPath(manager.documentsDirectory(),"CodexResetsScriptBackups");if(!manager.fileExists(backupDir))manager.createDirectory(backupDir,true);
    const stamp=String(Date.now()),backup=manager.joinPath(backupDir,stamp+"-"+name+".txt"),pending=manager.joinPath(backupDir,stamp+"-new.txt");
    manager.writeString(pending,code);if(sha256(manager.readString(pending))!==info.sha256)throw Error("暂存文件校验失败。");
    manager.move(path,backup);
    try{manager.move(pending,path)}catch(e){if(!manager.fileExists(path))manager.move(backup,path);throw e}
    await notice("脚本已更新","请退出当前预览后重新运行。原脚本保留在 CodexResetsScriptBackups 文件夹，组件无需重新添加。");
  }catch(e){await notice("暂未完成更新",String(e.message||e))}
}
// UPDATE END

const fm = FileManager.local();
const cacheDir = fm.joinPath(fm.documentsDirectory(), "CodexResetsMobile-v1");
try { if (!fm.fileExists(cacheDir)) fm.createDirectory(cacheDir, true); } catch (_) {}
function readCache(kind) {
  try {
    const raw = fm.readString(fm.joinPath(cacheDir, kind + ".json"));
    if (raw.length > 256000) return null;
    const c = JSON.parse(raw);
    if (c.body) validate(c.body, kind);
    if (c.body && !Number.isFinite(c.checkedAt)) return null;
    return c;
  } catch (_) { return null; }
}
function saveCache(kind, value) {
  try { fm.writeString(fm.joinPath(cacheDir, kind + ".json"), JSON.stringify(value)); } catch (_) {}
}
function header(response, name) {
  const entries = response?.headers || {};
  const key = Object.keys(entries).find(k => k.toLowerCase() === name.toLowerCase());
  return key ? entries[key] : null;
}
async function fetchData(kind, force) {
  const old = readCache(kind), now = Date.now();
  if (old?.retryAt > now) return {...old, issue:true};
  if (!force && old?.body && now >= old.checkedAt && now-old.checkedAt < REFRESH_MS) return old;
  try {
    const req = new Request(API + (kind === "status" ? "status" : "resets?limit=3&order=desc"));
    req.timeoutInterval = 8;
    req.headers = {Accept:"application/json", "Cache-Control":"no-cache"};
    if (old?.etag && old.body) req.headers["If-None-Match"] = old.etag;
    const raw = await req.loadString(), code = req.response?.statusCode;
    if (code === 429) {
      const cached = {...(old || {}), retryAt:retryTime(header(req.response,"retry-after"),now), issue:true};
      saveCache(kind,cached); return cached;
    }
    if (code === 304 && old?.body) {
      const cached = {...old,checkedAt:now,issue:false,retryAt:0};saveCache(kind,cached);return cached;
    }
    if (code !== 200 || raw.length > 256000) throw new Error("请求失败");
    const body = validate(JSON.parse(raw),kind);
    const cached = {body,checkedAt:now,etag:header(req.response,"etag"),issue:false,retryAt:0};
    saveCache(kind,cached);return cached;
  } catch (_) { return {...(old || {}),issue:true}; }
}

const results = await Promise.all([fetchData("status",!config.runsInWidget),fetchData("history",!config.runsInWidget)]);
const now = Date.now(), m = model(results[0],results[1],now);
const C = {white:new Color("F5F7FF"),dim:new Color("ACBED5"),muted:new Color("7F96B1"),
  green:new Color("60FFBC"),pink:new Color("FF79B8"),purple:new Color("B59AFF")};
const font = (n,bold=false) => bold ? Font.boldSystemFont(n) : Font.mediumSystemFont(n);
function text(parent,value,size=12,color=C.white,bold=false) {
  const t=parent.addText(String(value));t.font=font(size,bold);t.textColor=color;
  t.lineLimit=1;t.minimumScaleFactor=0.65;return t;
}
function row(parent) { const s=parent.addStack();s.layoutHorizontally();s.centerAlignContent();return s; }
function column(parent) { const s=parent.addStack();s.layoutVertically();s.spacing=3;return s; }
function formatDate(time) {
  if(time === null) return "—";
  const d=new Date(time),p=n=>String(n).padStart(2,"0");
  return `${p(d.getMonth()+1)}/${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}
function timeLabel(time) { return time ? formatDate(time).split(" ")[1] : "待更新"; }
function rule(parent) {
  const s=parent.addStack();s.size=new Size(0,1);s.backgroundColor=new Color("FFFFFF",0.13);
}
function stat(parent,title,value,color=C.white) {
  const s=column(parent);text(s,title,10,C.dim);text(s,value,16,color,true);return s;
}
const w=new ListWidget(),bg=new LinearGradient();
bg.colors=[new Color("143D45"),new Color("0B1428"),new Color("292344")];
bg.locations=[0,0.5,1];bg.startPoint=new Point(0,0);bg.endPoint=new Point(1,1);
w.backgroundGradient=bg;w.url=WEBSITE;w.refreshAfterDate=nextRefresh(m,now);
w.setPadding(12,16,12,16);w.spacing=0;
let family=config.widgetFamily;
if(!config.runsInWidget) {
  const a=new Alert();a.title="Codex 重置";a.message="选择预览尺寸。桌面会自动使用所添加的尺寸。";
  ["小号","中号","大号",`检查脚本更新 · ${SCRIPT_VERSION}`].forEach(s=>a.addAction(s));a.addCancelAction("取消");
  const choice=await a.presentSheet();if(choice===3)await scriptUpdate();family=["small","medium","large"][choice] || "medium";
}
family=["small","medium","large","extraLarge"].includes(family)?family:"small";
const small=family === "small",large=family === "large" || family === "extraLarge";
const head=row(w);text(head,"⟳",small?18:20,C.green,true);head.addSpacer(6);
text(head,"Codex 重置",small?12:16,C.white,true);head.addSpacer();
if(!small) text(head,(m.stale?"缓存 · ":"")+timeLabel(m.checkedAt),10,C.dim);
w.addSpacer(large?12:7);
const main=large || small ? w : row(w);
const primary=large || small ? main : column(main);
const heading={scheduled:"计划重置倒计时",awaiting:"已到计划时间",undated:"已有重置计划",elapsed:"已重置",unknown:"暂无重置记录",unavailable:"暂时无法更新"}[m.phase];
text(primary,heading,small?10:11,C.dim);
primary.addSpacer(4);
const tint=m.stale?C.dim:m.phase === "scheduled"?C.pink:C.green;
if(m.phase === "scheduled") {
  const t=primary.addDate(new Date(m.deadline));t.applyTimerStyle();
  t.font=font(small?28:large?34:28,true);t.textColor=tint;t.lineLimit=1;t.minimumScaleFactor=0.5;
} else {
  const value=m.phase === "elapsed"?elapsed(now-m.last):
    m.phase === "awaiting"?"等待确认":m.phase === "undated"?"时间待定":"—";
  text(primary,value,small?22:large?32:26,tint,true);
}
primary.addSpacer(5);
text(primary,m.deadline!==null?"计划 "+formatDate(m.deadline):m.watch?"观察中 · 尚无明确计划":
  m.phase === "unavailable"?"打开脚本重试":m.phase === "undated"?"等待公布具体时间":"暂无重置计划",small?9:10,C.dim);
if(!small && !large) {
  main.addSpacer(12);const side=column(main);
  stat(side,"累计重置",m.total===null?"—":`${m.total} 次`);side.addSpacer(5);
  stat(side,"平均间隔",m.average===null?"—":`${m.average.toFixed(1)} 天`);
}
if(large) {
  w.addSpacer(12);const stats=row(w);
  stat(stats,"最近一次",formatDate(m.last));stats.addSpacer();
  stat(stats,"累计重置",m.total===null?"—":`${m.total} 次`);stats.addSpacer();
  stat(stats,"平均间隔",m.average===null?"—":`${m.average.toFixed(1)} 天`);
  w.addSpacer(10);rule(w);w.addSpacer(10);
  const rh=row(w);text(rh,"最近记录",11,C.dim);rh.addSpacer();
  text(rh,results[1].issue?"缓存记录":"本地时间",10,C.muted);w.addSpacer(8);
  if(!m.records.length) text(w,results[1].body?"暂无记录":"记录暂不可用",12,C.dim);
  m.records.forEach((e,i)=>{
    const r=row(w);text(r,"•",14,C.green);r.addSpacer(6);
    text(r,formatDate(timestamp(e.announced_at)),14,C.white,true);r.addSpacer();
    text(r,e.reset_type==="regular"?"常规额度":e.reset_type==="banked"?"储备额度":"额度重置",11,C.dim);
    if(i<m.records.length-1)w.addSpacer(8);
  });
}
w.addSpacer();
if(small) {
  text(w,m.last!==null?"上次 "+formatDate(m.last):timeLabel(m.checkedAt),9,C.dim);w.addSpacer(4);
  text(w,m.stale?"缓存 · 点击查看来源":"数据：Codex Resets ↗",8,C.muted);
} else {
  const foot=row(w);text(foot,"数据：Codex Resets ↗",9,C.muted);foot.addSpacer();
  text(foot,m.stale?"缓存 · 非个人额度":"公告追踪 · 非个人额度",9,C.muted);
}
Script.setWidget(w);
if(!config.runsInWidget) {
  if(small) await w.presentSmall();else if(large) await w.presentLarge();else await w.presentMedium();
}
Script.complete();
