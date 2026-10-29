'use strict';
// Session mesh: every account's sessions/ folder points at one shared folder, so Claude Code's own
// peer discovery (ListAgents / SendMessage) sees live sessions of every account. Also lists, reads
// and spawns sessions across accounts. Claude Code keeps one <pid>.json + <pid>.<hash>.key per live
// session in <config>/sessions; pids are unique, so one shared folder holds every account safely.
const fs=require('fs'),path=require('path'),os=require('os'),readline=require('readline');
const {spawn,spawnSync}=require('child_process');

const home=()=>process.env.MULTI_CLAUDE_HOME||os.homedir();
const accountsDir=()=>path.join(home(),'claude-accounts');
const sharedDir=()=>path.join(home(),'claude-shared','sessions');
const sharedClaude=()=>path.join(home(),'claude-shared','CLAUDE.md');
const windows=process.platform==='win32';

// Same account list as the menus: the default ~/.claude plus every claude-<name> launcher.
function accounts(){
  const out=[];
  if(fs.existsSync(path.join(home(),'.claude'))) out.push({name:'claude',dir:path.join(home(),'.claude')});
  let files=[];try{files=fs.readdirSync(accountsDir());}catch{}
  for(const f of files){
    const m=/^(claude-[A-Za-z0-9_-]+)\.(bat|sh)$/.exec(f);
    if(!m||m[1]==='claude-menu'||m[1]==='claude-usage-report'||out.some(a=>a.name===m[1])) continue;
    out.push({name:m[1],dir:path.join(home(),'.'+m[1])});
  }
  return out;
}
function findAccount(name){
  const all=accounts(),want=String(name||'').toLowerCase();
  return all.find(a=>a.name===want)||all.find(a=>a.name==='claude-'+want)||null;
}

function isLink(p){try{return fs.lstatSync(p).isSymbolicLink();}catch{return false;}}
function real(p){try{return fs.realpathSync(p);}catch{return null;}}
function sameDir(a,b){const ra=real(a),rb=real(b);return !!ra&&!!rb&&(windows?ra.toLowerCase()===rb.toLowerCase():ra===rb);}
function moveEntries(from,to){
  let names=[];try{names=fs.readdirSync(from);}catch{return;}
  for(const n of names){
    const src=path.join(from,n),dst=path.join(to,n);
    try{
      if(!fs.statSync(src).isFile()) continue;
      if(!fs.existsSync(dst)||fs.statSync(src).mtimeMs>fs.statSync(dst).mtimeMs) fs.copyFileSync(src,dst);
    }catch{}
  }
}
function makeLink(target,at){fs.symlinkSync(target,at,windows?'junction':'dir');}

// Idempotent; safe to run on every start. Existing accounts and their already-running sessions join
// too: current entries are moved in, and live sessions keep rewriting theirs through the link.
// Returns one line per account that changed or failed.
function link(){
  const shared=sharedDir(),report=[];
  fs.mkdirSync(shared,{recursive:true});
  for(const a of accounts()){
    const s=path.join(a.dir,'sessions');
    try{
      if(isLink(s)){
        if(sameDir(s,shared)) continue;
        const old=real(s);if(old) moveEntries(old,shared);
        fs.rmSync(s,{force:true});
      }else if(fs.existsSync(s)){
        moveEntries(s,shared);
        fs.rmSync(s,{recursive:true,force:true});
      }else fs.mkdirSync(a.dir,{recursive:true});
      makeLink(shared,s);report.push(`${a.name}: linked`);
    }catch(e){report.push(`${a.name}: not linked (${e.code||e.message})`);}
  }
  ensureInstructions();
  report.push(...installTools());
  report.push(...shareMemory());
  return report;
}

// Project memory (<config>/projects/<key>/memory) is per account by default, so a session on another
// account knows none of the notes. Every project's memory moves to ~/claude-shared/memory/<key> and
// every account links to it, including accounts that never opened that project. The first merge keeps
// the newest copy of each file, unions MEMORY.md index lines, backs every original up, and parks the
// losing versions of conflicting files in claude-shared/memory-conflicts.
const memoryRoot=()=>path.join(home(),'claude-shared','memory');
const projectKey=k=>windows?k.toLowerCase():k;
function memoryDirs(){
  const byKey=new Map();
  for(const a of accounts()){
    const projects=path.join(a.dir,'projects');let keys=[];try{keys=fs.readdirSync(projects);}catch{continue;}
    for(const k of keys){
      const m=path.join(projects,k,'memory');
      if(!isLink(m)){let n=0;try{n=fs.readdirSync(m).length;}catch{}if(!n) continue;}
      const id=projectKey(k);
      if(!byKey.has(id)) byKey.set(id,{key:k,dirs:[]});
      byKey.get(id).dirs.push({account:a.name,dir:m});
    }
  }
  return byKey;
}
function mergeIndex(texts){
  // Newest first; keep its lines, then add lines from the others that point at a file not yet listed.
  const out=[],seen=new Set();
  const target=l=>{const m=/\]\(([^)]+)\)/.exec(l);return m?m[1].toLowerCase():null;};
  texts.forEach((t,i)=>{for(const l of t.replace(/\s+$/,'').split(/\r?\n/)){
    const tg=target(l);
    if(i===0){out.push(l);if(tg) seen.add(tg);continue;}
    if(tg&&!seen.has(tg)){out.push(l);seen.add(tg);}
  }});
  return out.join('\n').replace(/\n*$/,'\n');
}
// Opt-in (MULTI_CLAUDE_MESH_MEMORY=1): by default each account keeps its own notes and context is
// handed over per session with fork instead.
function shareMemory(){
  const report=[];
  if(process.env.MULTI_CLAUDE_MESH_MEMORY!=='1') return report;
  const stamp=new Date().toISOString().slice(0,10);
  for(const [id,{key,dirs}] of memoryDirs()){
    const shared=path.join(memoryRoot(),id);
    const own=dirs.filter(d=>!(isLink(d.dir)&&sameDir(d.dir,shared)));
    try{
      if(own.length){
        fs.mkdirSync(shared,{recursive:true});
        const sources=own.map(d=>({...d,real:real(d.dir)})).filter(d=>d.real&&!sameDir(d.real,shared));
        // Back up, then merge file by file (newest wins; others parked as conflicts).
        for(const s of sources) fs.cpSync(s.real,path.join(home(),'claude-shared',`memory-backup-${stamp}`,s.account,key),{recursive:true});
        const files=new Map();
        for(const s of [{account:'shared',real:shared},...sources]){
          let names=[];try{names=fs.readdirSync(s.real);}catch{}
          for(const n of names){
            const f=path.join(s.real,n);let st;try{st=fs.statSync(f);}catch{continue;}
            if(!st.isFile()) continue;
            if(!files.has(n)) files.set(n,[]);
            files.get(n).push({account:s.account,file:f,mtime:st.mtimeMs,text:fs.readFileSync(f,'utf8')});
          }
        }
        for(const [n,versions] of files){
          versions.sort((a,b)=>b.mtime-a.mtime);
          if(n==='MEMORY.md'){fs.writeFileSync(path.join(shared,n),mergeIndex(versions.map(v=>v.text)));continue;}
          const best=versions[0];
          if(best.account!=='shared') fs.copyFileSync(best.file,path.join(shared,n));
          for(const v of versions.slice(1)) if(v.text!==best.text&&v.account!=='shared'){
            const c=path.join(home(),'claude-shared','memory-conflicts',key,v.account);
            fs.mkdirSync(c,{recursive:true});fs.copyFileSync(v.file,path.join(c,n));
          }
        }
        for(const d of own){fs.rmSync(d.dir,{recursive:!isLink(d.dir),force:true});makeLink(shared,d.dir);}
        report.push(`memory ${key}: shared (${own.map(d=>d.account).join(', ')})`);
      }
      // Accounts that never opened this project get the link too, so they start with the same notes.
      for(const a of accounts()){
        if(dirs.some(d=>d.account===a.name)) continue;
        const m=path.join(a.dir,'projects',key,'memory');
        if(isLink(m)&&sameDir(m,shared)) continue;
        if(fs.existsSync(m)&&!isLink(m)){
          let n=0;try{n=fs.readdirSync(m).length;}catch{}
          if(n) continue; // has notes: merged on the next run like any other owner
          fs.rmSync(m,{recursive:true,force:true});
        }
        fs.mkdirSync(path.dirname(m),{recursive:true});
        if(isLink(m)) fs.rmSync(m,{force:true});
        makeLink(shared,m);
      }
    }catch(e){report.push(`memory ${key}: not shared (${e.code||e.message})`);}
  }
  return report;
}

// Undo shared memory: each account that owned a project's notes gets its backed-up folder back, plus
// any note written to the shared folder after the merge; accounts that only had a link get nothing.
// The shared folder is kept aside as claude-shared/memory-unshared-<date>.
function unshareMemory(){
  const report=[],root=memoryRoot();
  if(!fs.existsSync(root)) return report;
  const base=path.join(home(),'claude-shared');
  const backups=fs.readdirSync(base).filter(n=>n.startsWith('memory-backup-')).map(n=>path.join(base,n));
  const sharedAt=Math.min(...backups.map(b=>fs.statSync(b).birthtimeMs||fs.statSync(b).mtimeMs),Infinity);
  const findBackup=(account,key)=>{
    for(const b of backups){
      const dir=path.join(b,account);let names=[];try{names=fs.readdirSync(dir);}catch{continue;}
      const hit=names.find(n=>projectKey(n)===projectKey(key));if(hit) return path.join(dir,hit);
    }
    return null;
  };
  for(const a of accounts()){
    const projects=path.join(a.dir,'projects');let keys=[];try{keys=fs.readdirSync(projects);}catch{continue;}
    for(const k of keys){
      const m=path.join(projects,k,'memory');
      if(!isLink(m)) continue;
      // Compare real paths: on macOS the temp and home trees sit behind symlinks (/var -> /private/var).
      const shared=real(m),under=projectKey(path.resolve(real(root)||root)+path.sep);
      if(!shared||!projectKey(path.resolve(shared)+path.sep).startsWith(under)) continue;
      fs.rmSync(m,{force:true});
      const backup=findBackup(a.name,k);
      if(!backup){report.push(`memory ${k}: link removed from ${a.name}`);continue;}
      fs.cpSync(backup,m,{recursive:true});
      for(const n of fs.readdirSync(shared)){
        const f=path.join(shared,n);let st;try{st=fs.statSync(f);}catch{continue;}
        if(!st.isFile()||n==='MEMORY.md'||st.mtimeMs<=sharedAt+120000) continue; // only notes written after the merge
        fs.copyFileSync(f,path.join(m,n));
      }
      // Index: own lines plus later entries, only for files this account now has.
      const own=path.join(m,'MEMORY.md'),sh=path.join(shared,'MEMORY.md');
      if(fs.existsSync(own)&&fs.existsSync(sh)){
        const merged=mergeIndex([fs.readFileSync(own,'utf8'),fs.readFileSync(sh,'utf8')]).split('\n')
          .filter(l=>{const t=/\]\(([^)]+)\)/.exec(l);return !t||fs.existsSync(path.join(m,t[1]));}).join('\n');
        fs.writeFileSync(own,merged);
      }
      report.push(`memory ${k}: ${a.name} has its own notes again`);
    }
  }
  const aside=path.join(base,`memory-unshared-${new Date().toISOString().slice(0,10)}`);
  try{fs.renameSync(root,aside);}catch{}
  return report;
}

// Undo: every account gets its own real sessions/ folder back, holding a copy of the current entries.
function unlink(){
  const shared=sharedDir(),report=[];
  for(const a of accounts()){
    const s=path.join(a.dir,'sessions');
    if(!isLink(s)) continue;
    try{fs.rmSync(s,{force:true});fs.mkdirSync(s);moveEntries(shared,s);report.push(`${a.name}: own folder again`);}
    catch(e){report.push(`${a.name}: failed (${e.code||e.message})`);}
  }
  report.push(...unshareMemory());
  removeInstructions();
  return report;
}

// Handoff: the light alternative to a fork. The calling session writes a brief and picks which of its
// memory notes and how many recent turns matter; they go into one file the new session reads first,
// so it gets only what the task needs instead of the whole (possibly huge) conversation.
const handoffDir=()=>path.join(home(),'claude-shared','handoffs');
function findNote(configDir,cwd,name){
  // Notes live in <config>/projects/<key>/memory, keyed by the project folder; take the deepest key
  // that the working folder falls under, then fall back to any project that has the note.
  const want=/\.md$/i.test(name)?name:name+'.md';
  const projects=path.join(configDir,'projects');let keys=[];try{keys=fs.readdirSync(projects);}catch{return null;}
  const cwdKey=projectKey(String(cwd||'').replace(/[^A-Za-z0-9]/g,'-'));
  const ranked=keys.filter(k=>fs.existsSync(path.join(projects,k,'memory',want)))
    .sort((a,b)=>(cwdKey.startsWith(projectKey(b))?b.length:0)-(cwdKey.startsWith(projectKey(a))?a.length:0));
  return ranked.length?path.join(projects,ranked[0],'memory',want):null;
}
function buildHandoff({from,brief,notes=[],recent=0,task,configDir,cwd}){
  const parts=[`# Handoff${from?` from session ${from}`:''}`,
    'You are continuing work another Claude session started. This file is all the context you get; treat it as authoritative.'];
  if(brief) parts.push('## Context',String(brief).trim());
  const missing=[];
  for(const n of notes){
    const f=configDir&&findNote(configDir,cwd,n);
    if(f) parts.push(`## Note: ${path.basename(f)}`,fs.readFileSync(f,'utf8').trim());else missing.push(n);
  }
  if(recent&&from){
    try{const turns=read(from,recent);if(turns.length) parts.push(`## Last ${turns.length} turns of that conversation`,turns.join('\n\n'));}catch{}
  }
  if(task) parts.push('## Your task',String(task).trim());
  fs.mkdirSync(handoffDir(),{recursive:true});
  const file=path.join(handoffDir(),`${new Date().toISOString().replace(/[:.]/g,'-')}-${process.pid}.md`);
  const content=parts.join('\n\n')+'\n';
  fs.writeFileSync(file,content); // kept as a record, and read by the session when too long to pass inline
  return {file,missing,content,prompt:`Read the handoff file ${file} first: it holds your context and your task. Then do the task.`};
}

// Fork: copy a session's transcript into another account and resume it there with --fork-session,
// so the new session starts with that whole conversation as its context (on the other account's quota).
function prepareFork(source,account){
  const live=sessions().find(s=>s.name===source||s.sessionId===source);
  const id=live?live.sessionId:source;
  const t=live&&live.transcript?{file:live.transcript}:transcriptOf(id);
  if(!t) throw new Error(`no transcript for session "${source}"`);
  const dst=path.join(account.dir,'projects',path.basename(path.dirname(t.file)),id+'.jsonl');
  if(path.resolve(dst)!==path.resolve(t.file)){fs.mkdirSync(path.dirname(dst),{recursive:true});fs.copyFileSync(t.file,dst);}
  let cwd=live?live.cwd:null;
  if(!cwd) for(const l of fs.readFileSync(t.file,'utf8').split(/\r?\n/)){try{const r=JSON.parse(l);if(r.cwd){cwd=r.cwd;break;}}catch{}}
  return {id,cwd};
}

// The MCP server runs from a fixed copy in ~/claude-accounts/mesh, so app updates never break the
// registered path; each run refreshes the copy. Accounts without the server get it once, user scope.
const toolsDir=()=>path.join(accountsDir(),'mesh');
function claudeJson(a){return a.name==='claude'?path.join(home(),'.claude.json'):path.join(a.dir,'.claude.json');}
function installTools(){
  const report=[];
  if(process.env.MULTI_CLAUDE_MESH_TOOLS==='0') return report;
  const dst=toolsDir();
  fs.mkdirSync(dst,{recursive:true});
  for(const n of ['mesh.js','mcp.js']){
    const src=path.join(__dirname,n),to=path.join(dst,n);
    if(path.resolve(src)===path.resolve(to)||!fs.existsSync(src)) continue;
    if(!fs.existsSync(to)||fs.readFileSync(src,'utf8')!==fs.readFileSync(to,'utf8')) fs.copyFileSync(src,to);
  }
  const server=path.join(dst,'mcp.js');
  for(const a of accounts()){
    let cfg;try{cfg=JSON.parse(fs.readFileSync(claudeJson(a),'utf8'));}catch{continue;} // not logged in yet
    const have=cfg.mcpServers&&cfg.mcpServers['multi-claude'];
    if(have&&(have.args||[]).some(x=>path.resolve(x)===path.resolve(server))) continue;
    const env=cleanEnv(a.name==='claude'?null:a.dir);
    if(a.name==='claude') delete env.CLAUDE_CONFIG_DIR;
    if(have) spawnSync(claudeCmd(),['mcp','remove','--scope','user','multi-claude'],{env,windowsHide:true,stdio:'ignore'});
    const r=spawnSync(claudeCmd(),['mcp','add','--scope','user','multi-claude','--',process.execPath,server],{env,windowsHide:true,encoding:'utf8'});
    const why=((r.stderr||'')+(r.error?r.error.message:'')).trim().split('\n')[0];
    report.push(`${a.name}: ${r.status===0?'tools added':`tools not added (${why})`}`);
  }
  return report;
}

// Resolves with the first live session of the account that was not running before, or null on timeout.
async function waitForNew(accountName,beforePids,timeoutMs=45000){
  const end=Date.now()+timeoutMs;
  while(Date.now()<end){
    const s=sessions().find(x=>x.account===accountName&&!beforePids.has(x.pid));
    if(s) return s;
    await new Promise(r=>setTimeout(r,1500));
  }
  return null;
}

const BEGIN='<!-- multi-claude session mesh -->',END='<!-- /multi-claude session mesh -->';
const INSTRUCTIONS=`${BEGIN}
## Sessions across accounts (multi-claude)
Live Claude sessions of EVERY account on this machine appear in ListAgents and can be messaged with SendMessage.
The multi-claude tools work across accounts: list_sessions, read_session, start_session (a new session on any
account, visible tab by default or headless). Use them when the user asks for work on another account.
Pass only the context the task needs: a handoff (your own brief + the relevant memory notes + a few recent
turns) by default, and fork the whole conversation only when a brief would lose too much.
${END}`;
function ensureInstructions(){
  const f=sharedClaude();
  if(process.env.MULTI_CLAUDE_MESH_INSTRUCTIONS==='0'||!fs.existsSync(f)) return;
  const text=fs.readFileSync(f,'utf8');
  const start=text.indexOf(BEGIN),stop=text.indexOf(END);
  const next=start>=0&&stop>start?text.slice(0,start)+INSTRUCTIONS+text.slice(stop+END.length):text.replace(/\s*$/,'\n\n')+INSTRUCTIONS+'\n';
  if(next!==text) fs.writeFileSync(f,next);
}
function removeInstructions(){
  const f=sharedClaude();if(!fs.existsSync(f)) return;
  const text=fs.readFileSync(f,'utf8'),start=text.indexOf(BEGIN),stop=text.indexOf(END);
  if(start>=0&&stop>start) fs.writeFileSync(f,text.slice(0,start).replace(/\s*$/,'\n')+text.slice(stop+END.length).replace(/^\s*/,''));
}

function alive(pid){try{process.kill(pid,0);return true;}catch(e){return e.code==='EPERM';}}
function transcriptOf(sessionId){
  for(const a of accounts()){
    const projects=path.join(a.dir,'projects');let dirs=[];try{dirs=fs.readdirSync(projects);}catch{continue;}
    for(const d of dirs){const f=path.join(projects,d,sessionId+'.jsonl');if(fs.existsSync(f)) return {account:a.name,file:f};}
  }
  return null;
}
function sessions(){
  const out=[];let names=[];try{names=fs.readdirSync(sharedDir());}catch{}
  for(const n of names){
    if(!/^\d+\.json$/.test(n)) continue;
    let s;try{s=JSON.parse(fs.readFileSync(path.join(sharedDir(),n),'utf8'));}catch{continue;}
    if(!s.pid||!alive(s.pid)) continue;
    const t=s.sessionId?transcriptOf(s.sessionId):null;
    // A session with no messages yet has no transcript; spawned ones leave a <pid>.account marker.
    let marked=null;try{marked=fs.readFileSync(path.join(sharedDir(),s.pid+'.account'),'utf8').trim();}catch{}
    out.push({name:s.name||'',account:t?t.account:marked||'?',sessionId:s.sessionId||'',status:s.status||'',kind:s.kind||'',cwd:s.cwd||'',pid:s.pid,transcript:t?t.file:null});
  }
  return out.sort((a,b)=>a.account.localeCompare(b.account)||a.name.localeCompare(b.name));
}

function textOf(content){
  if(typeof content==='string') return content;
  if(!Array.isArray(content)) return '';
  return content.filter(c=>c&&c.type==='text').map(c=>c.text).join('\n');
}
// Latest user/assistant text turns of a live session (by name) or any session (by id).
function read(target,lines=20){
  const live=sessions().find(s=>s.name===target||s.sessionId===target);
  const t=live&&live.transcript?{file:live.transcript}:transcriptOf(target);
  if(!t&&live) return [`(${live.name} is running but has no messages yet; it may be waiting on a first-run prompt or for its first message)`];
  if(!t) throw new Error(`no session named or with id "${target}"`);
  const turns=[];
  for(const raw of fs.readFileSync(t.file,'utf8').split('\n')){
    if(!raw.trim()) continue;let row;try{row=JSON.parse(raw);}catch{continue;}
    if((row.type!=='user'&&row.type!=='assistant')||!row.message||row.isMeta) continue;
    const text=textOf(row.message.content).trim();
    if(text) turns.push(`[${row.type}] ${text}`);
  }
  return turns.slice(-lines);
}

// A spawn started from inside a Claude session must not inherit that session's markers: with them the
// child acts as a sub-session (no transcript, no peer registration) and could speak as the parent.
const SESSION_VARS=['CLAUDECODE','CLAUDE_PID','CLAUDE_EFFORT','CLAUDE_CODE_CHILD_SESSION','CLAUDE_CODE_SESSION_ID',
  'CLAUDE_CODE_MESSAGING_SOCKET','CLAUDE_CODE_MESSAGING_TOKEN','CLAUDE_CODE_SESSION_ATTENDED','CLAUDE_CODE_SSE_PORT',
  'CLAUDE_CODE_ENTRYPOINT','CLAUDE_CODE_EXECPATH'];
function cleanEnv(configDir){
  const env={...process.env};
  for(const k of Object.keys(env)) if(SESSION_VARS.includes(k.toUpperCase())) delete env[k];
  if(configDir) env.CLAUDE_CONFIG_DIR=configDir;
  return env;
}

// On Windows run claude.exe directly (no shell) so the task stays one argument, quotes and all.
function claudeCmd(){
  if(!windows) return 'claude';
  const w=spawnSync('where',['claude'],{encoding:'utf8',windowsHide:true});
  return (w.stdout||'').split(/\r?\n/).map(l=>l.trim()).find(l=>/\.exe$/i.test(l))||'claude.exe';
}

function headless(account,task,{dir,model,resume,extra=[]}={}){
  // The prompt goes in on stdin: no command-line length limit, so a long handoff fits.
  const args=['-p','--output-format','json'];
  if(model) args.push('--model',model);
  if(resume) args.push('--resume',resume);
  const r=spawnSync(claudeCmd(),[...args,...extra],{cwd:dir||process.cwd(),env:cleanEnv(account.dir),input:task,encoding:'utf8',windowsHide:true,maxBuffer:64*1024*1024});
  if(r.error) throw r.error;
  let out;try{out=JSON.parse(r.stdout);}catch{return {ok:false,text:(r.stdout||'')+(r.stderr||'')};}
  return {ok:!out.is_error,text:out.result||'',sessionId:out.session_id};
}

// Headed: a new visible terminal runs "node mesh.js _exec <job>", which starts claude with the task
// as its first message. The job file carries the task so no shell quoting is involved.
function terminalCommand(execArgs,title,dir){
  const node=process.execPath;
  if(windows){
    const wt=spawnSync('where',['wt'],{encoding:'utf8',windowsHide:true});
    if(wt.status===0) return ['wt',['-w','0','new-tab','--title',title,'-d',dir,node,...execArgs]];
    return ['cmd',['/c','start',`"${title}"`,'/D',dir,node,...execArgs]];
  }
  const q=a=>`'${String(a).replace(/'/g,`'\\''`)}'`;
  const line=`cd ${q(dir)} && ${[node,...execArgs].map(q).join(' ')}`;
  if(process.platform==='darwin')
    return ['osascript',['-e',`tell application "Terminal" to do script ${JSON.stringify(line)}`,'-e','tell application "Terminal" to activate']];
  const candidates=[process.env.TERMINAL,'x-terminal-emulator','gnome-terminal','konsole','xterm'].filter(Boolean);
  for(const t of candidates){
    if(spawnSync('which',[t]).status!==0) continue;
    if(t.endsWith('gnome-terminal')) return [t,['--title',title,'--working-directory',dir,'--',node,...execArgs]];
    return [t,['-e',`bash -c ${q(line)}`]];
  }
  throw new Error('no terminal found for a visible session; use --headless or set $TERMINAL');
}
function headed(account,task,{dir,model,extra=[]}={}){
  dir=path.resolve(dir||process.cwd());
  const job=path.join(os.tmpdir(),`multi-claude-spawn-${process.pid}-${Date.now()}.json`);
  fs.writeFileSync(job,JSON.stringify({account:account.name,dir:account.dir,task,model,extra}));
  const [cmd,args]=terminalCommand([__filename,'_exec',job],account.name,dir);
  spawn(cmd,args,{detached:true,stdio:'ignore',env:cleanEnv()}).unref();
}
function execJob(job){
  const j=JSON.parse(fs.readFileSync(job,'utf8'));fs.rmSync(job,{force:true});
  const args=[];if(j.model) args.push('--model',j.model);args.push(...(j.extra||[]));if(j.task) args.push(j.task);
  const child=spawn(claudeCmd(),args,{stdio:'inherit',env:cleanEnv(j.dir)});
  const marker=path.join(sharedDir(),child.pid+'.account');
  try{fs.writeFileSync(marker,j.account);}catch{}
  child.on('exit',code=>{fs.rmSync(marker,{force:true});process.exit(code??1);});
  child.on('error',()=>{fs.rmSync(marker,{force:true});process.exit(1);});
}

function parse(argv){
  const opts={_:[],extra:[]};
  for(let i=0;i<argv.length;i++){
    const a=argv[i];
    if(a==='--'){opts.extra=argv.slice(i+1);break;}
    if(a==='--headless') opts.headless=true;
    else if(a==='--json') opts.json=true;
    else if(a==='--quiet') opts.quiet=true;
    else if(['--dir','--model','--resume','--lines','--fork','--brief','--notes','--recent','--from'].includes(a)) opts[a.slice(2)]=argv[++i];
    else opts._.push(a);
  }
  return opts;
}

const HELP=`multi-claude session mesh
  multi-claude sessions [--json]                   live sessions of all accounts
  multi-claude read <name|session-id> [--lines N]  latest messages of a session
  multi-claude spawn <account> ["task"] [--dir D] [--model M] [--headless] [--resume ID] [--fork SESSION] [-- <claude args>]
        handoff instead of fork: [--brief "context"] [--notes a.md,b.md] [--recent N --from SESSION]
                                                   new session; visible terminal tab unless --headless
  multi-claude mesh link|off|status                share session lists across accounts (on by default)
  multi-claude mesh memory-on|memory-off           share project notes across accounts (off by default)
Set MULTI_CLAUDE_MESH=0 to stop the automatic link on start.`;

async function interactive(){
  const rl=readline.createInterface({input:process.stdin,output:process.stdout});
  const ask=q=>new Promise(r=>rl.question(q,r));
  for(;;){
    const list=sessions();
    console.log('\n  LIVE SESSIONS (all accounts)\n');
    if(!list.length) console.log('  none');
    list.forEach((s,i)=>console.log(`  ${i+1}. ${s.account.padEnd(16)} ${s.name.padEnd(24)} ${s.status.padEnd(6)} ${s.cwd}`));
    console.log('\n  N. New session   R. Read a session   0. Back\n');
    const c=(await ask('  Pick an option: ')).trim().toLowerCase();
    if(c==='0'||c==='') break;
    if(c==='r'){
      const s=list[Number((await ask('  Session number: ')).trim())-1];
      if(s) console.log('\n'+read(s.sessionId,15).join('\n\n'));
      await ask('\n  Press Enter...');
    }else if(c==='n'){
      const all=accounts();all.forEach((a,i)=>console.log(`  ${i+1}. ${a.name}`));
      const acc=all[Number((await ask('  Account number: ')).trim())-1];if(!acc) continue;
      const dir=(await ask(`  Folder [${process.cwd()}]: `)).trim()||process.cwd();
      const task=(await ask('  Task (blank = open empty): ')).trim();
      const mode=(await ask('  Visible tab or headless? (v/h) [v]: ')).trim().toLowerCase();
      if(mode==='h'){
        if(!task){console.log('  Headless needs a task.');continue;}
        const r=headless(acc,task,{dir});console.log('\n'+r.text+(r.sessionId?`\nSESSION=${r.sessionId}`:''));
        await ask('\n  Press Enter...');
      }else headed(acc,task,{dir});
    }
  }
  rl.close();
}

async function main(argv){
  const [cmd,...rest]=argv,o=parse(rest);
  if(cmd==='_exec') return execJob(o._[0]);
  if(cmd==='menu') return interactive();
  if(cmd==='mesh'){
    const sub=o._[0]||'status';
    if(sub==='link'){const r=link();if(!o.quiet) console.log(r.length?r.join('\n'):'all accounts already share one session list');return;}
    if(sub==='off'){console.log(unlink().join('\n')||'nothing linked');return;}
    if(sub==='memory-off'){console.log(unshareMemory().join('\n')||'memory is not shared');return;}
    if(sub==='memory-on'){process.env.MULTI_CLAUDE_MESH_MEMORY='1';console.log(shareMemory().join('\n')||'memory already shared');return;}
    const shared=sharedDir();
    for(const a of accounts()){const s=path.join(a.dir,'sessions');console.log(`${a.name.padEnd(18)} ${isLink(s)&&sameDir(s,shared)?'shared':'own folder'}`);}
    return;
  }
  if(cmd==='sessions'){
    const list=sessions();
    if(o.json){console.log(JSON.stringify(list,null,2));return;}
    if(!list.length){console.log('no live sessions');return;}
    for(const s of list) console.log(`${s.account.padEnd(16)} ${s.name.padEnd(24)} ${s.status.padEnd(6)} ${s.sessionId}  ${s.cwd}`);
    return;
  }
  if(cmd==='read'){
    if(!o._[0]) throw new Error('usage: multi-claude read <name|session-id> [--lines N]');
    console.log(read(o._[0],Number(o.lines)||20).join('\n\n'));return;
  }
  if(cmd==='spawn'){
    const acc=findAccount(o._[0]);
    if(!acc) throw new Error(`unknown account "${o._[0]||''}"; accounts: ${accounts().map(a=>a.name).join(', ')}`);
    let task=o._.slice(1).join(' ');
    if(o.fork){const f=prepareFork(o.fork,acc);o.resume=f.id;o.dir=o.dir||f.cwd;o.extra=['--fork-session',...o.extra];}
    else if(o.brief||o.notes||o.recent){
      const h=buildHandoff({from:o.from||process.env.CLAUDE_CODE_SESSION_ID||null,brief:o.brief,notes:o.notes?o.notes.split(','):[],
        recent:Number(o.recent)||0,task,configDir:process.env.CLAUDE_CONFIG_DIR||path.join(home(),'.claude'),cwd:o.dir||process.cwd()});
      if(h.missing.length) console.error(`notes not found: ${h.missing.join(', ')}`);
      task=o.headless||h.content.length<24000?h.content:h.prompt;
    }
    if(o.headless){
      if(!task) throw new Error('--headless needs a task');
      const r=headless(acc,task,o);console.log(r.text);if(r.sessionId) console.log(`SESSION=${r.sessionId}`);
      process.exitCode=r.ok?0:1;return;
    }
    if(o.resume) o.extra=['--resume',o.resume,...o.extra];
    headed(acc,task,o);console.log(`opened ${acc.name} in a new terminal`);return;
  }
  console.log(HELP);
}

module.exports={buildHandoff,findNote,prepareFork,shareMemory,unshareMemory,mergeIndex,memoryRoot,waitForNew,installTools,accounts,findAccount,link,unlink,sessions,read,headless,headed,parse,sharedDir,INSTRUCTIONS};
if(require.main===module) main(process.argv.slice(2)).catch(e=>{console.error(e.message);process.exit(1);});
