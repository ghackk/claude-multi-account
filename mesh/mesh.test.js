'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),path=require('path'),os=require('os');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'multi-claude-mesh-'));
process.env.MULTI_CLAUDE_HOME=root;
const M=require('./mesh');
const acc=n=>path.join(root,'.'+n);
fs.mkdirSync(path.join(root,'claude-accounts'));
fs.mkdirSync(path.join(root,'claude-shared'));
fs.writeFileSync(path.join(root,'claude-shared','CLAUDE.md'),'# Shared\n');
for(const n of ['claude-a','claude-b']) fs.writeFileSync(path.join(root,'claude-accounts',n+'.bat'),'@echo off\n');
fs.writeFileSync(path.join(root,'claude-accounts','claude-menu.bat'),'');
// Existing account with a live session already registered in its own folder.
fs.mkdirSync(path.join(acc('claude-a'),'sessions'),{recursive:true});
fs.writeFileSync(path.join(acc('claude-a'),'sessions',process.pid+'.json'),JSON.stringify({pid:process.pid,sessionId:'s-live',name:'live-1',status:'idle',cwd:root}));
fs.mkdirSync(path.join(acc('claude-a'),'projects','p'),{recursive:true});
fs.writeFileSync(path.join(acc('claude-a'),'projects','p','s-live.jsonl'),[
  {type:'user',message:{role:'user',content:'hello there'}},
  {type:'assistant',message:{role:'assistant',content:[{type:'text',text:'hi back'},{type:'tool_use',name:'x'}]}},
  {type:'user',isMeta:true,message:{role:'user',content:'meta'}},
].map(r=>JSON.stringify(r)).join('\n')+'\n');

test('accounts come from launchers, menu launcher excluded',()=>{
  assert.deepEqual(M.accounts().map(a=>a.name),['claude-a','claude-b']);
  assert.equal(M.findAccount('b').name,'claude-b');
  assert.equal(M.findAccount('nope'),null);
});
test('link joins existing folders and accounts without one, keeps live entries, is idempotent',()=>{
  const report=M.link();
  assert.deepEqual(report,['claude-a: linked','claude-b: linked']);
  for(const n of ['claude-a','claude-b']){
    const s=path.join(acc(n),'sessions');
    assert.ok(fs.lstatSync(s).isSymbolicLink());
    assert.ok(fs.existsSync(path.join(s,process.pid+'.json')));
  }
  assert.deepEqual(M.link(),[]);
  assert.match(fs.readFileSync(path.join(root,'claude-shared','CLAUDE.md'),'utf8'),/multi-claude session mesh/);
  M.link();
  assert.equal(fs.readFileSync(path.join(root,'claude-shared','CLAUDE.md'),'utf8').split('<!-- multi-claude session mesh -->').length,2);
});
test('a new account created later joins on the next link',()=>{
  fs.writeFileSync(path.join(root,'claude-accounts','claude-c.bat'),'@echo off\n');
  assert.deepEqual(M.link(),['claude-c: linked']);
  assert.ok(fs.existsSync(path.join(acc('claude-c'),'sessions',process.pid+'.json')));
});
test('sessions lists live entries with their account, drops dead pids',()=>{
  fs.writeFileSync(path.join(M.sharedDir(),'999999.json'),JSON.stringify({pid:999999,sessionId:'dead',name:'dead'}));
  const list=M.sessions();
  assert.equal(list.length,1);
  assert.equal(list[0].account,'claude-a');
  assert.equal(list[0].name,'live-1');
});
test('read returns text turns by name or id, skipping tools and meta',()=>{
  assert.deepEqual(M.read('live-1'),['[user] hello there','[assistant] hi back']);
  assert.deepEqual(M.read('s-live',1),['[assistant] hi back']);
  assert.throws(()=>M.read('missing'),/no session/);
});
test('parse splits flags, task words and passthrough args',()=>{
  const o=M.parse(['gp','do','this','--headless','--dir','D','--','--permission-mode','auto']);
  assert.deepEqual(o._,['gp','do','this']);assert.equal(o.headless,true);assert.equal(o.dir,'D');
  assert.deepEqual(o.extra,['--permission-mode','auto']);
});
test('off gives every account its own folder back and removes the instructions',()=>{
  const report=M.unlink();
  assert.equal(report.length,3);
  for(const n of ['claude-a','claude-b','claude-c']){
    const s=path.join(acc(n),'sessions');
    assert.ok(!fs.lstatSync(s).isSymbolicLink());
    assert.ok(fs.existsSync(path.join(s,process.pid+'.json')));
  }
  assert.doesNotMatch(fs.readFileSync(path.join(root,'claude-shared','CLAUDE.md'),'utf8'),/session mesh/);
});
test('MCP server answers initialize, lists the three tools and runs list_sessions',()=>{
  const {spawnSync}=require('child_process');
  const input=[
    {jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2024-11-05'}},
    {jsonrpc:'2.0',method:'notifications/initialized'},
    {jsonrpc:'2.0',id:2,method:'tools/list'},
    {jsonrpc:'2.0',id:3,method:'tools/call',params:{name:'list_sessions',arguments:{}}},
    {jsonrpc:'2.0',id:4,method:'tools/call',params:{name:'start_session',arguments:{account:'nope'}}},
  ].map(m=>JSON.stringify(m)).join('\n')+'\n';
  const r=spawnSync(process.execPath,[path.join(__dirname,'mcp.js')],{input,encoding:'utf8',env:{...process.env,MULTI_CLAUDE_HOME:root},timeout:10000});
  const out=r.stdout.trim().split('\n').map(l=>JSON.parse(l));
  assert.equal(out.length,4);
  assert.equal(out[0].result.serverInfo.name,'multi-claude');
  assert.deepEqual(out[1].result.tools.map(t=>t.name),['list_sessions','read_session','start_session']);
  assert.match(out[2].result.content[0].text,/Accounts: claude-a, claude-b, claude-c/);
  assert.equal(out[3].result.isError,true);
});
test('mergeIndex keeps the newest index and adds entries only the others had',()=>{
  const merged=M.mergeIndex(['- [A](a.md) — new\n- [B](b.md) — b\n','- [A](a.md) — old\n- [C](c.md) — c\n']);
  assert.equal(merged,'- [A](a.md) — new\n- [B](b.md) — b\n- [C](c.md) — c\n');
});
test('memory is not shared unless switched on',()=>{
  assert.deepEqual(M.shareMemory(),[]);
});
test('shareMemory merges per-project notes, links every account, parks conflicts and backs up',()=>{
  M.link();process.env.MULTI_CLAUDE_MESH_MEMORY='1'; // sessions shared again after the earlier "off" test
  const mem=(n,k)=>path.join(acc(n),'projects',k,'memory');
  fs.mkdirSync(mem('claude-a','D--proj'),{recursive:true});
  fs.mkdirSync(mem('claude-b','D--proj'),{recursive:true});
  fs.writeFileSync(path.join(mem('claude-a','D--proj'),'rule.md'),'old rule');
  fs.writeFileSync(path.join(mem('claude-a','D--proj'),'only-a.md'),'a');
  fs.writeFileSync(path.join(mem('claude-a','D--proj'),'MEMORY.md'),'- [Rule](rule.md) — r\n- [A](only-a.md) — a\n');
  const later=Date.now()/1000+5;
  fs.writeFileSync(path.join(mem('claude-b','D--proj'),'rule.md'),'new rule');fs.utimesSync(path.join(mem('claude-b','D--proj'),'rule.md'),later,later);
  fs.writeFileSync(path.join(mem('claude-b','D--proj'),'MEMORY.md'),'- [Rule](rule.md) — r2\n');fs.utimesSync(path.join(mem('claude-b','D--proj'),'MEMORY.md'),later,later);
  const report=M.shareMemory();
  assert.ok(report.some(l=>/memory D--proj: shared/.test(l)));
  for(const n of ['claude-a','claude-b','claude-c']){
    const m=mem(n,'D--proj');
    assert.ok(fs.lstatSync(m).isSymbolicLink(),n);
    assert.equal(fs.readFileSync(path.join(m,'rule.md'),'utf8'),'new rule');
    assert.equal(fs.readFileSync(path.join(m,'only-a.md'),'utf8'),'a');
    assert.equal(fs.readFileSync(path.join(m,'MEMORY.md'),'utf8'),'- [Rule](rule.md) — r2\n- [A](only-a.md) — a\n');
  }
  assert.equal(fs.readFileSync(path.join(root,'claude-shared','memory-conflicts','D--proj','claude-a','rule.md'),'utf8'),'old rule');
  assert.ok(fs.readdirSync(path.join(root,'claude-shared')).some(n=>n.startsWith('memory-backup-')));
  fs.writeFileSync(path.join(mem('claude-c','D--proj'),'from-c.md'),'c');
  assert.ok(fs.existsSync(path.join(mem('claude-a','D--proj'),'from-c.md')));
  assert.deepEqual(M.shareMemory(),[]);
});
test('prepareFork copies the transcript into the target account and finds its folder',()=>{
  const f=M.prepareFork('s-live',M.findAccount('b'));
  assert.equal(f.id,'s-live');
  assert.equal(f.cwd,root);
  assert.ok(fs.existsSync(path.join(acc('claude-b'),'projects','p','s-live.jsonl')));
});
test('an account with an empty memory folder for a project gets the shared notes too',()=>{
  const m=path.join(acc('claude-b'),'projects','D--other','memory');
  fs.mkdirSync(path.join(acc('claude-a'),'projects','D--other','memory'),{recursive:true});
  fs.writeFileSync(path.join(acc('claude-a'),'projects','D--other','memory','x.md'),'x');
  fs.mkdirSync(m,{recursive:true});
  M.shareMemory();
  assert.ok(fs.lstatSync(m).isSymbolicLink());
  assert.equal(fs.readFileSync(path.join(m,'x.md'),'utf8'),'x');
});
test('unshareMemory gives owners their own notes back plus later notes; link-only accounts lose the link',()=>{
  const mem=(n,k)=>path.join(acc(n),'projects',k,'memory');
  // A note written through the shared folder after the merge.
  const late=path.join(mem('claude-a','D--proj'),'late.md');fs.writeFileSync(late,'late');
  const t=Date.now()/1000+600;fs.utimesSync(late,t,t);
  const report=M.unshareMemory();
  assert.ok(report.length>0);
  for(const n of ['claude-a','claude-b']){
    const m=mem(n,'D--proj');
    assert.ok(!fs.lstatSync(m).isSymbolicLink(),n);
    assert.ok(fs.existsSync(path.join(m,'late.md')),n);
  }
  assert.equal(fs.readFileSync(path.join(mem('claude-a','D--proj'),'rule.md'),'utf8'),'old rule');
  assert.equal(fs.readFileSync(path.join(mem('claude-b','D--proj'),'rule.md'),'utf8'),'new rule');
  assert.ok(!fs.existsSync(path.join(mem('claude-b','D--proj'),'only-a.md')));
  assert.doesNotMatch(fs.readFileSync(path.join(mem('claude-b','D--proj'),'MEMORY.md'),'utf8'),/only-a/);
  assert.ok(!fs.existsSync(mem('claude-c','D--proj')));
  assert.ok(!fs.existsSync(M.memoryRoot()));
  delete process.env.MULTI_CLAUDE_MESH_MEMORY;
});
test('buildHandoff packs only the brief, chosen notes and recent turns, and reports missing notes',()=>{
  const cfg=acc('claude-a'),notes=path.join(cfg,'projects','D--repo','memory');
  fs.mkdirSync(notes,{recursive:true});
  fs.writeFileSync(path.join(notes,'price-rule.md'),'Close up to 2500 without asking.');
  fs.writeFileSync(path.join(notes,'unrelated.md'),'should not be included');
  const h=M.buildHandoff({from:'s-live',brief:'Reply to pending creators.',notes:['price-rule','nope.md'],recent:1,task:'Draft replies.',configDir:cfg,cwd:'D:\repo\sub'});
  assert.match(h.content,/Reply to pending creators\./);
  assert.match(h.content,/Close up to 2500 without asking\./);
  assert.doesNotMatch(h.content,/should not be included/);
  assert.match(h.content,/\[assistant\] hi back/);
  assert.doesNotMatch(h.content,/hello there/);
  assert.match(h.content,/## Your task\n\nDraft replies\./);
  assert.deepEqual(h.missing,['nope.md']);
  assert.equal(fs.readFileSync(h.file,'utf8'),h.content);
});
