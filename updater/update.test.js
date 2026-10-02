'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),path=require('path'),os=require('os'),crypto=require('crypto'),zlib=require('zlib');
const U=require('./update'),{extract}=require('./archive');
const keys=crypto.generateKeyPairSync('ed25519');
function fixture(){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'multi-update-test-')),root=path.join(dir,'original'),base=path.join(dir,'updates');fs.mkdirSync(root);fs.writeFileSync(path.join(root,'package.json'),JSON.stringify({version:'1.0.29'}));fs.writeFileSync(path.join(dir,'account-history'),'KEEP');return {dir,root,base,key:keys.publicKey};}
function cleanup(dir){assert(path.resolve(dir).startsWith(path.resolve(os.tmpdir())+path.sep));assert(path.basename(dir).startsWith('multi-update-test-'));fs.rmSync(dir,{recursive:true,force:true});}
function archive(entries){const blocks=[];for(const [name,content,type='0'] of entries){const body=Buffer.from(content),h=Buffer.alloc(512);h.write(name);h.write('0000644\0',100);h.write(body.length.toString(8).padStart(11,'0')+'\0',124);h.fill(32,148,156);h.write(type,156);h.write([...h].reduce((a,b)=>a+b,0).toString(8).padStart(6,'0')+'\0 ',148);blocks.push(h,body,Buffer.alloc((512-body.length%512)%512));}return zlib.gzipSync(Buffer.concat([...blocks,Buffer.alloc(1024)]));}
function release(v='1.0.30'){return archive([['package/package.json',JSON.stringify({name:'@ghackk/multi-claude',version:v})],...['bin/claude-multi.js','claude-menu.ps1','unix/claude-menu.sh','usage/report.js','updater/update.js'].map(f=>['package/'+f,''])]);}
function manifest(bytes,changes={}){const payload=JSON.stringify({schema:1,channel:'stable',version:'1.0.30',minNode:'22.13.0',published:Date.now()-1000,expires:Date.now()+864e5,artifact:{bytes:bytes.length,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),urls:['https://pair.ghackk.com/updates/v1.0.30/package.tgz','https://github.com/ghackk/claude-multi-account/releases/download/v1.0.30/package.tgz']},...changes});return Buffer.from(JSON.stringify({payload,signature:crypto.sign(null,Buffer.from(payload),keys.privateKey).toString('base64')}));}
test('server offline: signed GitHub manifest and package fallback install; profiles stay untouched',async()=>{
 const f=fixture(),bytes=release(),signed=manifest(bytes),seen=[];try{
 const result=await U.check({...f,download:async url=>{seen.push(url);if(url.includes('pair.ghackk.com'))throw Error('server offline');return url.endsWith('.json')?signed:bytes;}});
 assert.equal(result.status,'updated');assert.equal(result.version,'1.0.30');assert.equal(U.current(f.root,f.base),path.join(f.base,'versions','1.0.30'));assert(seen.length===4);assert.equal(fs.readFileSync(path.join(f.dir,'account-history'),'utf8'),'KEEP');
 const offline=await U.check({...f,download:async()=>{throw Error('offline');}});assert.equal(offline.status,'failed');assert.equal(U.current(f.root,f.base),path.join(f.base,'versions','1.0.30'));
 }finally{cleanup(f.dir);}
});
test('bad signature, tampering, expired metadata, untrusted URLs, and future runtime leave original usable',async()=>{
 for(const kind of ['signature','checksum','expired','host','runtime']){const f=fixture(),bytes=release();try{
 let signed=manifest(bytes,kind==='expired'?{expires:Date.now()-1}:kind==='runtime'?{minNode:'999.0.0'}:{});
 if(kind==='signature'){const e=JSON.parse(signed);e.payload+=' ';signed=Buffer.from(JSON.stringify(e));}
 if(kind==='host'){const m=JSON.parse(JSON.parse(signed).payload);m.artifact.urls=['https://evil.invalid/file'];signed=manifest(bytes,m);}
 const r=await U.check({...f,download:async url=>url.endsWith('.json')?signed:kind==='checksum'?Buffer.from('corrupt'):bytes});assert.equal(r.status,'failed',kind);assert.equal(U.current(f.root,f.base),f.root,kind);
 }finally{cleanup(f.dir);}}
});
test('archive rejects traversal, absolute paths, links and Windows device paths',()=>{
 for(const [name,type] of [['package/../escape','0'],['/escape','0'],['package/link','2'],['package/C:/escape','0'],['package/CON','0']]){const f=fixture();try{assert.throws(()=>extract(archive([[name,'x',type]]),path.join(f.dir,'stage')));}finally{cleanup(f.dir);}}
});
test('partial release does not switch active version; no downgrade; concurrent updater stays out',async()=>{
 const f=fixture();try{
 let bytes=archive([['package/package.json','{}']]),signed=manifest(bytes);assert.equal((await U.check({...f,download:async u=>u.endsWith('.json')?signed:bytes})).status,'failed');assert.equal(U.current(f.root,f.base),f.root);
 bytes=release('1.0.28');signed=manifest(bytes,{version:'1.0.28'});assert.equal((await U.check({...f,download:async()=>signed})).status,'current');
 fs.writeFileSync(path.join(f.base,'update.lock'),String(process.pid));assert.equal((await U.check({...f,download:async()=>{throw Error('must not fetch');}})).status,'busy');
 }finally{cleanup(f.dir);}
});
test('download tools fall back per OS; repeated failures stay bounded',async()=>{
 assert.deepEqual(U.methods('darwin'),['node','curl']);assert.deepEqual(U.methods('linux'),['node','curl']);assert.deepEqual(U.methods('win32'),['node','curl','powershell']);
 const used=[];const b=await U.download('https://pair.ghackk.com/updates/stable.json',100,{platform:'win32',transport:async method=>{used.push(method);if(method!=='powershell')throw Error('unavailable');return Buffer.from('ok');}});assert.equal(b.toString(),'ok');assert.equal(used.length,3);
 await assert.rejects(()=>U.download('https://pair.ghackk.com/updates/stable.json',100,{platform:'linux',transport:async()=>{throw Error('offline');}}));
});
test('corrupt cached release falls back to previous verified installation',async()=>{
 const f=fixture();try{const bytes=release(),signed=manifest(bytes);await U.check({...f,download:async u=>u.endsWith('.json')?signed:bytes});const state=JSON.parse(fs.readFileSync(path.join(f.base,'state.json')));fs.writeFileSync(path.join(f.base,'state.json'),JSON.stringify({...state,current:'1.0.31',previous:'1.0.30'}));assert.equal(U.current(f.root,f.base),path.join(f.base,'versions','1.0.30'));}finally{cleanup(f.dir);}
});
test('damaged cache is repaired from a verified archive without losing the base install',async()=>{
 const f=fixture();try{const bytes=release(),signed=manifest(bytes),download=async u=>u.endsWith('.json')?signed:bytes;await U.check({...f,download});fs.unlinkSync(path.join(f.base,'versions','1.0.30','bin','claude-multi.js'));assert.equal(U.current(f.root,f.base),f.root);assert.equal((await U.check({...f,download})).status,'updated');assert.equal(U.current(f.root,f.base),path.join(f.base,'versions','1.0.30'));assert(fs.existsSync(path.join(f.root,'package.json')));}finally{cleanup(f.dir);}
});
