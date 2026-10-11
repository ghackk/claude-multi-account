'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),path=require('path'),os=require('os');
const {spawnSync}=require('child_process');
const D=require('./database');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'multi-claude-test-'));
process.env.CLAUDE_USAGE_HOME=path.join(root,'home');process.env.CLAUDE_USAGE_DIR=path.join(root,'data');fs.mkdirSync(process.env.CLAUDE_USAGE_HOME);
const C=require('./collector');
const profile=path.join(C.home,'.claude-fixture'),project=path.join(profile,'projects','one');fs.mkdirSync(project,{recursive:true});
fs.writeFileSync(path.join(profile,'.claude.json'),JSON.stringify({oauthAccount:{emailAddress:'owner@example.com',accountUuid:'a'}}));
const row=(id,out=5)=>JSON.stringify({type:'assistant',timestamp:'2026-01-01T23:30:00-05:00',sessionId:'s',message:{id,model:'claude-test',usage:{input_tokens:10,output_tokens:out,cache_read_input_tokens:20,cache_creation_input_tokens:3}}});
// Subagent (Task-tool) turns are relayed inline in the parent transcript, never under a "subagents" directory.
const agentRow=(id,out=5)=>JSON.stringify({type:'progress',timestamp:'2026-01-01T23:30:00-05:00',sessionId:'s',data:{type:'agent_progress',agentId:'ag1',message:{type:'assistant',timestamp:'2026-01-01T23:30:00-05:00',message:{id,model:'claude-test',usage:{input_tokens:10,output_tokens:out,cache_read_input_tokens:20,cache_creation_input_tokens:3}}}}});
test('incremental collection deduplicates growing content blocks, copied sessions, resets and partial lines',()=>{
  const db=D.open(path.join(C.dataDir,'usage.db')),file=path.join(project,'a.jsonl');
  fs.writeFileSync(file,row('m1')+'\n'+row('m1',15)+'\n'+row('m2').slice(0,40));C.collect(db);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM messages').get().n,1);
  assert.equal(db.prepare('SELECT output FROM messages').get().output,15);
  assert.equal(db.prepare('SELECT date FROM messages').get().date,'2026-01-02');
  fs.appendFileSync(file,row('m2').slice(40)+'\n');C.collect(db);assert.equal(db.prepare('SELECT COUNT(*) n FROM messages').get().n,2);
  fs.copyFileSync(file,path.join(project,'resumed.jsonl'));C.collect(db);assert.equal(db.prepare('SELECT COUNT(*) n FROM messages').get().n,2);
  fs.writeFileSync(path.join(project,'agent-progress.jsonl'),agentRow('m3')+'\n');C.collect(db);
  assert.equal(db.prepare('SELECT subagent FROM messages WHERE id=?').get('m3').subagent,1);
  assert.equal(db.prepare('SELECT output FROM messages WHERE id=?').get('m3').output,5);
  fs.writeFileSync(file,row('m4')+'\n');C.collect(db);assert.equal(db.prepare('SELECT COUNT(*) n FROM messages').get().n,4);
  fs.unlinkSync(path.join(profile,'.multi-claude-profile-id'));C.collect(db);assert.equal(db.prepare('SELECT COUNT(*) n FROM messages').get().n,4);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM profiles').get().n,2);
  const result=C.collect(db);assert.equal(result.lines,0);
  db.close();
});
test('lock prevents concurrent reporters and releases cleanly',()=>{const release=C.lock();assert.ok(release);assert.equal(C.lock(),null);release();const again=C.lock();assert.ok(again);again();});
test('main claude profile and a differently named profile sync to the same normalized email',()=>{
  const main=path.join(C.home,'.claude');fs.mkdirSync(path.join(main,'projects'),{recursive:true});
  fs.writeFileSync(path.join(C.home,'.claude.json'),JSON.stringify({oauthAccount:{emailAddress:'OWNER@EXAMPLE.COM',accountUuid:'a'}}));
  fs.writeFileSync(path.join(main,'projects','main.jsonl'),row('m1',15)+'\n'+row('main-only',9)+'\n');
  const alias=path.join(C.home,'.claude-zafff');fs.mkdirSync(path.join(alias,'projects'),{recursive:true});
  fs.writeFileSync(path.join(alias,'.claude.json'),JSON.stringify({oauthAccount:{emailAddress:'owner@example.com',accountUuid:'a'}}));
  fs.writeFileSync(path.join(alias,'projects','copy.jsonl'),row('main-only',9)+'\n');
  const db=D.open(path.join(C.dataDir,'usage.db'));C.collect(db);
  assert.equal(db.prepare('SELECT COUNT(DISTINCT email) n FROM messages').get().n,1);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM messages').get().n,5);
  assert.equal(db.prepare("SELECT COUNT(*) n FROM profiles WHERE name IN ('claude','claude-zafff')").get().n,2);
  const {hooks}=require('./install');hooks(main);const settings=C.readJSON(path.join(main,'settings.json'));
  assert.ok(settings.hooks.SessionStart[0].hooks[0].command.includes('claude-usage-report'));
  assert.ok(settings.hooks.SessionEnd[0].hooks[0].command.includes('claude-usage-report'));
  db.close();
});
test('history merge is idempotent and leaves source unchanged',()=>{
  const dest=path.join(root,'merged'),source=path.join(C.dataDir,'usage.db'),before=fs.readFileSync(source);
  for(let i=0;i<2;i++){
    const r=spawnSync(process.execPath,[path.join(__dirname,'report.js'),'merge',source],{env:{...process.env,CLAUDE_USAGE_DIR:dest},encoding:'utf8'});assert.equal(r.status,0,r.stderr);
  }
  const db=D.open(path.join(dest,'usage.db'));assert.equal(db.prepare('SELECT COUNT(*) n FROM messages').get().n,5);db.close();assert.deepEqual(fs.readFileSync(source),before);
});
test('backfill recovers subagent usage from files already fully consumed by an older collector, without moving the live offset',()=>{
  const bfProject=path.join(profile,'projects','backfill');fs.mkdirSync(bfProject,{recursive:true});
  const file=path.join(bfProject,'old.jsonl');
  fs.writeFileSync(file,agentRow('bf1')+'\n');
  const stat=fs.statSync(file);
  const head=fs.readFileSync(file).subarray(0,Math.min(256,stat.size));
  const signature=require('crypto').createHash('sha256').update(head).digest('hex');
  const instance=fs.readFileSync(path.join(profile,'.multi-claude-profile-id'),'utf8').trim();
  let db=D.open(path.join(C.dataDir,'usage.db'));
  // Simulate a file an older, buggy collector already scanned to completion, silently dropping the subagent line.
  db.prepare('INSERT INTO files(path,size,offset,signature,mtime,identity) VALUES(?,?,?,?,?,?)')
    .run(file,stat.size,stat.size,signature,stat.mtimeMs,'owner@example.com:'+instance);
  C.collect(db);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM messages WHERE id=?').get('bf1').n,0);
  db.close();
  const r=spawnSync(process.execPath,[path.join(__dirname,'report.js'),'backfill'],{env:process.env,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr);
  assert.match(r.stdout,/recovered/);
  db=D.open(path.join(C.dataDir,'usage.db'));
  const row=db.prepare('SELECT subagent,output FROM messages WHERE id=?').get('bf1');
  assert.equal(row.subagent,1); assert.equal(row.output,5);
  assert.equal(db.prepare('SELECT offset FROM files WHERE path=?').get(file).offset,stat.size);
  db.close();
});
test('launcher hooks preserve arguments and exit codes and are idempotent',()=>{
  const {patchLauncher}=require('./install');
  const bat=path.join(root,'claude-test.bat');fs.writeFileSync(bat,'@echo off\r\nset CLAUDE_CONFIG_DIR=%USERPROFILE%\\.claude-test\r\nclaude %*\r\n');assert.ok(patchLauncher(bat));
  const text=fs.readFileSync(bat,'utf8');assert.match(text,/call claude %\*/);assert.match(text,/exit \/b %_MULTI_CLAUDE_EXIT%/);assert.equal(/[\r\n]/.test(text.replace(/\r\n/g,'')),false);assert.match(text,/\.claude-test\r\nREM/);assert.equal(patchLauncher(bat),false);
  const sh=path.join(root,'claude-test.sh');fs.writeFileSync(sh,'#!/bin/bash\nclaude "$@"\n');patchLauncher(sh);assert.match(fs.readFileSync(sh,'utf8'),/exit "\$_multi_claude_exit"/);
});
test('session hooks and launcher patch route through wscript only when told it is available, falling back to direct powershell otherwise',()=>{
  const {hooks,patchLauncher,wshAvailable}=require('./install');
  const dir=path.join(C.home,'.claude-vbs-check');fs.mkdirSync(dir,{recursive:true});
  hooks(dir,true);
  assert.match(C.readJSON(path.join(dir,'settings.json')).hooks.SessionStart[0].hooks[0].command,/^wscript\.exe \/\/B ".*claude-usage-report-hidden\.vbs" -Background$/);
  hooks(dir,false);
  assert.match(C.readJSON(path.join(dir,'settings.json')).hooks.SessionStart[0].hooks[0].command,/^powershell\.exe .*claude-usage-report\.ps1" -Background$/);
  const vbsBat=path.join(root,'claude-vbs-check.bat');fs.writeFileSync(vbsBat,'@echo off\r\nclaude %*\r\n');patchLauncher(vbsBat,true);
  assert.match(fs.readFileSync(vbsBat,'utf8'),/wscript\.exe \/\/B "%USERPROFILE%\\claude-accounts\\claude-usage-report-hidden\.vbs" -Background/);
  const directBat=path.join(root,'claude-direct-check.bat');fs.writeFileSync(directBat,'@echo off\r\nclaude %*\r\n');patchLauncher(directBat,false);
  assert.match(fs.readFileSync(directBat,'utf8'),/powershell\.exe .*claude-usage-report\.ps1" -Background/);
  // Test/alternate homes must never run the live probe.
  assert.equal(wshAvailable(path.join(C.dataDir,'nonexistent.vbs')),false);
});
