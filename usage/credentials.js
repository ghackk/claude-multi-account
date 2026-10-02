'use strict';
// Match Claude Code's config-scoped macOS Keychain entry. Never fall back to
// another profile's entry and never refresh OAuth tokens here.
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const {execFileSync} = require('child_process');
function service(dir, isDefault = false) {
  return 'Claude Code-credentials' + (isDefault ? '' : '-' + crypto.createHash('sha256').update(dir.normalize('NFC')).digest('hex').slice(0,8));
}
function account() { return process.env.USER || os.userInfo().username; }
function security(args, options = {}) {
  return execFileSync('/usr/bin/security', args, {encoding:'utf8', timeout:10000, stdio:['pipe','pipe','pipe'], ...options});
}
function read(dir, isDefault = false, keychain) {
  if (process.platform === 'darwin') {
    try {
      return JSON.parse(security(['find-generic-password','-a',account(),'-s',service(dir,isDefault),'-w',...(keychain?[keychain]:[])]));
    } catch {}
  }
  try { return JSON.parse(fs.readFileSync(path.join(dir,'.credentials.json'),'utf8').replace(/^\uFEFF/,'')); } catch { return null; }
}
const quote = s => '"' + s.replace(/\\/g,'\\\\').replace(/"/g,'\\"') + '"';
function write(dir, isDefault, data, keychain) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw Error('Invalid credentials');
  const json = JSON.stringify(data);
  if (process.platform === 'darwin') {
    // Send hex via stdin, as Claude Code does; secrets never appear in argv.
    const input = `add-generic-password -U -a ${quote(account())} -s ${quote(service(dir,isDefault))} -X ${quote(Buffer.from(json).toString('hex'))}${keychain?' '+quote(keychain):''}\n`;
    try { security(['-i'],{input}); } catch { throw Error('Unable to save credentials to macOS Keychain. Unlock your login Keychain and retry.'); }
    let saved;
    try { saved=JSON.parse(security(['find-generic-password','-a',account(),'-s',service(dir,isDefault),'-w',...(keychain?[keychain]:[])])); }
    catch { throw Error('Unable to verify credentials in macOS Keychain'); }
    if (JSON.stringify(saved) !== json) throw Error('macOS Keychain did not save the credentials');
  } else {
    fs.mkdirSync(dir,{recursive:true,mode:0o700});
    fs.writeFileSync(path.join(dir,'.credentials.json'),json,{mode:0o600});
    fs.chmodSync(path.join(dir,'.credentials.json'),0o600);
  }
}
function remove(dir,isDefault,keychain) {
  if (process.platform === 'darwin') {
    try { security(['delete-generic-password','-a',account(),'-s',service(dir,isDefault),...(keychain?[keychain]:[])]); } catch {}
  }
}
if (require.main === module) {
  const [cmd,dir,defaultFlag,file] = process.argv.slice(2), isDefault = defaultFlag === 'default';
  try {
    if(cmd === 'export') {
      const data = read(dir,isDefault);
      if(!data) throw Error('No readable credentials for this profile');
      fs.writeFileSync(file,JSON.stringify(data),{mode:0o600});
      fs.chmodSync(file,0o600);
    } else if(cmd === 'import') write(dir,isDefault,JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')));
    else if(cmd === 'remove') remove(dir,isDefault);
    else throw Error('Unknown credential operation');
  } catch(e) { console.error(e.message); process.exitCode=1; }
}
module.exports={service,read,write,remove};
