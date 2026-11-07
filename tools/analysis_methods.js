// Shared generic calculation models. All tuning and publication limits are DB inputs.
// Embedded verbatim into the three Node-RED calculation producers at build time.
const gaMethods=(()=>{
 const finite=v=>v!==null&&v!==undefined&&v!==''&&Number.isFinite(Number(v));
 const median=a=>{const s=a.filter(finite).map(Number).sort((a,b)=>a-b),n=s.length;return n?n%2?s[(n-1)/2]:(s[n/2-1]+s[n/2])/2:null;};
 const time=r=>r.at??r.t;
 const positive=(p,names)=>names.every(k=>finite(p[k])&&Number(p[k])>0);
 function baseline(rows,field,p,pitch,to,gaps){
  if(!positive(p,['sample_count','window_minutes','maximum_start_delay_minutes','minimum_span_minutes','maximum_range_points','maximum_gap_minutes']))return {value:null,error:'missing_baseline_policy'};
  const q=rows.filter(r=>time(r)>=pitch&&time(r)<=Math.min(to,pitch+Number(p.window_minutes)*60000)&&finite(r[field]));
  if(!q.length||time(q[0])-pitch>Number(p.maximum_start_delay_minutes)*60000)return {value:null,validationError:'baseline_missing_near_pitch'};
  const good=[];
  for(const r of q){
   const previous=good.at(-1);
   if(previous&&(time(r)-time(previous)>Number(p.maximum_gap_minutes)*60000||gaps.some(g=>g.start<time(r)&&(g.end??Infinity)>time(previous))))break;
   good.push(r);
   if(good.length>=Number(p.sample_count)&&time(r)-time(good[0])>=Number(p.minimum_span_minutes)*60000){
    const vals=good.map(x=>Number(x[field]));
    if((Math.max(...vals)-Math.min(...vals))*1000>Number(p.maximum_range_points))return {value:null,validationError:'baseline_unstable_at_pitch'};
    return {value:median(vals),measuredAt:time(r),windowStartedAt:time(good[0]),windowEndedAt:time(r),sampleCount:good.length,coverageSeconds:(time(r)-time(good[0]))/1000};
   }
  }
  return {value:null,validationError:'baseline_insufficient_contiguous_pitch_data',sampleCount:good.length};
 }
 function rate(rows,field,p,from,to,gaps){
  if(!positive(p,['minimum_samples','minimum_span_minutes'])||!Number.isInteger(Number(p.minimum_samples))||Number(p.minimum_samples)<2)return {value:null,error:'missing_endpoint_rate_policy'};
  let start=from;for(const g of gaps)if(g.start<=to&&(g.end??Infinity)>start)start=Math.max(start,g.end??to+1);
  const q=rows.filter(r=>time(r)>=start&&time(r)<=to&&finite(r[field])).sort((a,b)=>time(a)-time(b));
  const info={sampleCount:q.length,measuredAt:q.at(-1)?time(q.at(-1)):null,windowStartedAt:q[0]?time(q[0]):start,windowEndedAt:q.at(-1)?time(q.at(-1)):to,coverageSeconds:q.length>1?(time(q.at(-1))-time(q[0]))/1000:0,requestedWindowSeconds:(to-from)/1000};
  if(q.length<Number(p.minimum_samples)||info.coverageSeconds<Number(p.minimum_span_minutes)*60)return {...info,value:null,validationError:'endpoint_rate_insufficient_span'};
  return {...info,value:1000*(Number(q[0][field])-Number(q.at(-1)[field]))*86400/info.coverageSeconds};
 }
 function attenuation(og,sg){return finite(og)&&Number(og)>1&&finite(sg)?100*(Number(og)-Number(sg))/(Number(og)-1):null;}
 return {baseline,rate,median,attenuation};
})();
