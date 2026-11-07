/* Transport projection only. The database owns all values and presentation.
 * Dictionary encoding removes repeated presentation fields without selecting
 * points, calculating values, or changing their timestamps or gap segments.
 */
function gaPackAnalysisPresentation(analysis){
  const metadataKeys=['label','render_mode','band_model','band_description','band_opacity','line_color','line_dasharray'];
  const pointKeys=['graph_id','series_id','sample_at','actual_value','range_min_value','range_max_value','actual_value_display','basis_display','segment_id'];
  const definitions=[],identities=new Map();
  const series=(analysis.series||[]).map(row=>{
    const metadata=Object.fromEntries(metadataKeys.filter(k=>Object.prototype.hasOwnProperty.call(row,k)).map(k=>[k,row[k]]));
    const key=JSON.stringify(metadata);
    if(!identities.has(key)){const presentation_id=definitions.length;identities.set(key,presentation_id);definitions.push({presentation_id,...metadata});}
    return {...Object.fromEntries(pointKeys.filter(k=>Object.prototype.hasOwnProperty.call(row,k)).map(k=>[k,row[k]])),presentation_id:identities.get(key)};
  });
  return {...analysis,series_definitions:definitions,series};
}
