export const cloudEntity = 'sensor.atlas_wall_connector_cloud';
export const ebikePowerEntity = 'sensor.ebike_power';
export const evRates = {flat: .555, peak: .585, critical: .888, valley: .385, deep: .222};
const numeric = value => value != null && value !== '' && Number.isFinite(Number(value)) ? Number(value) : null;
let observed = [], observedAt = 0, observedPending;
export function observedVersion() { return observedAt; }
export function sessionsFromPowerHistory(rows) {
  const sessions=[];
  let active=null, previous=null;
  const finish=()=>{
    if(active && active.kwh>=0.1 && active.end>active.start)
      sessions.push({start:Math.round(active.start/1000),seconds:Math.round((active.end-active.start)/1000),kwh:active.kwh,source:'observed'});
    active=null;
  };
  for(const row of rows || []) {
    const at=Date.parse(row.last_updated || row.last_changed), watts=numeric(row.state);
    if(!Number.isFinite(at))continue;
    if(previous && active) {
      const gap=at-previous.at;
      if(gap>0 && gap<=10*60000 && previous.watts>50) {
        active.kwh+=previous.watts*gap/3600000000;
        active.end=at;
      } else if(gap>10*60000)finish();
    }
    if(watts!==null && watts>50 && !active)active={start:at,end:at,kwh:0};
    if((watts===null || watts<=50) && active)finish();
    previous={at,watts};
  }
  return sessions;
}
export async function refreshObservedSessions(hass,now=Date.now()) {
  if(!hass?.callApi || observedPending || now-observedAt<5*60000)return observedPending;
  observedPending=(async()=>{
    const start=new Date(now-14*86400000).toISOString();
    const query=new URLSearchParams({filter_entity_id:cloudEntity,end_time:new Date(now).toISOString(),no_attributes:'1'});
    const groups=await hass.callApi('GET',`history/period/${start}?${query}`);
    observed=sessionsFromPowerHistory(groups?.[0]);
    observedAt=Date.now();
    if(typeof window!=='undefined')window.dispatchEvent(new Event('atlas-observed-charging'));
  })().catch(()=>{}).finally(()=>{observedPending=null;});
  return observedPending;
}
export function evPeriod(month, hour, year=2026) {
  if (hour >= 23 || hour < 7) return 'valley';
  if(year>2026 || (year===2026&&month>=10)) {
    if([1,2,12].includes(month)) {
      if(hour>=11&&hour<14)return 'deep';
      if(hour>=10&&hour<15)return 'valley';
      if(hour>=16&&hour<19)return 'critical';
      if((hour>=7&&hour<9)||(hour>=19&&hour<21))return 'peak';
    } else if(month>=3&&month<=6) {
      if(hour>=10&&hour<14)return 'deep';
      if(hour>=8&&hour<15)return 'valley';
      if(hour>=17&&hour<22)return 'critical';
      if(hour>=17&&hour<23)return 'peak';
    } else if([7,8].includes(month)) {
      if(hour>=17&&hour<22)return 'critical';
      if(hour>=16&&hour<23)return 'peak';
    } else {
      if(hour>=11&&hour<14)return 'deep';
      if(hour>=9&&hour<15)return 'valley';
      if(hour>=17&&hour<20)return 'critical';
      if(hour>=16&&hour<22)return 'peak';
    }
    return 'flat';
  }
  if ([1,2,12].includes(month)) {
    if (hour >= 11 && hour < 14) return 'deep';
    if (hour >= 10 && hour < 15) return 'valley';
    if (hour >= 16 && hour < 19) return 'critical';
    if ((hour >= 7 && hour < 9) || (hour >= 19 && hour < 21)) return 'peak';
  } else if ([3,4,5].includes(month)) {
    if (hour >= 11 && hour < 14) return 'deep';
    if (hour >= 10 && hour < 15) return 'valley';
    if (hour >= 17 && hour < 20) return 'critical';
    if (hour >= 20 && hour < 22) return 'peak';
  } else if (month === 6) {
    if (hour >= 7 && hour < 12) return 'valley';
    if (hour >= 17 && hour < 22) return 'critical';
    if (hour >= 16 && hour < 23) return 'peak';
  } else if ([7,8].includes(month)) {
    if (hour >= 17 && hour < 22) return 'critical';
    if (hour >= 16 && hour < 23) return 'peak';
  } else {
    if (hour >= 11 && hour < 14) return 'deep';
    if (hour >= 10 && hour < 15) return 'valley';
    if (hour >= 17 && hour < 19) return 'critical';
    if (hour >= 16 && hour < 21) return 'peak';
  }
  return 'flat';
}
export function cloudStatus(hass, now = Date.now()) {
  const entity = hass.states[cloudEntity], attrs = entity?.attributes || {};
  const age = now - Date.parse(attrs.updated_at);
  const cloudAge = now - Date.parse(attrs.cloud_timestamp);
  const available = Array.isArray(attrs.sessions) && Number.isFinite(age);
  const fresh = available && age >= -60000 && age < 900000;
  const power = fresh && cloudAge >= -60000 && cloudAge < 900000 ? numeric(entity.state) : null;
  return {available, fresh, power, updatedAt:attrs.updated_at, year:Number(attrs.coverage_year), sessions:attrs.sessions || []};
}
export function sessionBreakdown(row) {
  if (!row || !Number.isFinite(row.start) || !Number.isFinite(row.seconds) || row.seconds <= 0 || row.seconds > 31*86400 || !Number.isFinite(row.kwh) || row.kwh < 0) return null;
  const start=row.start*1000, end=start+row.seconds*1000;
  if (!Number.isFinite(new Date(start).getTime()) || !Number.isFinite(new Date(end).getTime())) return null;
  const averageKw=row.kwh/(row.seconds/3600), segments=[];
  let supported=true;
  for(let t=start;t<end;) {
    const next=Math.min(end,(Math.floor(t/3600000)+1)*3600000), date=new Date(t+28800000);
    const tariff=evPeriod(date.getUTCMonth()+1,date.getUTCHours(),date.getUTCFullYear());
    supported &&= date.getUTCFullYear()===2026;
    const kwh=averageKw*(next-t)/3600000;
    const previous=segments.at(-1);
    if(previous?.tariff===tariff){previous.end=next;previous.kwh+=kwh;}
    else segments.push({start:t,end:next,tariff,price:evRates[tariff],kwh});
    t=next;
  }
  for(const segment of segments)segment.fee=supported?segment.kwh*segment.price:null;
  return {start,end,seconds:row.seconds,kwh:row.kwh,averageKw,segments,fee:supported?segments.reduce((sum,s)=>sum+s.fee,0):null,source:row.source||'cloud'};
}
function mergedSessionRows(hass,now) {
  const cloud=cloudStatus(hass,now).sessions;
  return [...cloud,...observed.filter(row=>!cloud.some(c=>{
    const overlap=Math.min(row.start+row.seconds,c.start+c.seconds)-Math.max(row.start,c.start);
    return overlap>0 && overlap>=Math.min(row.seconds,c.seconds)*0.5;
  }))];
}
export function chargingSessions(hass, now=Date.now()) {
  const seen=new Set();
  return mergedSessionRows(hass,now).map(sessionBreakdown).filter(row=>{
    if(!row || row.start>now || seen.has(row.start))return false;
    seen.add(row.start);return true;
  }).sort((a,b)=>b.start-a.start);
}
export function chargingSummary(hass, key, now = Date.now()) {
  const status = cloudStatus(hass, now);
  if ((!status.available && !observed.length) || Number(key.slice(0,4)) !== status.year) return null;
  const from = Date.parse(key.length === 4 ? `${key}-01-01T00:00:00+08:00` : key.length === 7 ? `${key}-01T00:00:00+08:00` : `${key}T00:00:00+08:00`);
  const local = new Date(from + 28800000);
  const until = key.length === 4 ? Date.UTC(local.getUTCFullYear()+1,0,1)-28800000 : key.length === 7 ? Date.UTC(local.getUTCFullYear(),local.getUTCMonth()+1,1)-28800000 : from+86400000;
  const parts = Object.fromEntries(Object.keys(evRates).map(key=>[key,0]));
  let kwh=0, count=0, periodEstimated=false;
  const seen=new Set();
  for (const row of mergedSessionRows(hass,now)) {
    if (!Number.isFinite(row.start) || !Number.isFinite(row.seconds) || !(row.seconds>0) || row.seconds>31*86400 || !(row.kwh>=0) || !Number.isFinite(row.kwh) || seen.has(row.start)) continue;
    seen.add(row.start);
    const start=row.start*1000, end=start+row.seconds*1000;
    const a=Math.max(from,start), b=Math.min(until,end,now);
    if (!(b>a)) continue;
    count++;
    periodEstimated ||= row.source==='observed' || a!==start || b!==end;
    kwh += row.kwh * (b-a)/(end-start);
    // Session totals have no power curve: allocate across each hourly boundary as an estimate.
    for(let t=a;t<b;) {
      const next=Math.min(b,(Math.floor(t/3600000)+1)*3600000);
      const date=new Date(t+28800000);
      parts[evPeriod(date.getUTCMonth()+1,date.getUTCHours())] += row.kwh*(next-t)/(end-start);
      t=next;
    }
  }
  const fee = status.year===2026 ? Object.entries(parts).reduce((sum,[t,kwh])=>sum+kwh*evRates[t],0) : null;
  return {kwh,count,fee,parts,periodEstimated,fresh:status.fresh,updatedAt:status.updatedAt};
}
export function garagePower(hass) {
  const ebike=numeric(hass.states[ebikePowerEntity]?.state), tesla=cloudStatus(hass).power;
  return ebike===null||tesla===null?null:ebike+tesla;
}
