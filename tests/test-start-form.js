'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.resolve(__dirname,'..'),classes=new Map(),listeners=[];
class Element{
 attachShadow(){this.shadowRoot={innerHTML:'',activeElement:null,querySelectorAll:()=>listeners,querySelector:()=>null};}
}
const window={customCards:[]};
vm.runInNewContext(fs.readFileSync(path.join(root,'dashboard/gjaeringsassistent-card.js'),'utf8'),{
 HTMLElement:Element,customElements:{get:n=>classes.get(n),define:(n,c)=>classes.set(n,c)},window,console,URL,Date,Math,setTimeout,clearTimeout
});
const Card=classes.get('gjaeringsassistent-card'),card=new Card();
// Read the actual dashboard's scalar card properties, including its nesting.
// Configuration must enter through HA's public setConfig boundary.
const lines=fs.readFileSync(path.join(root,'dashboard/gjaeringsassistent-dashboard.yaml'),'utf8').split('\n'),configs=[];
for(let i=0;i<lines.length;i++){
 const at=lines[i].indexOf('type: custom:gjaeringsassistent-card');if(at<0)continue;
 const config={type:'custom:gjaeringsassistent-card'};
 for(let j=i+1;j<lines.length;j++){
  if(!lines[j].trim())continue;
  const indentation=lines[j].search(/\S/);if(indentation<at)break;
  if(indentation===at){const match=lines[j].trim().match(/^(\w+): (.+)$/);if(match)config[match[1]]=match[2];}
 }
 if(config.view==='startfields')configs.push(config);
}
assert.deepEqual(configs.map(c=>c.section).sort(),['measurement','pitch']);
for(const config of configs){const instance=new Card();assert.doesNotThrow(()=>instance.setConfig(config),config.title);instance.hass={states:{}};assert.match(instance.shadowRoot.innerHTML,/DB-kontrakt: startfelt mangler/);}
assert.throws(()=>new Card().setConfig({view:'unknown-view'}),/støtter view/);
const field={entity_id:'number.gjaeringsassistent_slurry_volum_ml',field_name:'slurry_volume_ml',section_id:'pitch',label:'Slurryvolum',input_type:'number',value:null,value_display:'Ikke angitt',minimum:0,maximum:5000,step:10,required:1,applicable:1,validation_status:'missing',validation_message:'Mangler: Slurryvolum',options:[]};
const requests=[];
card.setConfig(configs.find(c=>c.section==='pitch'));
card._hass={states:{'sensor.gjaeringsassistent_startstatus':{state:'idle',attributes:{start_fields:[field],start_ready:0}},'number.gjaeringsassistent_slurry_volum_ml':{state:'4000'}},callApi:async(...args)=>requests.push(args)};
card._renderStartFields();
assert.match(card.shadowRoot.innerHTML,/value=""/);assert.match(card.shadowRoot.innerHTML,/Ikke angitt/);assert.doesNotMatch(card.shadowRoot.innerHTML,/value="4000"/);
let changed;
listeners.push({dataset:{entity:field.entity_id},value:'4000',addEventListener:(name,handler)=>{assert.equal(name,'change');changed=handler;}});
card._renderStartFields();
(async()=>{
 await changed();await changed();
 assert.equal(requests.length,2,'explicit same-value save must not depend on a HA state change');
 assert.equal(requests[0][0],'POST');assert.equal(requests[0][1],'events/gjaeringsassistent_set_start_field');
 assert.equal(requests[0][2].entity_id,field.entity_id);assert.equal(requests[0][2].value,'4000');
 assert.equal(field.value,null,'request acceptance must not invent persisted input');
 card._hass.states['sensor.gjaeringsassistent_startstatus'].attributes.start_fields[0]={...field,value:'4000',validation_status:'ok',validation_message:'Lagret i MariaDB'};
 card._renderStartFields();assert.match(card.shadowRoot.innerHTML,/value="4000"/);assert.match(card.shadowRoot.innerHTML,/Lagret i MariaDB/);
 console.log('PASS both actual dashboard start cards enter through setConfig; DB form renders NULL without stale HA fallback, sends same-value saves and waits for DB-published values');
})().catch(e=>{console.error(e);process.exitCode=1;});
