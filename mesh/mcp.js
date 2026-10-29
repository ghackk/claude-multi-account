'use strict';
// MCP server (stdio) that gives every Claude session native tools to work across accounts:
// list live sessions, read one, and start a new session (visible tab or headless) on any account.
// Messaging itself is Claude Code's own SendMessage; the shared session list makes peers visible.
const readline=require('readline');
const M=require('./mesh');

const TOOLS=[
  {name:'list_sessions',
   description:'List live Claude sessions of EVERY account on this machine (name, account, status, folder) and the accounts available to start new sessions on. Message a session with SendMessage using its name.',
   inputSchema:{type:'object',properties:{}}},
  {name:'read_session',
   description:'Read the latest user/assistant messages of another Claude session, by its name (from list_sessions / ListAgents) or session id. Works for any account, live or finished.',
   inputSchema:{type:'object',properties:{session:{type:'string',description:'Session name or session id'},lines:{type:'number',description:'How many recent turns (default 20)'}},required:['session']}},
  {name:'start_session',
   description:'Start a new Claude session on another account (its quota is used). Default: a visible terminal tab; returns the new session name so you can SendMessage it (use notify_when_idle to hear when it finishes). headless:true when the user wants it in the background or just the answer back. '+
     'CONTEXT, choose smartly and pass only what the task needs: '+
     '(1) self-contained task: just `task`. '+
     '(2) needs some of your context (most handovers): HANDOFF, cheap. Write `brief` yourself with only what matters for this task (goal, decisions made, rules and limits, names/handles/ids, what to send back); list in `notes` the memory note files holding rules it must follow (e.g. outreach rules, price authority); add `recent_turns` (5-15) only if the latest exchange matters. '+
     '(3) needs the whole conversation because a brief would lose too much (long intertwined work): fork:"self". Expensive on the target account, use only then. '+
     'resume reopens an existing session.',
   inputSchema:{type:'object',properties:{
     account:{type:'string',description:'Account name, e.g. "gp", "claude-gp", or "claude" for the default account'},
     task:{type:'string',description:'What the new session must do and what result to send back (and to whom)'},
     brief:{type:'string',description:'Handoff: only the context this task needs, written by you'},
     notes:{type:'array',items:{type:'string'},description:'Handoff: memory note file names (from your MEMORY.md) to include in full'},
     recent_turns:{type:'number',description:'Handoff: include this many of your latest conversation turns (text only)'},
     fork:{type:'string',description:'"self" or a session name/id: start with that whole conversation (expensive; only when a brief would lose too much)'},
     folder:{type:'string',description:'Working folder (default: this session\'s folder)'},
     model:{type:'string',description:'Optional model, e.g. "sonnet"'},
     headless:{type:'boolean',description:'Run in the background and return the answer (default false = visible tab)'},
     resume:{type:'string',description:'Session id to reopen instead of starting fresh'}},required:['account']}},
];

function text(t,isError=false){return {content:[{type:'text',text:t}],isError};}

async function call(name,a={}){
  // Tolerate the obvious synonyms a model may guess before loading the schema.
  if(a.task===undefined) a.task=a.prompt??a.message;
  if(a.session===undefined) a.session=a.name??a.session_id??a.id;
  if(name==='list_sessions'){
    const list=M.sessions(),accs=M.accounts().map(x=>x.name);
    const rows=list.map(s=>`${s.name}  account=${s.account}  status=${s.status||'?'}  folder=${s.cwd}`);
    return text(`Live sessions (${list.length}):\n${rows.join('\n')||'none'}\n\nAccounts: ${accs.join(', ')}`);
  }
  if(name==='read_session') return text(M.read(a.session,Number(a.lines)||20).join('\n\n')||'(no text turns yet)');
  if(name==='start_session'){
    const acc=M.findAccount(a.account);
    if(!acc) return text(`Unknown account "${a.account}". Accounts: ${M.accounts().map(x=>x.name).join(', ')}`,true);
    const self=process.env.CLAUDE_CODE_SESSION_ID||'';
    let dir=a.folder||process.cwd(),resume=a.resume,extra=[],note='';
    if(a.fork){const f=M.prepareFork(a.fork==='self'?self:a.fork,acc);resume=f.id;dir=a.folder||f.cwd||dir;extra=['--fork-session'];}
    else if(a.brief||(a.notes&&a.notes.length)||a.recent_turns){
      const h=M.buildHandoff({from:self||null,brief:a.brief,notes:[].concat(a.notes||[]),recent:Number(a.recent_turns)||0,task:a.task,
        configDir:process.env.CLAUDE_CONFIG_DIR||require('path').join(require('os').homedir(),'.claude'),cwd:process.cwd()});
      // Inline when it fits (headless has no limit; a tab's command line caps near 32k chars on Windows).
      a.task=a.headless||h.content.length<24000?h.content:h.prompt;
      note=`Handoff file: ${h.file}${h.missing.length?` (notes not found: ${h.missing.join(', ')})`:''}\n`;
    }
    if(a.headless){
      if(!a.task) return text('headless needs a task',true);
      const r=M.headless(acc,a.task,{dir,model:a.model,resume,extra});
      return text(`${note}${r.text}\n\nSESSION=${r.sessionId||'?'} (account ${acc.name}; pass it as resume to continue)`,!r.ok);
    }
    const before=new Set(M.sessions().map(s=>s.pid));
    M.headed(acc,a.task||'',{dir,model:a.model,extra:[...(resume?['--resume',resume]:[]),...extra]});
    const s=await M.waitForNew(acc.name,before,45000);
    if(s) return text(`${note}Opened ${acc.name} in a visible tab. Session name: ${s.name} (id ${s.sessionId}). Message it with SendMessage to "${s.name}".`);
    return text(`${note}Opened ${acc.name} in a visible tab, but it has not registered yet. It may be waiting on a first-run prompt (e.g. "trust this folder") in that tab; check list_sessions again shortly.`);
  }
  return text(`Unknown tool ${name}`,true);
}

const send=m=>process.stdout.write(JSON.stringify(m)+'\n');
readline.createInterface({input:process.stdin}).on('line',async line=>{
  let msg;try{msg=JSON.parse(line);}catch{return;}
  const {id,method,params}=msg;
  if(id===undefined) return; // notifications
  try{
    if(method==='initialize') return send({jsonrpc:'2.0',id,result:{protocolVersion:params?.protocolVersion||'2024-11-05',capabilities:{tools:{}},serverInfo:{name:'multi-claude',version:'1'}}});
    if(method==='tools/list') return send({jsonrpc:'2.0',id,result:{tools:TOOLS}});
    if(method==='tools/call') return send({jsonrpc:'2.0',id,result:await call(params.name,params.arguments||{})});
    if(method==='ping') return send({jsonrpc:'2.0',id,result:{}});
    send({jsonrpc:'2.0',id,error:{code:-32601,message:`Method not found: ${method}`}});
  }catch(e){send({jsonrpc:'2.0',id,result:text(e.message,true)});}
});
