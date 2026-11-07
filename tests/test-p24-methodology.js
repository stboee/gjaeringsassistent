'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),helper=fs.readFileSync(path.join(root,'tools/analysis_methods.js'),'utf8');
const methods=new Function(helper+';return gaMethods;')();
const flow=JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'),'utf8'));
// Use the shipped seed parameters, avoiding a test-only set of hidden defaults.
const seed=fs.readFileSync(path.join(root,'sql/03-w3470-template-seed.sql'),'utf8');
function policy(id){const out={};for(const m of seed.matchAll(new RegExp("'"+id+"','(?:pitch_baseline_median_v1|endpoint_rate_v1)','([^']+)','(real|integer)',([^,]+),([^,]+),",'g')))out[m[1]]=Number(m[m[2]==='real'?3:4]);return out;}
const bp=policy('tilt_baseline'),rp=policy('sg_rate');assert.equal(rp.minimum_span_minutes,1080);assert.equal(bp.sample_count,3);
const start=Date.parse('2026-10-01T00:00:00Z'),rows=(n,rate=4)=>Array.from({length:n},(_,i)=>({at:start+i*300000,sg:1.05-rate/1000*i/288}));
const calculate=(a,p=rp,gaps=[])=>methods.rate(a,'sg',p,start-86400000,a.at(-1).at,gaps);
let r=calculate(rows(289));assert.ok(Math.abs(r.value-4)<1e-8);assert.equal(r.rangeMin,undefined);assert.equal(r.rangeMax,undefined);
r=calculate(rows(289,0));assert.ok(Math.abs(r.value)<1e-8,'Good flat measurements publish zero');
assert.equal(calculate(rows(6)).value,null,'25 min below conservative sensitivity limit');
const spike=rows(289);spike[140].sg+=.005;r=calculate(spike);assert.ok(Math.abs(r.value-4)<.01);assert.equal(r.outlierCount,undefined);
const polluted=rows(13);polluted.forEach((p,i)=>p.sg+=i%2?.005:-.005);assert.equal(calculate(polluted).value,null);
const gap={start:start+300000,end:start+23*3600000};r=calculate(rows(289),rp,[gap]);assert.equal(r.windowStartedAt,gap.end);assert.equal(r.sampleCount,13);assert.equal(r.value,null);
assert.equal(calculate(rows(13),rp,[{start:start+300000,end:null}]).value,null);
const pitch=rows(4,0),resumed=rows(12,0).map(r=>({...r,at:r.at+11*3600000,sg:1.044}));
const base=methods.baseline([...pitch,...resumed],'sg',bp,start,resumed.at(-1).at,[{start:start+20*60000,end:resumed[0].at}]);
assert.equal(base.value,1.05);assert.equal(base.sampleCount,3);assert.equal(base.measuredAt,start+600000);
assert.equal(methods.baseline(resumed,'sg',bp,start,resumed.at(-1).at,[]).value,null,'Late data cannot replace pitch calibration');
const unstable=rows(3);unstable[2].sg=1.06;assert.equal(methods.baseline(unstable,'sg',bp,start,unstable[2].at,[]).value,null);
for(const id of ['p20_bio_eval_result','p20_process_eval_result','p22_analysis_result'])assert.ok(flow.find(n=>n.id===id).func.startsWith(helper),'Same calculation implementation: '+id);
// Exercise both production adapters, including source-field and pitch-time handling.
for(const scope of ['bio','process']){
 const source=flow.find(n=>n.id==='p20_'+scope+'_eval_result').func;
 const prefix=source.slice(0,source.indexOf('function evaluateMetric'));
 const calculation=(measurements,params=rp,model='endpoint_rate_v1')=>new Function('msg',prefix+";return evaluateCalculation('test',"+measurements.at(-1).at+",{});")({payload:[
 [{_set:'summary',session_id:'test',current_phase_id:'B1',current_process_id:'P1',pitched_at:new Date(start).toISOString()}],
 measurements.map(r=>({_set:'series',at:new Date(r.at).toISOString(),tilt_sg:r.sg})),
 [{_set:'calculations',calculation_id:'test',model_id:model}],
 [{_set:'calculation_inputs',calculation_id:'test',input_id:'series_sg',source_kind:'series',source_id:'tilt_sg'}],
 Object.entries(params).map(([parameter_id,value])=>({_set:'calculation_params',calculation_id:'test',parameter_id,data_type:'real',real_value:value}))
 ]});
 assert.ok(Math.abs(calculation(rows(289)).value-4)<1e-8,scope+' same measured endpoint rate');
 assert.ok(Math.abs(calculation(rows(289,0)).value)<1e-8,scope+' true zero');
 assert.equal(calculation(rows(6)).value,null,scope+' same minimum-span rejection');
 assert.equal(calculation(rows(3,0),bp,'pitch_baseline_median_v1').value,1.05,scope+' pitch baseline');
}
// The actual raw filter must reject minority extremes even when MAD equals zero.
const src=flow.find(n=>n.id==='p21_live_history_process').func,a=src.indexOf('const validate='),b=src.indexOf('\nconst rows=',a);
const rulesBy={sg:[{model_id:'robust_mad_v1',parameters:{mad_multiplier:6,noise_floor:.0001}}]};
const validate=new Function('rulesBy','median','mean','ms','g',src.slice(a,b)+';return validate;')(rulesBy,methods.median,a=>a.reduce((s,v)=>s+v,0)/a.length,Date.parse,{poll_interval_seconds:300});
const raw=[...Array(20).fill(1.0349),1.0308,1.0383];const accepted=validate('sg',raw,null,null,null);assert.equal(accepted.accepted.length,20);assert.equal(accepted.value,1.0349);
for(const scope of ['bio','process']){
 const f=flow.find(n=>n.id==='p20_'+scope+'_criterion_correction_context_result').func;
 const run=(parameters,base=[],model='threshold')=>new Function('msg',f)({ga_correction_request:{action:'override',parameters},payload:[[{_set:'criterion',session_id:'test',phase_id:'B5',process_id:'P5',criterion_id:'test',model_id:model}],[{_set:'allowed',parameter_id:'minimum_value',data_type:'real'},{_set:'allowed',parameter_id:'maximum_value',data_type:'real'},{_set:'allowed',parameter_id:'maximum_age_minutes',data_type:'integer'}],[...base.map(r=>({_set:'base_params',...r}))]]});
 assert.equal(run({minimum_value:75,maximum_value:0})[0],null);assert.equal(run({minimum_value:75,maximum_age_minutes:0})[0],null);assert.ok(run({minimum_value:75})[0]);
 assert.equal(run({minimum_value:90},[{parameter_id:'maximum_value',data_type:'real',real_value:80}])[0],null,'Merged inherited upper bound is validated');
 assert.equal(run({minimum_value:null,maximum_value:80},[], 'window_median_range')[0],null,'Mandatory interval bounds cannot be cleared');
 const clear=run({minimum_value:75,maximum_value:null,maximum_age_minutes:null})[0];assert.ok(clear);assert.match(clear.topic,/is_unset/);assert.equal(clear.payload.filter(v=>v===1).length>=3,true,'Explicit null is persisted as unset');
}
const missingFloor=new Function('rulesBy','median','mean','ms','g',src.slice(a,b)+';return validate;')({sg:[{model_id:'robust_mad_v1',parameters:{mad_multiplier:6}}]},methods.median,a=>a.reduce((s,v)=>s+v,0)/a.length,Date.parse,{poll_interval_seconds:300});assert.equal(missingFloor('sg',raw,null,null,null).reason,'missing_validation_policy');
console.log('RESULT: PASS – shared measured endpoint rate, zero trend, insufficient short windows, outliers, gaps, pitch baseline, MAD=0 and correction semantics');
