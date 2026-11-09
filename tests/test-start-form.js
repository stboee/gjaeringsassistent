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
const field={entity_id:'number.gjaeringsassistent_slurry_volum_ml',field_name:'slurry_volume_ml',section_id:'pitch',label:'Slurryvolum',input_type:'number',value:null,value_display:'Ikke angitt',minimum:0,maximum:5000,step:10,required:1,applicable:1,validation_status:'missing',validation_message:'Mangler: Slurryvolum',options:[]};
const requests=[];
card._config={view:'startfields',section:'pitch',title:'DB-startfelt'};
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
 console.log('PASS DB form renders NULL without stale HA fallback, sends same-value saves and waits for DB-published values');
})().catch(e=>{console.error(e);process.exitCode=1;});
