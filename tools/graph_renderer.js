/* Shared SVG presentation for measured and calculated series. Values, labels, axes and styles are DB read-model fields.
 * This source is embedded verbatim into the card and both report producers at build.
 * It has no metric/graph IDs, statistical calculations or domain fallback values.
 */
function gaRenderAnalysisSvg(data){
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const time=v=>v===null||v===undefined?NaN:new Date(typeof v==='string'&&!/[zZ]$|[+-]\d{2}:?\d{2}$/.test(v)?v.replace(' ','T')+'Z':v).getTime();
  const finite=v=>v!==null&&v!==undefined&&v!==''&&Number.isFinite(Number(v));
  const definitions=new Map((data.definitions||[]).map(r=>[r.presentation_id,r]));
  const expanded=data.series.map(r=>{if(r.presentation_id===undefined)throw Error('Grafpunkt mangler presentasjonsreferanse');const metadata=definitions.get(r.presentation_id);if(!metadata)throw Error('Grafpunkt mangler presentasjonsmetadata');return {...metadata,...r};});
  const g=data.graph,all=expanded.filter(r=>r.graph_id===g.graph_id),rows=all.filter(r=>Number.isFinite(time(r.sample_at))&&finite(r.actual_value));
  const x0=time(g.x_axis_started_at),x1=time(g.x_axis_ended_at),lo=Number(g.y_axis_min),hi=Number(g.y_axis_max);
  if(![x0,x1,lo,hi].every(Number.isFinite)||x1<=x0||hi<=lo)return '<p class="warn">Grafen mangler gyldig aksemetadata fra MariaDB.</p>';
  const layout=['canvas_width','canvas_height','compact_height','margin_left','margin_right','margin_top','margin_bottom','date_font_size','axis_font_size','marker_font_size','line_width','point_radius'];
  if(layout.some(k=>!finite(g[k])||Number(g[k])<=0)||!g.font_family)throw Error('DB-kontrakt: grafens presentasjonspolicy mangler');
  const w=Number(g.canvas_width),h=Number(data.compact?g.compact_height:g.canvas_height),m={l:Number(g.margin_left),r:Number(g.margin_right),t:Number(g.margin_top),b:Number(g.margin_bottom)};
  const font=(size)=>`font:${Number(size)}px ${esc(g.font_family)}`;
  const X=t=>m.l+(t-x0)/(x1-x0)*(w-m.l-m.r),Y=v=>m.t+(hi-v)/(hi-lo)*(h-m.t-m.b);
  const path=points=>points.map((p,i)=>`${i?'L':'M'}${p[0].toFixed(2)},${p[1].toFixed(2)}`).join(' ');
  const gaps=data.gaps.map(r=>({a:time(r.gap_started_at),b:r.gap_ended_at?time(r.gap_ended_at):Infinity}));
  const crossing=(a,b)=>g.gap_policy==='measurement_gaps'&&gaps.some(r=>r.a<=b&&r.b>a);
  const ticks=data.axisTicks.filter(r=>r.graph_id===g.graph_id).map(r=>`<line class="gridline grid" x1="${m.l}" y1="${Y(Number(r.tick_value))}" x2="${w-m.r}" y2="${Y(Number(r.tick_value))}"/><text style="${font(g.axis_font_size)}" class="axis y" text-anchor="end" x="${m.l-7}" y="${Y(Number(r.tick_value))+3}">${esc(r.axis_label)}</text>`).join('');
  const days=data.timeMarkers.filter(r=>r.graph_id===g.graph_id).map(r=>{const t=time(r.marker_at);return t>=x0&&t<=x1?`<line class="day-line day" x1="${X(t)}" y1="${m.t}" x2="${X(t)}" y2="${h-m.b}"/><text style="${font(g.date_font_size)}" class="day-label" x="${X(t)+2}" y="${h-m.b+14}">${esc(r.axis_label)}</text>`:'';}).join('');
  const bio=Number(g.show_biological_bands)===1?data.biology.filter(r=>r.graph_id===g.graph_id).map((r,i)=>{const a=Math.max(x0,time(r.started_at)),b=Math.min(x1,r.ended_at?time(r.ended_at):x1);return Number.isFinite(a)&&Number.isFinite(b)&&b>=a?`<rect class="bio-band bio b${i%6+1}" x="${X(a)}" y="${m.t}" width="${X(b)-X(a)}" height="${h-m.t-m.b}"/><text style="${font(g.marker_font_size)}" class="bio-label" x="${X(a)+3}" y="${m.t+14}">${esc(r.label)}</text>`:'';}).join(''):'';
  const proc=Number(g.show_process_markers)===1?data.process.filter(r=>r.graph_id===g.graph_id).map(r=>{const t=time(r.started_at);return t>=x0&&t<=x1?`<line class="process-line process" x1="${X(t)}" y1="${m.t}" x2="${X(t)}" y2="${h-m.b}"/><text style="${font(g.marker_font_size)}" class="process-label" x="${X(t)+3}" y="${m.t+30}">${esc(r.label)}</text>`:'';}).join(''):'';
  const requirements=Number(g.show_criterion_markers)===1?data.requirements.filter(r=>r.graph_id===g.graph_id).map(r=>[r.minimum_value,r.maximum_value].filter(finite).map(v=>{const y=Y(Number(v)),t=time(r.met_at);return `<line class="criterion-line criterion" x1="${m.l}" y1="${y}" x2="${w-m.r}" y2="${y}"/><text style="${font(g.marker_font_size)}" class="criterion-label" x="${w-m.r-3}" y="${y-4}">${esc(r.owner_display)} · ${esc(r.requirement_display)}</text>${t>=x0&&t<=x1?`<circle class="criterion-dot" cx="${X(t)}" cy="${y}" r="4"/>`:''}`;}).join('')).join(''):'';
  const curves=[...new Set(rows.map(r=>r.series_id))].map(id=>{
    const rr=rows.filter(r=>r.series_id===id&&time(r.sample_at)>=x0&&time(r.sample_at)<=x1).sort((a,b)=>time(a.sample_at)-time(b.sample_at)),groups=[];let group=[],previous=null;
    for(const r of rr){
      if(Number(r.actual_value)<lo||Number(r.actual_value)>hi){if(group.length)groups.push(group);group=[];previous=null;continue;}
      const gap=previous&&(r.segment_id!==undefined?previous.segment_id!==r.segment_id:crossing(time(previous.sample_at),time(r.sample_at)));
      const styleChanged=previous&&(previous.line_color!==r.line_color||previous.line_dasharray!==r.line_dasharray);
      if((gap||styleChanged)&&group.length){groups.push(group);group=gap?[]:[previous];}
      group.push(r);previous=r;
    }
    if(group.length)groups.push(group);
    return groups.map(items=>{
      const style=items.at(-1),points=items.map(r=>[X(time(r.sample_at)),Y(Number(r.actual_value))]);
      let band='';
      if(style.band_model!=='none'&&items.length>1&&items.every(r=>finite(r.range_min_value)&&finite(r.range_max_value))){
        const upper=items.map(r=>[X(time(r.sample_at)),Y(Number(r.range_max_value))]),lower=items.map(r=>[X(time(r.sample_at)),Y(Number(r.range_min_value))]);
        const polygon=upper.concat(lower.slice().reverse()).map(p=>p.join(',')).join(' ');
        band=`<polygon class="analysis-range-band analysis-band" style="fill:${esc(style.line_color)};opacity:${Number(style.band_opacity)}" points="${polygon}"><title>${esc(style.band_description)}</title></polygon>`;
      }
      const drawPoints=style.render_mode==='step'?points.flatMap((p,i)=>i?[[p[0],points[i-1][1]],p]:[p]):points;
      const line=style.render_mode==='points'?'':`<path class="analysis-line" style="fill:none;stroke:${esc(style.line_color)};stroke-dasharray:${esc(style.line_dasharray)};stroke-width:${Number(g.line_width)}" d="${path(drawPoints)}"/>`;
      const markers=items.map(r=>`<circle class="analysis-point" style="fill:${esc(r.line_color)}" cx="${X(time(r.sample_at))}" cy="${Y(Number(r.actual_value))}" r="${Number(g.point_radius)}"><title>${esc(r.actual_value_display)} · ${esc(r.basis_display)}</title></circle>`).join('');
      return band+line+markers;
    }).join('');
  }).join('');
  const legend=[...new Set(all.map(r=>r.series_id))].map(id=>{const latest=rows.filter(r=>r.series_id===id).sort((a,b)=>time(a.sample_at)-time(b.sample_at)).at(-1),definition=all.find(r=>r.series_id===id);return `<span>${esc(definition.label)}${latest?' · '+esc(latest.basis_display):''}<br><small>${esc(definition.band_description)}</small></span>`;}).join(' · ');
  const referenceBands=data.referenceBands.filter(r=>r.graph_id===g.graph_id&&finite(r.minimum_value)&&finite(r.maximum_value)).map(r=>`<rect class="reference" x="${m.l}" y="${Y(Number(r.maximum_value))}" width="${w-m.l-m.r}" height="${Math.abs(Y(Number(r.minimum_value))-Y(Number(r.maximum_value)))}" style="fill:${esc(r.line_color)};opacity:${Number(r.band_opacity)}"><title>${esc(r.label)}</title></rect>`).join('');
  const endpoints=`<text class="axis" text-anchor="start" style="${font(g.date_font_size)};text-anchor:start" x="${m.l}" y="${h-6}">${esc(g.x_axis_start_display)}</text><text class="axis" text-anchor="end" style="${font(g.date_font_size)};text-anchor:end" x="${w-m.r}" y="${h-6}">${esc(g.x_axis_end_display)}</text>`;
  const latest=(data.latest||[]).filter(r=>r.graph_id===g.graph_id).map(r=>`<strong>${esc(r.latest_value_display)}</strong>`).join('<br>');
  // Shared surface styling keeps dashboard themes and report CSS from changing SVG semantics.
  // All data-series styles and typography still come from the DB contract.
  const surfaceStyle='<style>.ga-graph .gridline{stroke:#ddd}.ga-graph .axis{fill:#666}.ga-graph .day-line{stroke:#ddd;stroke-dasharray:2 4}.ga-graph .day-label{fill:#666}.ga-graph .bio-band{opacity:.08}.ga-graph .bio-band.b1{fill:#1976d2}.ga-graph .bio-band.b2{fill:#ef6c00}.ga-graph .bio-band.b3{fill:#7b1fa2}.ga-graph .bio-band.b4{fill:#00897b}.ga-graph .bio-band.b5{fill:#c62828}.ga-graph .bio-band.b6{fill:#455a64}.ga-graph .bio-label,.ga-graph .process-label{fill:#333}.ga-graph .process-line{stroke:#6a1b9a;stroke-width:1;stroke-dasharray:3 3}.ga-graph .criterion-line{stroke:#d32f2f;stroke-width:1;stroke-dasharray:6 5}.ga-graph .criterion-label{fill:#d32f2f;text-anchor:end}.ga-graph .criterion-dot{fill:#d32f2f}</style>';
  return `<p class="analysis-current">${latest}</p><svg class="ga-graph" viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(g.label)}">${surfaceStyle}${bio}${referenceBands}${ticks}${days}${requirements}${curves}${proc}${endpoints}</svg><p class="analysis-basis legend">${legend}</p>${rows.length?'':'<p class="muted empty">Ingen gyldige analyseverdier ennå.</p>'}`;
}
