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
test('incremental collection deduplicates growing content blocks, copied sessions, resets and partial lines',()=>{
  const db=D.open(path.join(C.dataDir,'usage.db')),file=path.join(project,'a.jsonl');
  fs.writeFileSync(file,row('m1')+'\n'+row('m1',15)+'\n'+row('m2').slice(0,40));C.collect(db);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM messages').get().n,1);
  assert.equal(db.prepare('SELECT output FROM messages').get().output,15);
  assert.equal(db.prepare('SELECT date FROM messages').get().date,'2026-01-02');
  fs.appendFileSync(file,row('m2').slice(40)+'\n');C.collect(db);assert.equal(db.prepare('SELECT COUNT(*) n FROM messages').get().n,2);
  fs.copyFileSync(file,path.join(project,'resumed.jsonl'));C.collect(db);assert.equal(db.prepare('SELECT COUNT(*) n FROM messages').get().n,2);
  const sub=path.join(project,'subagents');fs.mkdirSync(sub);fs.writeFileSync(path.join(sub,'agent.jsonl'),row('m3')+'\n');C.collect(db);
  assert.equal(db.prepare('SELECT subagent FROM messages WHERE id=?').get('m3').subagent,1);
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
test('launcher hooks preserve arguments and exit codes and are idempotent',()=>{
  const {patchLauncher}=require('./install');
  const bat=path.join(root,'claude-test.bat');fs.writeFileSync(bat,'@echo off\r\nset CLAUDE_CONFIG_DIR=%USERPROFILE%\\.claude-test\r\nclaude %*\r\n');assert.ok(patchLauncher(bat));
  const text=fs.readFileSync(bat,'utf8');assert.match(text,/call claude %\*/);assert.match(text,/exit \/b %_MULTI_CLAUDE_EXIT%/);assert.equal(/[\r\n]/.test(text.replace(/\r\n/g,'')),false);assert.match(text,/\.claude-test\r\nREM/);assert.equal(patchLauncher(bat),false);
  const sh=path.join(root,'claude-test.sh');fs.writeFileSync(sh,'#!/bin/bash\nclaude "$@"\n');patchLauncher(sh);assert.match(fs.readFileSync(sh,'utf8'),/exit "\$_multi_claude_exit"/);
});
