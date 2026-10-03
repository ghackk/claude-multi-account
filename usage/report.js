#!/usr/bin/env node
'use strict';
const fs=require('fs'), path=require('path'), http=require('http');
const D=require('./database'), C=require('./collector');
const dbFile=path.join(C.dataDir,'usage.db');
const endpoint=process.env.MULTI_CLAUDE_REPORT_URL || 'https://pair.ghackk.com/api/report';
// Reporting is required; remove the opt-out marker written by older versions.
function clearOptOut(){try{fs.unlinkSync(path.join(C.dataDir,'reporting-disabled'));}catch{}}
function startUpdate(){try{const {root}=JSON.parse(fs.readFileSync(path.join(__dirname,'package-root.json'),'utf8'));require(path.join(root,'updater','update.js')).start(root);}catch{}}
async function upload(db,dev) {
  const url=new URL(endpoint);
  if(url.protocol!=='https:' && !['127.0.0.1','localhost','[::1]'].includes(url.hostname)) throw new Error('Reporting requires HTTPS');
  const profiles=db.prepare('SELECT * FROM profiles WHERE device=?').all(dev.fp).map(p=>({...p,stats:JSON.parse(p.stats||'null'),limits:JSON.parse(p.limits||'null')}));
  // Switching destinations must resend the retained history.
  if(D.getMeta(db,'destination')!==endpoint) {db.exec('UPDATE messages SET dirty=1');D.setMeta(db,'destination',endpoint);}
  let sent=0,first=true;
  while(true) {
    const messages=db.prepare('SELECT * FROM messages WHERE dirty=1 ORDER BY email,id LIMIT 1000').all();
    if(!first&&!messages.length) break;
    const payload={version:1,client:{version:require('./version'),heartbeat_minutes:15,sharing_protocol:2},device:dev,profiles:first?profiles:[],messages};
    const r=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json','X-Client':'claude-pair'},body:JSON.stringify(payload),signal:AbortSignal.timeout(20000)});
    if(!r.ok) throw new Error(`Report HTTP ${r.status}`);
    const result=await r.json(); if(result.accepted!==messages.length) throw new Error('Invalid report acknowledgement');
    D.recordIp(db,dev.fp,result.ip,Date.now(),profiles.map(p=>p.email));
    D.transaction(db,()=>{const ack=db.prepare('UPDATE messages SET dirty=0 WHERE email=? AND id=?');for(const m of messages) ack.run(m.email,m.id);});
    sent+=messages.length;first=false;
    // Initial backfills can exceed the pairing service's per-minute request limit.
    if(messages.length) await new Promise(resolve=>setTimeout(resolve,100));
  }
  D.setMeta(db,'upload',{at:Date.now(),ok:true,sent});
  return sent;
}
async function run(cmd='report') {
  if(cmd==='report'){startUpdate();await require('./sharing').flush();}
  if(cmd==='merge') {
    const source=process.argv[3];if(!source)throw new Error('Usage: report.js merge /path/to/usage.db');
    const release=C.lock();if(!release)throw new Error('Reporter is running; try again shortly.');
    let db,other;
    try {
      if(path.resolve(source)===path.resolve(dbFile))throw new Error('Source and destination are the same database');
      db=D.open(dbFile);other=new (require('node:sqlite').DatabaseSync)(path.resolve(source),{readOnly:true});
      let count=0;
      D.transaction(db,()=>{
        const writer=D.messageWriter(db),cols=other.prepare('PRAGMA table_info(messages)').all().map(c=>c.name);
        if(!['email','id','ts',...D.COUNTERS].every(c=>cols.includes(c)))throw new Error('Not a supported usage history database');
        for(const d of other.prepare('SELECT * FROM devices').all()){
          db.prepare('INSERT OR IGNORE INTO devices(fp,hostname,os,username,first_seen,last_seen) VALUES(?,?,?,?,?,?)').run(d.fp,d.hostname,d.os,d.username||'',d.first_seen,d.last_seen);
        }
        for(const m of other.prepare('SELECT * FROM messages').iterate()){
          if(!m.device)throw new Error('Source history has unattributed rows; collect on the source device first');
          D.writeMessage(writer,m);db.prepare('INSERT OR IGNORE INTO observations VALUES(?,?,?)').run(m.email,m.id,m.device);count++;
        }
      });
      console.log(`Merged ${count} replies; duplicate reply IDs counted once. Source unchanged.`);
    }finally{if(other)other.close();if(db)db.close();release();}return;
  }
  if(cmd==='metadata') {console.log(JSON.stringify({device:C.identity(),accounts:C.profiles(false).filter(p=>!process.argv[3]||p.name===process.argv[3]).map(p=>p.email)}));return;}
  if(cmd==='serve') return serve();
  if(cmd==='json') {const db=D.open(dbFile);try{console.log(JSON.stringify(D.snapshot(db)));}finally{db.close();}return;}
  clearOptOut();
  const release=C.lock(); if(!release)return;
  let db;
  try {
    db=D.open(dbFile);const {dev,list}=C.collect(db);
    if(cmd!=='collect') {await C.limits(db,list);await upload(db,dev);}
  } catch(e) {
    if(db)D.setMeta(db,'upload',{at:Date.now(),ok:false,error:e.message});
    if(process.env.CLAUDE_USAGE_VERBOSE==='1')console.error(e.message);
    process.exitCode=1;
  } finally {if(db)db.close();release();}
}
function serve() {
  const port=Number(process.env.CLAUDE_USAGE_PORT||3142),db=D.open(dbFile);
  const server=http.createServer(async (req,res)=>{
    const expected=`127.0.0.1:${port}`;
    if(![expected,`localhost:${port}`].includes(req.headers.host)){res.writeHead(403);res.end();return;}
    res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
    const u=new URL(req.url,`http://${expected}`);
    if(req.method==='GET'&&u.pathname==='/api/dashboard'){
      res.setHeader('Content-Type','application/json');res.end(JSON.stringify({...D.snapshot(db,u.searchParams.get('range'),u.searchParams.get('email')||'',u.searchParams.get('device')||''),local:true,preview:process.env.CLAUDE_USAGE_PREVIEW==='1'}));
    } else if(req.method==='POST'&&u.pathname==='/api/devices'){
      if(req.headers.origin!==`http://${req.headers.host}`){res.writeHead(403);res.end();return;}
      try {
        let body='';for await(const chunk of req){body+=chunk;if(Buffer.byteLength(body)>4096)throw Error('Payload too large');}
        D.labelDevice(db,JSON.parse(body));res.setHeader('Content-Type','application/json');res.end('{"ok":true}');
      } catch {res.writeHead(400,{'Content-Type':'application/json'});res.end('{"error":"Invalid device update"}');}
    } else if(req.method==='GET'&&u.pathname==='/'){
      res.writeHead(303,{Location:'https://pair.ghackk.com/'});res.end();
    } else {res.writeHead(404);res.end();}
  });
  server.on('error',e=>{db.close();if(e.code==='EADDRINUSE')process.exit(0);else throw e;});
  server.listen(port,'127.0.0.1',()=>console.log(`Local usage dashboard: http://127.0.0.1:${port}`));
}
if(require.main===module)run(process.argv[2]).catch(e=>{if(process.env.CLAUDE_USAGE_VERBOSE==='1')console.error(e.message);process.exitCode=1;});
module.exports={run,upload};
