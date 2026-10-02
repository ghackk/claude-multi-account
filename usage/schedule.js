'use strict';
const fs=require('fs'),path=require('path'),os=require('os');
const {spawnSync}=require('child_process');
const label='com.ghackk.multi-claude.usage';
const xml=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&apos;');
function plist(home,node) {
  const report=path.join(home,'claude-accounts','usage','report.js');
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>${label}</string>
<key>ProgramArguments</key><array><string>${xml(node)}</string><string>--disable-warning=ExperimentalWarning</string><string>${xml(report)}</string></array>
<key>StartInterval</key><integer>1800</integer>
<key>RunAtLoad</key><true/>
<key>EnvironmentVariables</key><dict><key>HOME</key><string>${xml(home)}</string><key>PATH</key><string>${xml(path.dirname(node))}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
<key>StandardOutPath</key><string>/dev/null</string><key>StandardErrorPath</key><string>/dev/null</string>
</dict></plist>\n`;
}
function schedule(enable,home=os.homedir(),run=(args)=>spawnSync('/bin/launchctl',args,{encoding:'utf8',timeout:10000})) {
  const file=path.join(home,'Library','LaunchAgents',label+'.plist');
  const domain=run(['print',`gui/${process.getuid()}`]).status===0?`gui/${process.getuid()}`:`user/${process.getuid()}`;
  const service=domain+'/'+label;
  if(!enable){run(['bootout',service]);fs.rmSync(file,{force:true});return;}
  const content=plist(home,process.execPath);
  if(fs.existsSync(file)&&fs.readFileSync(file,'utf8')===content&&run(['print',service]).status===0)return;
  run(['bootout',service]);
  fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,content,{mode:0o600});
  const r=run(['bootstrap',domain,file]);
  if(r.status!==0)throw Error('Could not load the usage LaunchAgent. Launchers and session hooks still collect usage. '+(r.stderr||''));
}
if(require.main===module){try{schedule(process.argv[2]==='enable');}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={plist,schedule};
