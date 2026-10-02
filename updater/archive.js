'use strict';
// Deliberately accepts only regular files/directories from npm pack's package/ tar.
const fs=require('fs'),path=require('path'),zlib=require('zlib');
function extract(bytes,destination){
 const tar=zlib.gunzipSync(bytes,{maxOutputLength:100*1024*1024}),seen=new Set();let count=0;
 for(let at=0;at+512<=tar.length;){
  const h=tar.subarray(at,at+512);if(h.every(b=>b===0))break;
  const text=(a,n)=>h.subarray(a,a+n).toString('utf8').replace(/\0.*$/s,'');
  const oct=(a,n)=>{const s=text(a,n).trim();if(!/^[0-7]+$/.test(s))throw Error('Invalid archive field');return parseInt(s,8);};
  const sum=[...h].reduce((s,b,i)=>s+(i>=148&&i<156?32:b),0);if(sum!==oct(148,8))throw Error('Invalid archive checksum');
  const name=(text(345,155)?text(345,155)+'/':'')+text(0,100),size=oct(124,12),type=text(156,1)||'0';
  if(!['0','5'].includes(type)||size>30*1024*1024||at+512+size>tar.length||++count>5000)throw Error('Unsupported archive entry');
  if(!name.startsWith('package/')||/[\\:\x00-\x1f]/.test(name))throw Error('Unsafe archive path');
  const relative=name.slice(8).replace(/\/$/,'');
  if(relative){
   const parts=relative.split('/');if(parts.some(p=>!p||p==='.'||p==='..'||/[. ]$/.test(p)||/^(con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)/i.test(p)))throw Error('Unsafe archive path');
   const key=relative.toLowerCase();if(seen.has(key))throw Error('Duplicate archive path');seen.add(key);
   const target=path.resolve(destination,...parts);if(!target.startsWith(path.resolve(destination)+path.sep))throw Error('Archive escapes destination');
   if(type==='5')fs.mkdirSync(target,{recursive:true});else{fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,tar.subarray(at+512,at+512+size),{flag:'wx',mode:oct(100,8)&0o111?0o755:0o644});}
  }
  at+=512+Math.ceil(size/512)*512;
 }
 if(!count)throw Error('Empty archive');
}
module.exports={extract};
