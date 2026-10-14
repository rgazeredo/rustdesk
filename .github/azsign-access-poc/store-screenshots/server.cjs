// Loopback-only fixture API. This process never contacts a real CMS or device.
const https = require('node:https');
const fs = require('node:fs');
const names = ['Recepção — Demonstração','Vitrine — Demonstração','Sala de reunião — Demonstração','Corredor — Demonstração','Estoque — Demonstração'];
const statuses = ['available','available','offline','blocked','unprovisioned'];
const devices = names.map((name,i)=>({
  id:`00000000-0000-4000-8000-00000000000${i+1}`, name,
  remote_id:i===4?null:`90000000${i+1}`, tenant_id:'00000000-0000-4000-8000-000000000010',
  tenant_name:'Empresa demonstração',player_status:i===2?'offline':'online',
  remote_access_status:statuses[i], last_heartbeat_at:new Date().toISOString(),tags:[]
}));
https.createServer({pfx:fs.readFileSync('fixture.pfx'),passphrase:process.env.AZSIGN_CAPTURE_PFX_PASSWORD},(req,res)=>{
  const url = new URL(req.url,'https://app.azsign.com.br');
  fs.appendFileSync('store-screenshots/requests.txt',`${req.method} ${url.pathname}${url.search}\n`);
  res.setHeader('Content-Type','application/json');
  let data;
  if(url.pathname==='/api/v1/desktop/session'&&req.method==='GET') {
    if(req.headers.authorization?.startsWith('Bearer MSIX-CI-NOT-A-REAL-TOKEN-')!==true){res.statusCode=401;data={};}
    else data={expires_at:new Date(Date.now()+3600000).toISOString(),
      user:{id:'00000000-0000-4000-8000-000000000020',name:'Demonstração',email:'demo@example.com'},
      tenant:{id:'00000000-0000-4000-8000-000000000010',name:'Empresa demonstração'}};
  } else if(url.pathname==='/api/v1/desktop/address-book'&&req.method==='GET') {
    const search=(url.searchParams.get('search')||'').toLowerCase();
    const dataDevices=devices.filter(d=>d.name.toLowerCase().includes(search));
    data={data:dataDevices,meta:{current_page:1,last_page:1,per_page:20,total:dataDevices.length,from:1,to:dataDevices.length}};
  } else {res.statusCode=403;data={message:'Operation not allowed in screenshot fixture'};}
  res.end(JSON.stringify(data));
}).listen(443,'127.0.0.1',()=>fs.writeFileSync('fixture-ready.txt','ready'));
