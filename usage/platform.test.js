'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs'),os=require('os'),path=require('path');
const {spawnSync,execFileSync}=require('child_process');
const C=require('./credentials');
const root=path.resolve(__dirname,'..');
test('Windows default-account transfer preserves root email metadata',{skip:process.platform!=='win32'},()=>{
  const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'multi-claude-windows-'));
  try { run('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'windows-transfer.test.ps1'),'-FixtureHome',fixture]); }
  finally {fs.rmSync(fixture,{recursive:true,force:true});}
});
function run(command,args,options={}) {
  const r=spawnSync(command,args,{encoding:'utf8',timeout:60000,...options});
  assert.equal(r.status,0,r.stdout+'\n'+r.stderr+'\n'+(r.error||''));
  return r.stdout;
}
test('npm entry point runs without lifecycle setup',()=>{
  assert.equal(require('../package.json').scripts.postinstall,undefined);
  assert.equal(run(process.execPath,[path.join(root,'bin/claude-multi.js'),'--version']).trim(),require('../package.json').version);
});
test('Keychain service names isolate profiles and preserve NFC',()=>{
  assert.equal(C.service('/Users/test/.claude',true),'Claude Code-credentials');
  assert.notEqual(C.service('/Users/test/.claude-a'),C.service('/Users/test/.claude-b'));
  assert.equal(C.service('/Users/cafe\u0301/.claude-a'),C.service('/Users/café/.claude-a'));
});
test('native macOS temporary Keychain round-trip and isolation',{skip:process.platform!=='darwin'},()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'multi-claude-keychain-'));
  const keychain=path.join(dir,'fixture.keychain-db');
  const sec=(...args)=>execFileSync('/usr/bin/security',args,{stdio:'pipe'});
  try {
    sec('create-keychain','-p','synthetic-test-password',keychain);
    sec('unlock-keychain','-p','synthetic-test-password',keychain);
    const a={claudeAiOauth:{accessToken:'synthetic-a',expiresAt:123}},b={claudeAiOauth:{accessToken:'synthetic-b'}};
    C.write(dir+'/main',true,a,keychain);
    C.write(dir+'/profile',false,b,keychain);
    assert.deepEqual(C.read(dir+'/main',true,keychain),a);
    assert.deepEqual(C.read(dir+'/profile',false,keychain),b);
    assert.equal(C.read(dir+'/missing',false,keychain),null);
    C.write(dir+'/renamed',false,C.read(dir+'/profile',false,keychain),keychain);
    C.remove(dir+'/profile',false,keychain);
    assert.equal(C.read(dir+'/profile',false,keychain),null);
    assert.deepEqual(C.read(dir+'/renamed',false,keychain),b);
    assert.deepEqual(C.read(dir+'/main',true,keychain),a);
  } finally { try{sec('delete-keychain',keychain);}finally{fs.rmSync(dir,{recursive:true,force:true});} }
});
test('system Bash menu: create, launch, rename, export/import, default account, delete',{skip:process.platform==='win32'},()=>{
  const fixture=fs.mkdtempSync(path.join(os.tmpdir(),"multi claude's test-"));
  try {
    fs.mkdirSync(path.join(fixture,'bin'));
    fs.writeFileSync(path.join(fixture,'bin/claude'),'#!/bin/bash\nprintf "%s\\n" "$CLAUDE_CONFIG_DIR" "$@" > "$HOME/launched"\nexit 23\n',{mode:0o755});
    const script=String.raw`
export MULTI_CLAUDE_LIBRARY_ONLY=1 MULTI_CLAUDE_REPORT_URL=http://127.0.0.1:9/api/report MULTI_CLAUDE_AUTO_UPDATE=0
source "$PACKAGE_ROOT/unix/claude-menu.sh"
show_header() { :; }
start_usage_report() { :; }
# Menu integration uses fixture files; real Keychain is tested separately.
credential_helper() {
    case "$1" in
      export) cp "$2/.credentials.json" "$4" ;;
      import) if [ -d "$2" ]; then cp "$4" "$2/.credentials.json"; fi ;;
      remove) : ;;
    esac
}
create_account <<<'alpha
n'
test -x "$ACCOUNTS_DIR/claude-alpha.sh" || exit 1
test -L "$HOME/.local/bin/claude-alpha" || exit 1
test -f "$HOME/.zshrc" -o -f "$HOME/.bashrc" || exit 1
printf '{}' > "$HOME/.claude-alpha/.credentials.json"
printf '{"oauthAccount":{"emailAddress":"same@example.com"}}' > "$HOME/.claude-alpha/.claude.json"
PATH="$FIXTURE_BIN:$PATH" bash "$ACCOUNTS_DIR/claude-alpha.sh" 'two words' --continue
test "$?" = 23 || exit 1
grep -q '^two words$' "$HOME/launched" || exit 1
pick_account() { echo claude-alpha; }
rename_account <<<'beta
'
test -d "$HOME/.claude-beta" || exit 1
grep -q same@example.com "$HOME/.claude-beta/.claude.json" || exit 1
test ! -e "$HOME/.claude-alpha" || exit 1
test -x "$ACCOUNTS_DIR/claude-beta.sh" || exit 1
token=$(build_export_token claude-beta) || exit 1
[[ "$token" = CLAUDE_TOKEN_GZ:*:END_TOKEN ]] || exit 1
[[ "$token" != *$'\n'* ]] || exit 1
apply_import_token "$token" <<<'y' || exit 1
test -f "$HOME/.claude-beta/.credentials.json" || exit 1
mkdir -p "$HOME/.claude"
printf '{}' > "$HOME/.claude/.credentials.json"
printf '{"oauthAccount":{"emailAddress":"main@example.com"}}' > "$HOME/.claude.json"
main_token=$(build_export_token claude) || exit 1
printf '{}' > "$HOME/.claude.json"
apply_import_token "$main_token" <<<'y' || exit 1
grep -q main@example.com "$HOME/.claude.json" || exit 1
touch "$ACCOUNTS_DIR/claude-usage-report.sh"
[[ " $(get_accounts) " != *' claude-usage-report '* ]] || exit 1
pick_account() { echo claude-beta; }
delete_account <<<'YES
'
test ! -e "$HOME/.claude-beta" || exit 1
test -f "$HOME/.claude.json" || exit 1
echo 'Menu round-trip passed'
`;
    run('/bin/bash',['-c',script],{env:{...process.env,HOME:fixture,CLAUDE_USAGE_HOME:fixture,CLAUDE_CONFIG_DIR:'',PACKAGE_ROOT:root,FIXTURE_BIN:path.join(fixture,'bin'),PATH:path.dirname(process.execPath)+':'+process.env.PATH}});
  } finally {fs.rmSync(fixture,{recursive:true,force:true});}
});
test('macOS LaunchAgent plist and real CI scheduling',{skip:process.platform!=='darwin'},async()=>{
  const {plist,schedule}=require('./schedule');
  const fixture=fs.mkdtempSync(path.join(os.tmpdir(),"multi-claude agent's & test-"));
  const file=path.join(fixture,'agent.plist');
  fs.writeFileSync(file,plist(fixture,process.execPath));
  run('/usr/bin/plutil',['-lint',file]);
  try {
    if(process.env.CI==='true') {
      const script=path.join(fixture,'claude-accounts','usage','report.js');
      const marker=path.join(fixture,'ran');
      fs.mkdirSync(path.dirname(script),{recursive:true});
      fs.writeFileSync(script,`require('fs').writeFileSync(${JSON.stringify(marker)},'ok')`);
      schedule(true,fixture);
      for(let i=0;i<30&&!fs.existsSync(marker);i++)await new Promise(r=>setTimeout(r,500));
      assert.equal(fs.readFileSync(marker,'utf8'),'ok');
      schedule(false,fixture);
      assert.equal(fs.existsSync(path.join(fixture,'Library/LaunchAgents/com.ghackk.multi-claude.usage.plist')),false);
    }
  } finally {if(process.env.CI==='true')schedule(false,fixture);fs.rmSync(fixture,{recursive:true,force:true});}
});
test('legacy installer includes companion files and configures a fresh shell',{skip:process.platform==='win32'},()=>{
  const home=fs.mkdtempSync(path.join(os.tmpdir(),'multi-claude-install-'));
  try {
    run('/bin/bash',[path.join(root,'unix/install.sh')],{env:{...process.env,HOME:home,CLAUDE_USAGE_HOME:home,MULTI_CLAUDE_REPORT_URL:'http://127.0.0.1:9/api/report',MULTI_CLAUDE_AUTO_UPDATE:'0'}});
    for(const file of ['usage/credentials.js','usage/schedule.js','unix/archive.py','claude-usage-report.sh'])assert.ok(fs.existsSync(path.join(home,'claude-multi-account',file)),file);
    assert.ok(fs.lstatSync(path.join(home,'.local/bin/multi-claude')).isSymbolicLink());
  } finally{fs.rmSync(home,{recursive:true,force:true});}
});
test('pip startup persists its actual Scripts directory in a fresh shell',{skip:process.platform==='win32'},()=>{
  const home=fs.mkdtempSync(path.join(os.tmpdir(),"multi-claude pip's test-"));
  try {
    run('python3',['-c',String.raw`
import os, pathlib, sys
sys.path.insert(0, os.environ['PACKAGE_ROOT'])
from multi_claude import cli
scripts = pathlib.Path.home() / 'Library/Python/3.12/bin'
scripts.mkdir(parents=True)
cli._find_scripts_dirs = lambda: {str(scripts)}
os.environ['PATH'] = '/usr/bin:/bin'
cli.ensure_path()
rc = pathlib.Path.home() / ('.zshrc' if sys.platform == 'darwin' else '.bashrc')
assert 'Library/Python/3.12/bin' in rc.read_text()
assert str(scripts) in os.environ['PATH'].split(':')
`],{env:{...process.env,HOME:home,PACKAGE_ROOT:root,SHELL:'/bin/bash'}});
  } finally {fs.rmSync(home,{recursive:true,force:true});}
});
