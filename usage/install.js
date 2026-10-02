'use strict';
const fs=require('fs'),path=require('path');
const C=require('./collector');
const target=path.join(C.home,'claude-accounts'), source=path.resolve(__dirname,'..');
function copy(src,dst){if(path.resolve(src)===path.resolve(dst))return;fs.copyFileSync(src,dst);}
function patchLauncher(file){
  const original=fs.readFileSync(file,'utf8');
  let text=original.replace(/\r\n?/g,'\n');
  if(text.includes('multi-claude usage hooks')) {
    const normalized=file.endsWith('.bat')?text.replace(/\n/g,'\r\n'):text;
    if(normalized!==original)fs.writeFileSync(file,normalized);
    return false;
  }
  if(file.endsWith('.bat')) {
    const call='powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%USERPROFILE%\\claude-accounts\\claude-usage-report.ps1" -Background >nul 2>&1';
    text=text.replace(/^(\s*)(?:call\s+)?claude(\s+[^\r\n]*)?\r?$/mi,(_,space,args='')=>`REM multi-claude usage hooks\n${call}\ncall claude${args}\nset "_MULTI_CLAUDE_EXIT=%ERRORLEVEL%"\n${call}\nexit /b %_MULTI_CLAUDE_EXIT%`);
    text=text.replace(/\r?\n/g,'\r\n');
  }else if(file.endsWith('.sh')){
    const call='bash "$HOME/claude-accounts/claude-usage-report.sh" --background';
    text=text.replace(/^(\s*)(?:exec\s+)?claude(\s+[^\r\n]*)?\r?$/m,(_,space,args='')=>`# multi-claude usage hooks\n${call}\nclaude${args}\n_multi_claude_exit=$?\n${call}\nexit "$_multi_claude_exit"`);
    text=text.replace(/\r\n/g,'\n');
  }
  if(!text.includes('multi-claude usage hooks'))return false;
  fs.copyFileSync(file,file+'.before-usage');fs.writeFileSync(file,text);return true;
}
function hooks(dir){
  const file=path.join(dir,'settings.json');let settings={};
  if(fs.existsSync(file)){settings=C.readJSON(file);if(!settings)throw Error(`Invalid JSON; left unchanged: ${file}`);}
  const report=path.join(target,'claude-usage-report'+(process.platform==='win32'?'.ps1':'.sh'));
  const quote=s=>"'"+s.replace(/'/g,"'\\''")+"'";
  const command=process.platform==='win32'?`powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "${report}" -Background`:`bash ${quote(report)} --background`;
  settings.hooks ||= {};
  for(const event of ['SessionStart','SessionEnd']){
    const groups=settings.hooks[event] || [];
    for(const group of groups)if(Array.isArray(group.hooks))group.hooks=group.hooks.filter(h=>!(/claude-usage-report|local-usage[\\/]usage\.js/.test(h.command||'')));
    settings.hooks[event]=groups.filter(g=>!Array.isArray(g.hooks)||g.hooks.length);
    settings.hooks[event].push({hooks:[{type:'command',command,timeout:10}]});
  }
  const content=JSON.stringify(settings,null,2)+'\n';
  if(fs.existsSync(file)&&fs.readFileSync(file,'utf8')===content)return;
  if(fs.existsSync(file))fs.copyFileSync(file,file+'.before-usage');
  fs.mkdirSync(dir,{recursive:true});fs.writeFileSync(file,content);
}
function install(){
  require('node:sqlite');fs.mkdirSync(path.join(target,'usage'),{recursive:true});
  for(const name of ['database.js','collector.js','credentials.js','schedule.js','report.js','install.js','sharing.js','version.js'])copy(path.join(source,'usage',name),path.join(target,'usage',name));
  for(const name of ['claude-usage-report.ps1','claude-usage-report.sh'])copy(path.join(source,name),path.join(target,name));
  for(const entry of fs.readdirSync(target))if(/^claude-.*\.(bat|sh)$/.test(entry)&&!entry.startsWith('claude-usage-report'))patchLauncher(path.join(target,entry));
  const dirs=fs.readdirSync(C.home,{withFileTypes:true}).filter(e=>e.isDirectory()&&(e.name==='.claude'||e.name.startsWith('.claude-'))).map(e=>path.join(C.home,e.name));
  dirs.push(path.join(C.home,'claude-shared'));
  for(const dir of dirs)hooks(dir);
}
if(require.main===module){try{install();}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={install,patchLauncher,hooks};
