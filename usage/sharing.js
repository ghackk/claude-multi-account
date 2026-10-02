#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const C=require('./collector');
const queue=path.join(C.dataDir,'sharing-pending');
const read=file=>{try{return JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));}catch{return null;}};
function write(file,value){fs.mkdirSync(path.dirname(file),{recursive:true});const tmp=file+'.'+crypto.randomUUID()+'.tmp';fs.writeFileSync(tmp,JSON.stringify(value),{mode:0o600});fs.renameSync(tmp,file);}
function endpoint(base){const url=new URL(base);if(url.protocol!=='https:'&&!(url.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(url.hostname)))throw Error('Sharing requires HTTPS');if(url.username||url.password)throw Error('Invalid sharing endpoint');return url.origin;}
const receiptFile=p=>path.join(p.dir,'.multi-claude-share.json');
function metadata(names=[]){
 const device=C.identity(),profiles=C.profiles(false).filter(p=>!names.length||names.includes(p.name));
 const accounts=[...new Set(profiles.map(p=>p.email))],parents={},origins=new Map();
 for(const p of profiles){const r=read(receiptFile(p)),receipt=r?.device===device.fp&&r.email===p.email?r.receipt:null;
  if(!origins.has(p.email))origins.set(p.email,new Map());origins.get(p.email).set(receipt?.transfer_id||'unknown',receipt);
 }
 // Several selected copies of one account can have different origins. Do not invent a parent.
 for(const [email,receipts] of origins)if(receipts.size===1&&!receipts.has('unknown'))parents[email]=[...receipts.values()][0];
 return {protocol:2,client_version:require('./version'),request_id:crypto.randomUUID(),device,accounts,parents};
}
function begin(response,base){
 if(!response.transfer_id||!response.confirmation)return;
 if(!/^[a-f0-9-]{36}$/.test(response.transfer_id)||!Array.isArray(response.accounts)||!response.receipts)throw Error('Invalid sharing response');
 const file=path.join(queue,response.transfer_id+'.json');
 // Do not overwrite a completed result awaiting upload on a delivery retry.
 if(read(file))return;
 write(file,{base:endpoint(base),device:C.identity(),transfer_id:response.transfer_id,confirmation:response.confirmation,accounts:response.accounts,receipts:response.receipts});
}
function finish(response,base,status,names=[]){
 begin(response,base);if(!response.transfer_id)return;
 const file=path.join(queue,response.transfer_id+'.json'),job=read(file);if(!job||job.results)return;
 const profiles=C.profiles(false).filter(p=>names.includes(p.name));
 job.results=job.accounts.map(email=>{const p=profiles.find(p=>p.email===email);return {email,status:p?'installed':status==='cancelled'?'cancelled':'failed',profile:p?.name||''};});
 // Persist the result before receipts; a reporter can safely retry after a crash.
 write(file,job);
 saveReceipts(job,false);
}
function saveReceipts(job,confirmed){
 for(const r of job.results||[]){if(r.status!=='installed')continue;
  const p=C.profiles(false).find(p=>p.name===r.profile&&p.email===r.email);if(!p)continue;
  const old=read(receiptFile(p));
  // A delayed confirmation must not overwrite a newer import's provenance.
  if(confirmed&&old&&old.receipt?.transfer_id!==job.transfer_id)continue;
  write(receiptFile(p),{device:job.device.fp,email:r.email,receipt:job.receipts[r.email],confirmed});
 }
}
async function flush(){
 if(!fs.existsSync(queue))return {pending:0};const started=Date.now(),device=C.identity();
 const jobs=fs.readdirSync(queue).filter(n=>/^[a-f0-9-]{36}\.json$/.test(n)).map(name=>({file:path.join(queue,name),job:read(path.join(queue,name))})).filter(({job})=>job?.results);
 let pending=jobs.length;
 for(const {file,job} of jobs.slice(0,20)){
  if(Date.now()-started>=8000)break;
  if(job.device.fp!==device.fp)continue;
  try{
   const response=await fetch(endpoint(job.base)+'/api/sharing/confirm',{method:'POST',headers:{'Content-Type':'application/json','X-Client':'claude-pair'},body:JSON.stringify({transfer_id:job.transfer_id,device:job.device,confirmation:job.confirmation,results:job.results}),signal:AbortSignal.timeout(5000)});
   if(!response.ok||!(await response.json()).ok)continue;
   saveReceipts(job,true);try{fs.unlinkSync(file);pending--;}catch{}
  }catch{break;}
 }return {pending};
}
async function main(){
 const [cmd,base,status,...names]=process.argv.slice(2);
 if(cmd==='metadata'){await flush();console.log(JSON.stringify(metadata(process.argv.slice(3))));return;}
 if(cmd==='flush'){console.log(JSON.stringify(await flush()));return;}
 const response=JSON.parse(fs.readFileSync(0,'utf8').replace(/^\uFEFF/,''));
 if(cmd==='begin')begin(response,base);
 else if(cmd==='finish'){finish(response,base,status,names);const result=await flush();if(result.pending)console.error('Sharing confirmation queued; the installed profile is unchanged.');}
 else throw Error('Unknown sharing command');
}
if(require.main===module)main().catch(e=>{console.error('Sharing tracking: '+e.message);process.exitCode=1;});
module.exports={metadata,begin,finish,flush};
