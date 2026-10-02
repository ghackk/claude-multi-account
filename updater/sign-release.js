'use strict';
// Release-maintainer tool. The private key is never included in the package or feed.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const [archive,version,keyFile,output]=process.argv.slice(2);
if(!archive||!/^\d+\.\d+\.\d+$/.test(version||'')||!keyFile||!output)throw Error('Usage: sign-release.js package.tgz VERSION PRIVATE_KEY OUTPUT');
const bytes=fs.readFileSync(archive),privateKey=fs.readFileSync(keyFile);
const expected=crypto.createPublicKey(fs.readFileSync(path.join(__dirname,'public-key.pem'))).export({type:'spki',format:'der'});
if(!crypto.createPublicKey(privateKey).export({type:'spki',format:'der'}).equals(expected))throw Error('Signing key does not match the client pin');
const payload=JSON.stringify({schema:1,channel:'stable',version,minNode:'22.13.0',published:Date.now(),expires:Date.now()+89*864e5,artifact:{bytes:bytes.length,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),urls:[`https://pair.ghackk.com/updates/v${version}/package.tgz`,`https://github.com/ghackk/claude-multi-account/releases/download/v${version}/ghackk-multi-claude-${version}.tgz`]}});
const envelope={payload,signature:crypto.sign(null,Buffer.from(payload),privateKey).toString('base64')};
require('./update').verify(envelope,fs.readFileSync(path.join(__dirname,'public-key.pem')));
fs.writeFileSync(output,JSON.stringify(envelope)+'\n');console.log('Signed release '+version);
