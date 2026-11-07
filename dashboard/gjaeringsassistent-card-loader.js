(()=>{
  const base='/local/gjaeringsassistent';
  const manifestUrl=`${base}/frontend-manifest.json?_=${Date.now()}`;
  fetch(manifestUrl,{cache:'no-store',credentials:'same-origin'})
    .then(response=>{if(!response.ok)throw new Error(`Gjæringsassistent frontend-manifest HTTP ${response.status}`);return response.json();})
    .then(manifest=>{const card=manifest?.files?.card;if(!card?.public_name||!card?.sha256)throw new Error('Gjæringsassistent frontend-manifest mangler card');return import(`${base}/${card.public_name}?sha=${encodeURIComponent(String(card.sha256).slice(0,16))}`);})
    .catch(error=>console.error('Gjæringsassistent frontend-loader:',error));
})();
