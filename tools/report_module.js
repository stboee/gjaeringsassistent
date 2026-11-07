'use strict';
// Same owned renderer sources used by the Node-RED active/completed report nodes.
const fs=require('node:fs'),path=require('node:path');
const source=['graph_renderer.js','presentation_payload.js','report_renderer.js'].map(f=>fs.readFileSync(path.join(__dirname,f),'utf8')).join('\n');
const render=new Function(source+'\nreturn rows=>gaRenderSessionReport(gaReportSets(rows));')();
module.exports=render;
