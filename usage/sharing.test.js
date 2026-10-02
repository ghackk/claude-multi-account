'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'client-sharing-'));process.env.CLAUDE_USAGE_HOME=root;process.env.CLAUDE_USAGE_DIR=path.join(root,'usage');process.env.CLAUDE_CONFIG_DIR='';
const C=require('./collector'),S=require('./sharing');
const profile=path.join(root,'.claude-fixture'),email='fixture@example.com';fs.mkdirSync(profile);fs.writeFileSync(path.join(profile,'.claude.json'),JSON.stringify({oauthAccount:{emailAddress:email}}));
const receipt=()=>({transfer_id:crypto.randomUUID(),confirmation:'fixture',accounts:[email],receipts:{[email]:{transfer_id:crypto.randomUUID(),signature:'fixture'}}});
test('selected metadata excludes unselected accounts; receipt is tied to account and physical identity',()=>{
 const other=path.join(root,'.claude-other');fs.mkdirSync(other);fs.writeFileSync(path.join(other,'.claude.json'),JSON.stringify({oauthAccount:{emailAddress:'other@example.com'}}));
 assert.deepEqual(S.metadata(['claude-fixture']).accounts,[email]);assert.deepEqual(S.metadata(['missing']).accounts,[]);
 fs.writeFileSync(path.join(profile,'.multi-claude-share.json'),JSON.stringify({device:'wrong-device',email,confirmed:true,receipt:{transfer_id:'foreign'}}));assert.deepEqual(S.metadata(['claude-fixture']).parents,{});
});
test('failure and cancellation do not infer installed merely from an existing local profile',()=>{
 for(const status of ['failed','cancelled']){const r=receipt();S.finish(r,'http://127.0.0.1:1',status,[]);const job=JSON.parse(fs.readFileSync(path.join(C.dataDir,'sharing-pending',r.transfer_id+'.json')));assert.equal(job.results[0].status,status);}
});
test('journal stores no downloaded payload; completion cannot be overwritten by a begin retry',()=>{
 const r={...receipt(),token:'CREDENTIAL_FIXTURE_NEVER_IN_JOURNAL'};S.finish(r,'http://127.0.0.1:1','installed',['claude-fixture']);S.begin(r,'http://127.0.0.1:1');const raw=fs.readFileSync(path.join(C.dataDir,'sharing-pending',r.transfer_id+'.json'),'utf8');assert.doesNotMatch(raw,/CREDENTIAL_FIXTURE/);assert.equal(JSON.parse(raw).results[0].status,'installed');assert.equal(JSON.parse(fs.readFileSync(path.join(profile,'.multi-claude-share.json'))).confirmed,false);
});
test('nonlocal plaintext confirmation endpoints are rejected without any request',()=>{
 assert.throws(()=>S.begin(receipt(),'http://example.invalid'),/requires HTTPS/);
});
test('background reporter version matches both package channels and every scheduler uses 15 minutes',()=>{
 const version=require('./version');assert.equal(version,require('../package.json').version);
 assert.ok(fs.readFileSync(path.join(__dirname,'../pyproject.toml'),'utf8').includes('version = "'+version+'"'));
 assert.match(require('./schedule').plist('/fixture','/fixture/node'),/<key>StartInterval<\/key><integer>900<\/integer>/);
 assert.match(fs.readFileSync(path.join(__dirname,'../claude-usage-report.ps1'),'utf8'),/RepetitionInterval \(New-TimeSpan -Minutes 15\)/);
 assert.match(fs.readFileSync(path.join(__dirname,'../claude-usage-report.sh'),'utf8'),/\*\/15 \* \* \* \*/);
});
test('Windows install upgrades the existing schedule and installs the executing version helper in a closed fixture',{skip:process.platform!=='win32'},()=>{
 const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'heartbeat-install-'));
 const r=require('node:child_process').spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'windows-heartbeat.test.ps1'),'-FixtureHome',fixture],{encoding:'utf8',timeout:30000});assert.equal(r.status,0,r.stdout+'\n'+r.stderr);
});
test('a backup containing different imported copies of one email never chooses an arbitrary parent',()=>{
 const second=path.join(root,'.claude-copy');fs.mkdirSync(second);fs.writeFileSync(path.join(second,'.claude.json'),JSON.stringify({oauthAccount:{emailAddress:email}}));
 const fp=C.identity().fp;
 for(const dir of [profile,second])fs.writeFileSync(path.join(dir,'.multi-claude-share.json'),JSON.stringify({device:fp,email,confirmed:true,receipt:{transfer_id:crypto.randomUUID(),signature:'fixture'}}));
 assert.deepEqual(S.metadata(['claude-fixture','claude-copy']).parents,{});
 assert.ok(S.metadata(['claude-fixture']).parents[email]);
});
