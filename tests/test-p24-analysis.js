'use strict';
// REQ-MOTOR-044 REQ-HA-069 REQ-HA-070 REQ-HA-071 REQ-HA-074 REQ-HA-075
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),flow=JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'),'utf8'));
const fn=flow.find(n=>n.id==='p22_analysis_result').func;
const start=Date.parse('2026-10-01T00:00:00Z'),at=i=>new Date(start+i*300000).toISOString();
const policy={graph_id:'generic',series_id:'rate',source_kind:'metric',metric_id:'arbitrary',minimum_samples:12,minimum_coverage_fraction:.75,warmup_minutes:1080,provisional_allowed:0,provisional_minimum_samples:3,provisional_minimum_span_minutes:10,band_model:'none'};
const rows=n=>Array.from({length:n},(_,i)=>({_set:'measurements',bucket_at:at(i),sg_value:1.05,sg_median:1.05-i*.00001,sg_min:1.0499-i*.000009,sg_max:1.0501-i*.000011}));
const cp=Object.entries({window_hours:24,minimum_samples:12,minimum_span_minutes:1080}).map(([parameter_id,value])=>({_set:'calc_params',calculation_id:'reg',parameter_id,data_type:parameter_id==='minimum_samples'?'integer':'real',integer_value:value,real_value:value}));
function run(measurements,defs=[policy],extra=[]){return new Function('msg','node',fn)({payload:[[{_set:'context',session_id:'test',og:1.05,pitched_at:at(0)}],defs.map(d=>({_set:'series_defs',...d})),measurements,[{_set:'metric_rules',metric_id:'arbitrary',calculation_model_id:'metric-calculation-output-v1'}],[{_set:'metric_inputs',metric_id:'arbitrary',input_id:'calculation',source_kind:'biology_calculation',source_id:'reg'}],[{_set:'calc_rules',calculation_id:'reg',model_id:'endpoint_rate_v1'}],cp,...extra]}, {error:e=>{throw Error(e)}});}
function values(msg){assert.equal(msg.ga_analysis.rejected_values,0);return Array.from({length:msg.ga_analysis.accepted_values},(_,i)=>(()=>{const row=msg.payload.slice(i*19,i*19+19);assert.equal(row[4],at(0).replace('T',' ').replace('Z',''));return [...row.slice(0,4),...row.slice(5)];})());}
assert.equal(run(rows(2)).ga_analysis.accepted_values,0);
assert.equal(run(rows(145)).ga_analysis.accepted_values,0,'12 hours is not published as a complete rate');
const mature=run(rows(289)),v=values(mature),p=v.at(-1);
assert.equal(v[0][5],'standard');assert.equal(p[6],1);assert.equal(p[7],null);assert.equal(p[8],null);
assert.ok(Math.abs(p[4]-2.88)<1e-8);assert.equal(p[14],86400);
assert.match(mature.topic,/INSERT IGNORE INTO analysis_series_values/);assert.doesNotMatch(mature.topic,/UPDATE analysis_series_values/);
const gap=[{_set:'gaps',gap_started_at:at(1),gap_ended_at:at(200)}];
assert.equal(run(rows(289),[policy],[gap]).ga_analysis.accepted_values,0,'insufficient time after a real gap');
assert.equal(run(rows(289),[policy],[[{_set:'gaps',gap_started_at:at(1),gap_ended_at:null}]]).ga_analysis.accepted_values,0);
const stab={...policy,series_id:'stable',source_kind:'biological_criterion',owner_id:'owner',criterion_id:'criterion',band_model:'none'};
const params=Object.entries({window_hours:24,minimum_samples:12,minimum_span_hours:18,since_current_process_start:false}).map(([parameter_id,value])=>({_set:'bio_params',phase_id:'owner',criterion_id:'criterion',parameter_id,data_type:typeof value==='boolean'?'boolean':parameter_id==='minimum_samples'?'integer':'real',boolean_value:value?1:0,integer_value:value,real_value:value}));
assert.equal(run(rows(4),[stab],[params]).ga_analysis.accepted_values,0);
const sv=values(run(rows(289),[stab],[params]));assert.ok(sv.length>0);assert.equal(sv[0][5],'standard');assert.equal(sv[0][7],null);assert.equal(sv[0][8],null);assert.ok(Math.abs(sv.at(-1)[4]-2.88)<1e-8);
// Raw Tilt remains available without pitch measurements or a baseline.
const raw={...policy,series_id:'raw',metric_id:'raw',minimum_samples:1,minimum_coverage_fraction:0,warmup_minutes:0};
const manual={...raw,series_id:'manual',metric_id:'manual',render_mode:'points'};
const sourceRows=rows(1).map(r=>({...r,bucket_at:at(100),sg_median:1.0135}));
const obs=[{_set:'observations',observation_revision_id:'manual-r1',recorded_at:at(90),corrected_sg:1.01}];
const separate=new Function('msg','node',fn)({payload:[[{_set:'context',session_id:'test',og:1.048,pitched_at:at(0)}],[{_set:'series_defs',...raw},{_set:'series_defs',...manual}],sourceRows,obs,[{_set:'metric_rules',metric_id:'raw',calculation_model_id:'metric-raw-attenuation-v1'},{_set:'metric_rules',metric_id:'manual',calculation_model_id:'metric-manual-attenuation-v1'}]]},{error:e=>{throw Error(e)}});
const both=values(separate);assert.equal(both.length,2);assert.ok(Math.abs(both[0][4]-71.875)<1e-8);assert.ok(Math.abs(both[1][4]-79.1666666667)<1e-8);assert.notEqual(both[0][3],both[1][3],'manual retains its own actual timestamp');
const renderer=fs.readFileSync(path.join(root,'tools/graph_renderer.js'),'utf8');
assert.ok(fs.readFileSync(path.join(root,'dashboard/gjaeringsassistent-card.js'),'utf8').startsWith(renderer));
for(const id of ['p22_active_report_result','p21_session_export_read_result'])assert.ok(flow.find(n=>n.id===id).func.startsWith(renderer));
const payloadHelper=fs.readFileSync(path.join(root,'tools/presentation_payload.js'),'utf8');const directRender=new Function(renderer+';return gaRenderAnalysisSvg;')(),pack=new Function(payloadHelper+';return gaPackAnalysisPresentation;')();const render=data=>{const p=pack({series:data.series});return directRender({...data,series:p.series,definitions:p.series_definitions});},graph={canvas_width:900,canvas_height:420,compact_height:280,margin_left:68,margin_right:20,margin_top:46,margin_bottom:48,date_font_size:11,axis_font_size:11,marker_font_size:10,font_family:'sans-serif',line_width:2.4,point_radius:2,graph_id:'generic',label:'Test',x_axis_started_at:at(0),x_axis_ended_at:at(12),y_axis_min:0,y_axis_max:4,gap_policy:'measurement_gaps'};
const point={graph_id:'generic',series_id:'rate',label:'Rate',sample_at:at(2),actual_value:2.88,range_min_value:2.5,range_max_value:3,line_color:'#ff8f00',line_dasharray:'6 4',band_model:'none',band_opacity:.24,band_description:'Ingen bånd',basis_display:'Foreløpig · 3 målinger / 10 min',actual_value_display:'2,88 pkt/døgn'};
const data={graph,referenceBands:[],series:[point],axisTicks:[],timeMarkers:[],requirements:[],biology:[],process:[],gaps:[]};
let svg=render({...data,latest:[{graph_id:'generic',latest_value_display:'Rate · −0,19 SG-poeng/døgn · målt 08.10.2026 23:05'}]});assert.match(svg,/−0,19/);assert.match(svg,/analysis-point/);assert.match(svg,/stroke-dasharray:6 4/);assert.match(svg,/3 målinger \/ 10 min/);assert.doesNotMatch(svg,/polygon/);
svg=render({...data,series:[point,{...point,sample_at:at(3)}]});assert.doesNotMatch(svg,/polygon/);
svg=render({...data,series:[{...point,band_model:'regression_input_range'},{...point,band_model:'regression_input_range',sample_at:at(12)}],gaps:[{gap_started_at:at(3),gap_ended_at:at(11)}]});assert.doesNotMatch(svg,/polygon/);assert.equal((svg.match(/<path class="analysis-line"/g)||[]).length,2);
assert.doesNotMatch(render({...data,series:[{...point,render_mode:'points'}]}),/analysis-line/);assert.doesNotMatch(render({...data,series:[{...point,actual_value:-.19}]}),/analysis-point/);
assert.match(render({...data,series:[]}),/Ingen gyldige analyseverdier/);
// Exercise the complete report producers with valid graph data, not only a
// missing-axis fixture. Both must present the same status and biological audit.
const axes=['sg','temperature','pressure'].map(graph_id=>({_set:'overview_axes',graph_id,y_axis_min:0,y_axis_max:2,y_axis_tick_step:.5,x_axis_started_at:at(0),x_axis_ended_at:at(12),x_axis_start_display:'Pitch',x_axis_end_display:'Slutt',band_model:'sample_range',band_description:'Målespredning',band_opacity:.24}));
const audit={_set:'bio_exceptions',created_display:'01.10.2026 02:10',owner_id:'B2',label:'Testkriterium',action_display:'Registrert',exception_type_display:'Akseptert avvik',note_display:'–'};
function report(id,payload){const node=flow.find(n=>n.id===id);return new Function('msg','node',node.func)({_msgid:'test-report',payload,ga_archive_attempt_id:'test-attempt',ga_template_path:'/data/template.sqlite'},{error:e=>{throw Error(e)}});}
const common=[axes,[{_set:'analysis_graphs',...graph}],[{_set:'analysis_series',...point}],[audit]];
let active=report('p22_active_report_result',[[{_set:'clock',generated_display:'01.10.2026',file_stamp:'test'}],[{_set:'summary',session_id:'test'}],[{_set:'session',session_id:'test',batch_name:'Test'}],[{_set:'series',at_ms:start+600000,sg_value:1.05,sg_median:1.05,sg_min:1.049,sg_max:1.051,temperature_mean_c:1,temperature_min_c:.9,temperature_max_c:1.1,pressure_mean_bar:null,pressure_min_bar:null,pressure_max_bar:null}],...common]);
assert.match(active.payload,/stroke-dasharray:6 4/);assert.match(active.payload,/Biologiske kriteriefravik/);assert.match(active.payload,/Testkriterium/);assert.doesNotMatch(active.payload,/NaN|undefined/);
let completed=report('p21_session_export_read_result',[[{_set:'archive_session',session_id:'test',batch_name:'Test',pitched_at:at(0)}],[{_set:'clock',generated_display:'01.10.2026',file_stamp:'test',database_now:at(12)}],[{_set:'summary',session_id:'test'}],[{_set:'session',session_id:'test',batch_name:'Test'}],...common]);
assert.match(completed.payload,/stroke-dasharray:6 4/);assert.match(completed.payload,/Biologiske kriteriefravik/);assert.match(completed.payload,/Testkriterium/);assert.doesNotMatch(completed.payload,/NaN|undefined/);
console.log('RESULT: PASS – p24r6 measured endpoints and raw/manual sources, gaps, stability without band, single point, shared renderer');
