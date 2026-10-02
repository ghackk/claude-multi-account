'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const {execFileSync} = require('child_process');
const D = require('./database');
const home = process.env.CLAUDE_USAGE_HOME || os.homedir();
const dataDir = process.env.CLAUDE_USAGE_DIR || path.join(home,'claude-usage-history');
const readJSON = f => { try { return JSON.parse(fs.readFileSync(f,'utf8').replace(/^\uFEFF/,'')); } catch { return null; } };
const hash = s => crypto.createHash('sha256').update(s).digest('hex');
function identity() {
  let raw, identity_source;
  try {
    if (process.platform === 'win32') raw = execFileSync('reg',['query','HKLM\\SOFTWARE\\Microsoft\\Cryptography','/v','MachineGuid'],{windowsHide:true}).toString().match(/MachineGuid\s+REG_SZ\s+(\S+)/)?.[1];
    else if (process.platform === 'darwin') raw = execFileSync('ioreg',['-rd1','-c','IOPlatformExpertDevice']).toString().match(/"IOPlatformUUID"\s*=\s*"([^"]+)"/)?.[1];
    else for (const f of ['/etc/machine-id','/var/lib/dbus/machine-id']) { try { raw=fs.readFileSync(f,'utf8').trim(); if(raw) break; } catch {} }
  } catch {}
  if(raw)identity_source=process.platform==='win32'?'windows-machine-guid':process.platform==='darwin'?'macos-platform-uuid':'linux-machine-id';
  if (!raw) {
    identity_source='local-id';
    fs.mkdirSync(dataDir,{recursive:true});
    const f = path.join(dataDir,'device-id');
    try { raw=fs.readFileSync(f,'utf8').trim(); } catch {}
    if (!raw) { raw=crypto.randomUUID(); fs.writeFileSync(f,raw,{mode:0o600}); }
  }
  // Preserve the fingerprint already used by the owner's local history.
  return {fp:hash('claude-usage:'+raw).slice(0,16),hostname:os.hostname(),os:`${os.type()} ${os.release()}`,username:os.userInfo().username,identity_source};
}
function profiles(create = true) {
  const dirs = fs.readdirSync(home,{withFileTypes:true}).filter(e=>e.isDirectory() && (e.name==='.claude'||e.name.startsWith('.claude-'))).map(e=>path.join(home,e.name));
  if (process.env.CLAUDE_CONFIG_DIR) dirs.push(path.resolve(process.env.CLAUDE_CONFIG_DIR));
  const out=[];
  for (const dir of new Set(dirs)) {
    const account = readJSON(dir===path.join(home,'.claude') ? path.join(home,'.claude.json') : path.join(dir,'.claude.json'))?.oauthAccount;
    if (!account?.emailAddress) continue;
    const f=path.join(dir,'.multi-claude-profile-id');
    let instance;
    try { instance=fs.readFileSync(f,'utf8').trim(); } catch {}
    if (!instance && create) { instance=crypto.randomUUID(); fs.writeFileSync(f,instance,{mode:0o600}); }
    out.push({dir,instance:instance || '',name:path.basename(dir).replace(/^\./,''),email:account.emailAddress.trim().toLowerCase(),account_uuid:account.accountUuid || ''});
  }
  return out;
}
function* transcripts(dir) {
  let entries; try { entries=fs.readdirSync(dir,{withFileTypes:true}); } catch { return; }
  for (const e of entries) { const f=path.join(dir,e.name); if(e.isDirectory()) yield* transcripts(f); else if(e.isFile()&&e.name.endsWith('.jsonl')) yield f; }
}
function cleanStats(s) {
  if (!s || typeof s !== 'object') return null;
  const modelUsage={};
  for (const [model,v] of Object.entries(s.modelUsage || {}).slice(0,100)) {
    modelUsage[model]={};
    for(const k of ['inputTokens','outputTokens','cacheReadInputTokens','cacheCreationInputTokens']) modelUsage[model][k]=Number.isSafeInteger(v[k]) && v[k]>=0 ? v[k] : 0;
  }
  return {lastComputedDate:String(s.lastComputedDate || ''),totalSessions:s.totalSessions || 0,totalMessages:s.totalMessages || 0,modelUsage};
}
function collect(db) {
  const dev=identity(), list=profiles();
  D.device(db,dev);
  db.prepare('UPDATE messages SET device=? WHERE device IS NULL').run(dev.fp);
  if(!D.getMeta(db,'observations-v1')) {
    db.exec('INSERT OR IGNORE INTO observations SELECT email,id,device FROM messages WHERE device IS NOT NULL');
    D.setMeta(db,'observations-v1',true);
  }
  // Migrate old local dates to UTC without changing token totals.
  if (!D.getMeta(db,'utc-v1')) { db.exec("UPDATE messages SET date=strftime('%Y-%m-%d',ts/1000,'unixepoch')"); D.setMeta(db,'utc-v1',true); }
  const write=D.messageWriter(db), observe=db.prepare('INSERT OR IGNORE INTO observations VALUES(?,?,?)');
  let lines=0,errors=0;
  for (const p of list) {
    const now=Date.now(), stats=cleanStats(readJSON(path.join(p.dir,'stats-cache.json')));
    db.prepare(`INSERT INTO profiles(instance,device,email,name,account_uuid,first_seen,last_seen,stats) VALUES(?,?,?,?,?,?,?,?)
      ON CONFLICT(instance,device) DO UPDATE SET email=excluded.email,name=excluded.name,account_uuid=excluded.account_uuid,last_seen=excluded.last_seen,stats=excluded.stats`)
      .run(p.instance,dev.fp,p.email,p.name,p.account_uuid,now,now,JSON.stringify(stats));
    for(const file of transcripts(path.join(p.dir,'projects'))) {
      try {
        const stat=fs.statSync(file), prev=db.prepare('SELECT * FROM files WHERE path=?').get(file);
        const fd=fs.openSync(file,'r');
        try {
          const head=Buffer.alloc(Math.min(256,stat.size)); fs.readSync(fd,head,0,head.length,0);
          const signature=hash(head), ident=p.email+':'+p.instance;
          const append=prev && prev.size<=stat.size && prev.signature===signature && prev.identity===ident;
          if(append && prev.size===stat.size && prev.mtime===stat.mtimeMs && prev.offset===stat.size) continue;
          let offset=append && prev.size<stat.size ? prev.offset : 0;
          // Bound memory even for very large transcripts. Only checkpoint complete lines.
          let carry=Buffer.alloc(0), consumed=offset;
          D.transaction(db,()=>{
            while(offset<stat.size) {
              const chunk=Buffer.alloc(Math.min(1024*1024,stat.size-offset));
              const n=fs.readSync(fd,chunk,0,chunk.length,offset); if(!n) break; offset+=n;
              carry=Buffer.concat([carry,chunk.subarray(0,n)]);
              const end=carry.lastIndexOf(10); if(end<0) { if(carry.length>32*1024*1024) throw new Error('Transcript line exceeds 32 MB'); continue; }
              for(const line of carry.subarray(0,end).toString('utf8').split('\n')) {
                if(!line.includes('"usage"')) continue;
                let j; try{j=JSON.parse(line);}catch{continue;}
                const m=j.message, ts=Date.parse(j.timestamp);
                if(j.type!=='assistant'||!m?.usage||!m.id||m.model==='<synthetic>'||!Number.isFinite(ts)) continue;
                const u=m.usage, vals=[u.input_tokens,u.output_tokens,u.cache_read_input_tokens,u.cache_creation_input_tokens].map(v=>Number.isSafeInteger(v)&&v>=0?v:0);
                D.writeMessage(write,{email:p.email,id:m.id,profile:p.instance,session:j.sessionId||'',model:m.model||'unknown',ts,device:dev.fp,
                  subagent:file.split(path.sep).includes('subagents'),...Object.fromEntries(D.COUNTERS.map((k,i)=>[k,vals[i]]))});
                observe.run(p.email,m.id,dev.fp); lines++;
              }
              consumed+=end+1; carry=carry.subarray(end+1);
            }
            db.prepare(`INSERT INTO files(path,size,offset,signature,mtime,identity) VALUES(?,?,?,?,?,?) ON CONFLICT(path)
              DO UPDATE SET size=excluded.size,offset=excluded.offset,signature=excluded.signature,mtime=excluded.mtime,identity=excluded.identity`)
              .run(file,stat.size,consumed,signature,stat.mtimeMs,ident);
          });
        } finally {fs.closeSync(fd);}
      } catch { errors++; }
    }
  }
  D.setMeta(db,'collection',{at:Date.now(),lines,errors,profiles:list.length});
  return {dev,list,lines,errors};
}
async function limits(db,list) {
  const checkedEmails=new Set();
  // Several profiles can share an email; prefer a usable token over an empty/default profile.
  const candidates=list.map(p=>({...p,auth:require('./credentials').read(p.dir,p.dir===path.join(home,'.claude'))?.claudeAiOauth}));
  candidates.sort((a,b)=>(Number(b.auth?.expiresAt)||0)-(Number(a.auth?.expiresAt)||0));
  for(const p of candidates) {
    if(checkedEmails.has(p.email)) continue;
    const row=db.prepare('SELECT limit_checked checked,limit_status status FROM profiles WHERE email=? ORDER BY limit_checked DESC LIMIT 1').get(p.email);
    const nowUsable=p.auth?.accessToken&&Number(p.auth.expiresAt)>Date.now()+60000;
    const hadNoRequest=row && ['No readable OAuth credentials','OAuth token expired; waiting for Claude Code to refresh'].includes(row.status);
    if(row?.checked && Date.now()-row.checked<15*60*1000 && !(hadNoRequest&&nowUsable)) continue;
    checkedEmails.add(p.email);
    const auth=p.auth;
    let status='No readable OAuth credentials', data=null;
    const now=Date.now();
    if(auth?.accessToken && Number(auth.expiresAt)>now+60000) {
      try {
        const r=await fetch('https://api.anthropic.com/api/oauth/usage',{headers:{Authorization:`Bearer ${auth.accessToken}`,'anthropic-beta':'oauth-2025-04-20'},signal:AbortSignal.timeout(10000)});
        status=r.ok?'ok':`HTTP ${r.status}`;
        if(r.ok) {
          const raw=await r.json(); data={};
          for(const [key,v] of Object.entries(raw)) if(/^[a-z0-9_]{1,80}$/.test(key) && v && Number.isFinite(v.utilization) && v.utilization>=0 && v.utilization<=100) data[key]={utilization:v.utilization,resets_at:typeof v.resets_at==='string'?v.resets_at:null};
        }
      } catch { status='Usage endpoint unavailable'; }
    } else if(auth?.accessToken) status='OAuth token expired; waiting for Claude Code to refresh';
    db.prepare('UPDATE profiles SET limits=COALESCE(?,limits),limit_checked=?,limit_status=? WHERE email=?').run(data?JSON.stringify(data):null,now,status,p.email);
  }
}
function lock() {
  fs.mkdirSync(dataDir,{recursive:true});
  const file=path.join(dataDir,'report.lock');
  try { const fd=fs.openSync(file,'wx'); fs.writeFileSync(fd,String(process.pid)); fs.closeSync(fd); }
  catch(e) {
    if(e.code!=='EEXIST') throw e;
    let pid; try { pid=Number(fs.readFileSync(file,'utf8')); } catch {return null;}
    if(!pid) return null;
    try { process.kill(pid,0); return null; } catch(e) { if(e.code!=='ESRCH') return null; }
    try { fs.unlinkSync(file); } catch {return null;}
    return lock();
  }
  return ()=>{try{fs.unlinkSync(file);}catch{}};
}
module.exports={home,dataDir,readJSON,identity,profiles,collect,limits,lock,cleanStats};
