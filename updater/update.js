'use strict';
const fs=require('fs'),path=require('path'),os=require('os'),crypto=require('crypto');
const {spawn,spawnSync}=require('child_process'),{extract}=require('./archive');
const MANIFEST='https://pair.ghackk.com/updates/stable.json';
const MIRROR='https://github.com/ghackk/claude-multi-account/releases/latest/download/stable.json';
const ROOT=path.resolve(__dirname,'..');
const BASE=process.env.MULTI_CLAUDE_UPDATE_DIR||path.join(os.homedir(),'.multi-claude-updates');
const read=(file,fallback={})=>{try{return JSON.parse(fs.readFileSync(file,'utf8'));}catch{return fallback;}};
function atomic(file,data){const tmp=file+'.'+crypto.randomUUID()+'.tmp';fs.writeFileSync(tmp,JSON.stringify(data),{mode:0o600});try{fs.renameSync(tmp,file);}finally{if(fs.existsSync(tmp))fs.unlinkSync(tmp);}}
function version(v){if(typeof v!=='string'||!/^\d{1,6}\.\d{1,6}\.\d{1,6}$/.test(v))throw Error('Invalid release version');return v.split('.').map(Number);}
function newer(a,b){const aa=version(a),bb=version(b);for(let i=0;i<3;i++)if(aa[i]!==bb[i])return aa[i]>bb[i];return false;}
function allowed(url){const u=new URL(url);if(u.protocol!=='https:'||u.username||u.password||u.port||u.hash)throw Error('Untrusted update URL');
 if(!(u.hostname==='pair.ghackk.com'&&u.pathname.startsWith('/updates/'))&&!(u.hostname==='github.com'&&(u.pathname.startsWith('/ghackk/claude-multi-account/releases/download/')||u.href===MIRROR)))throw Error('Untrusted update host');return u.href;}
function verify(envelope,key,now=Date.now()){
 if(typeof envelope?.payload!=='string'||typeof envelope.signature!=='string'||envelope.payload.length>60000)throw Error('Invalid update manifest');
 if(!crypto.verify(null,Buffer.from(envelope.payload),key,Buffer.from(envelope.signature,'base64')))throw Error('Update signature rejected');
 const m=JSON.parse(envelope.payload);version(m.version);
 if(m.schema!==1||m.channel!=='stable'||!Number.isSafeInteger(m.expires)||m.expires<now||!Number.isSafeInteger(m.published)||m.published>now+300000||m.expires<=m.published||m.expires-m.published>90*864e5)throw Error('Expired or invalid update manifest');
 if(!/^\d+\.\d+\.\d+$/.test(m.minNode)||!m.artifact||!Array.isArray(m.artifact.urls)||!m.artifact.urls.length||m.artifact.urls.length>3||!m.artifact.urls.every(u=>typeof u==='string')||!/^[a-f0-9]{64}$/.test(m.artifact.sha256)||!Number.isSafeInteger(m.artifact.bytes)||m.artifact.bytes<1||m.artifact.bytes>20*1024*1024)throw Error('Invalid release artifact');
 m.artifact.urls.forEach(allowed);return m;
}
async function fetchBytes(url,max){
 const response=await fetch(allowed(url),{signal:AbortSignal.timeout(8000),headers:{'User-Agent':'multi-claude-updater/1'}});
 if(!response.ok||new URL(response.url).protocol!=='https:')throw Error('Update HTTP '+response.status);
 const chunks=[];let size=0;for await(const part of response.body){size+=part.length;if(size>max)throw Error('Update download too large');chunks.push(part);}return Buffer.concat(chunks);
}
function methods(platform=process.platform){return platform==='win32'?['node','curl','powershell']:['node','curl'];}
async function download(url,max,options={}){
 const failures=[];for(const method of methods(options.platform)){
  try{
   if(options.transport)return await options.transport(method,url,max);
   if(method==='node')return await fetchBytes(url,max);
   allowed(url);const command=method==='curl'?(process.platform==='win32'?'curl.exe':'curl'):'powershell.exe';
   const args=method==='curl'?['--fail','--silent','--show-error','--location','--proto','=https','--proto-redir','=https','--max-time','12','--max-filesize',String(max),url]:['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'download.ps1'),'-Url',url,'-MaxBytes',String(max)];
   const r=spawnSync(command,args,{timeout:15000,maxBuffer:max,windowsHide:true});if(r.error||r.status!==0)throw Error('Transport failed');if(r.stdout.length>max)throw Error('Download too large');return r.stdout;
  }catch(e){failures.push(method+': '+e.message);}
 }throw Error('Update download unavailable ('+failures.join('; ')+')');
}
function validateInstall(root,expected){
 const pkg=read(path.join(root,'package.json'));if(pkg.name!=='@ghackk/multi-claude'||pkg.version!==expected)throw Error('Release metadata mismatch');
 for(const name of ['bin/claude-multi.js','claude-menu.ps1','unix/claude-menu.sh','usage/report.js','updater/update.js'])if(!fs.statSync(path.join(root,name)).isFile())throw Error('Incomplete release');
 const r=spawnSync(process.execPath,['--check',path.join(root,'bin/claude-multi.js')],{timeout:10000,windowsHide:true});if(r.status!==0)throw Error('Release entry point is invalid');
}
function current(root=ROOT,base=BASE){
 const installed=read(path.join(root,'package.json')).version,state=read(path.join(base,'state.json'));
 for(const candidate of [state.current,state.previous])try{if(candidate&&newer(candidate,installed)){const dest=path.join(base,'versions',candidate);validateInstall(dest,candidate);return dest;}}catch{}
 return root;
}
function source(root,platform=process.platform){const p=root.replace(/\\/g,'/').toLowerCase();if(p.includes('/node_modules/'))return 'npm';if(p.includes('/cellar/')||p.includes('/homebrew/'))return 'homebrew';if(p.includes('/scoop/apps/'))return 'scoop';if(fs.existsSync(path.join(root,'.git')))return 'git/pip';return 'archive';}
async function check(options={}){
 const root=options.root||ROOT,base=options.base||BASE,key=options.key||fs.readFileSync(path.join(__dirname,'public-key.pem'));
 fs.mkdirSync(base,{recursive:true,mode:0o700});let lock;
 const lockFile=path.join(base,'update.lock');
 try{lock=fs.openSync(lockFile,'wx',0o600);fs.writeFileSync(lock,String(process.pid));}catch(e){
  if(e.code!=='EEXIST')throw e;
  let pid;try{pid=Number(fs.readFileSync(lockFile,'utf8'));if(!Number.isSafeInteger(pid)||pid<=0)throw Error();process.kill(pid,0);return {status:'busy'};}catch(err){if(err.code==='EPERM')return {status:'busy'};}
  if(Date.now()-fs.statSync(lockFile).mtimeMs<60000)return {status:'busy'};
  fs.unlinkSync(lockFile);return check(options);
 }
 const stateFile=path.join(base,'state.json'),state=read(stateFile);let stage;
 try{
  let manifest,manifestError;
  for(const url of [MANIFEST,MIRROR])try{manifest=verify(JSON.parse((await (options.download||download)(url,65536)).toString()),key);break;}catch(e){manifestError=e;}
  if(!manifest)throw manifestError;
  const active=read(path.join(current(root,base),'package.json')).version;
  if(!newer(manifest.version,active)||state.highest&&newer(state.highest,manifest.version)){atomic(stateFile,{...state,checked:Date.now(),status:'current'});return {status:'current',version:active};}
  if(newer(manifest.minNode,process.versions.node))throw Error('Newer Node.js is required; current installation retained');
  let bytes,last;
  for(const url of manifest.artifact.urls){try{const b=await(options.download||download)(url,manifest.artifact.bytes);if(b.length!==manifest.artifact.bytes||crypto.createHash('sha256').update(b).digest('hex')!==manifest.artifact.sha256)throw Error('Release checksum mismatch');bytes=b;break;}catch(e){last=e;}}
  if(!bytes)throw last;
  const versions=path.join(base,'versions');fs.mkdirSync(versions,{recursive:true});stage=fs.mkdtempSync(path.join(versions,'.staging-'));extract(bytes,stage);validateInstall(stage,manifest.version);
  fs.writeFileSync(path.join(stage,'.verified-update.json'),JSON.stringify({version:manifest.version,sha256:manifest.artifact.sha256}));
  const target=path.join(versions,manifest.version);
  if(fs.existsSync(target)){
   let intact=false;try{validateInstall(target,manifest.version);intact=read(path.join(target,'.verified-update.json')).sha256===manifest.artifact.sha256;}catch{}
   if(!intact){const quarantine=path.join(versions,'.replaced-'+manifest.version+'-'+crypto.randomUUID());fs.renameSync(target,quarantine);try{fs.renameSync(stage,target);stage=null;}catch(e){fs.renameSync(quarantine,target);throw e;}}
  }else{fs.renameSync(stage,target);stage=null;}
  atomic(stateFile,{...state,previous:state.current||null,current:manifest.version,highest:manifest.version,checked:Date.now(),status:'updated'});
  return {status:'updated',version:manifest.version};
 }catch(e){atomic(stateFile,{...state,checked:Date.now(),status:'failed',error:e.message});return {status:'failed',error:e.message};}
 finally{if(stage){const resolved=path.resolve(stage),parent=path.resolve(base,'versions')+path.sep;if(!resolved.startsWith(parent)||!path.basename(resolved).startsWith('.staging-'))throw Error('Invalid cleanup target');fs.rmSync(resolved,{recursive:true,force:true});}if(lock!==undefined)fs.closeSync(lock);try{fs.unlinkSync(lockFile);}catch{}}
}
function start(root=ROOT,base=BASE){
 if(process.env.MULTI_CLAUDE_AUTO_UPDATE==='0'||process.env.MULTI_CLAUDE_LIBRARY_ONLY==='1'||process.env.MULTI_CLAUDE_UPDATE_BOOTSTRAPPED==='1')return;
 try{const state=read(path.join(base,'state.json'));if(state.status==='failed'&&Date.now()-state.checked<15*60*1000)return;const p=spawn(process.execPath,[path.join(__dirname,'update.js'),'worker',root,base],{detached:true,stdio:'ignore',windowsHide:true});p.on('error',()=>{});p.unref();}catch{}
}
async function cli(){const command=process.argv[2],root=process.argv[3]||ROOT,base=process.argv[4]||BASE;
 if(command==='worker'){await check({root,base});return;}
 if(command==='check'){const r=await check({root,base});console.log(JSON.stringify(r));if(r.status==='failed')process.exitCode=1;return;}
 if(command==='status'){console.log(JSON.stringify({installed:read(path.join(root,'package.json')).version,running:read(path.join(current(root,base),'package.json')).version,source:source(root),...read(path.join(base,'state.json'))},null,2));return;}
 if(command==='resolve'){start(root,base);console.log(current(root,base));return;}
 throw Error('Unknown updater command');
}
if(require.main===module)cli().catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports={verify,newer,allowed,methods,download,check,current,start,source,validateInstall};
