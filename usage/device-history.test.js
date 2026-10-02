'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),os=require('os'),path=require('path');
const D=require('./database');
test('names and complete per-email IP history survive repeated reports and database reopening',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'device-history-')),file=path.join(dir,'usage.db');let db=D.open(file);
 try{
 const d={fp:'1234567890abcdef',hostname:'Laptop',os:'macOS',username:'sam',identity_source:'macos-platform-uuid'};
 D.device(db,d,100);D.labelDevice(db,{fp:d.fp,label:'Work Mac',owner:'Sam',known:true});
 D.recordIp(db,d.fp,'192.0.2.1',100,['TEST@example.com']);D.recordIp(db,d.fp,'192.0.2.2',200,['test@example.com','second@example.com']);D.recordIp(db,d.fp,'192.0.2.1',300,['test@example.com']);D.recordIp(db,d.fp,'bad address',400,['test@example.com']);
 D.device(db,{...d,identity_source:''},500);D.labelDevice(db,{fp:d.fp,label:'Work Mac',known:true});db.close();db=D.open(file);
 const snapshot=D.snapshot(db,'all','test@example.com',d.fp),device=snapshot.devices[0];
 assert.equal(device.owner,'Sam');assert.equal(device.label,'Work Mac');assert.equal(device.identity_source,'macos-platform-uuid');assert.equal(device.ips.length,2);assert.equal(snapshot.accountIps.length,2);
 const first=snapshot.accountIps.find(x=>x.ip==='192.0.2.1');assert.equal(first.first_seen,100);assert.equal(first.last_seen,300);
 assert.equal(D.snapshot(db,'all','second@example.com').accountIps.length,1);
 assert.throws(()=>D.labelDevice(db,{fp:'aaaaaaaaaaaaaaaa',label:'Unknown',known:true}));
 assert.throws(()=>D.labelDevice(db,{fp:d.fp,label:'x',owner:2,known:true}));
 const writer=D.messageWriter(db),m={email:'test@example.com',id:'reply',model:'future-model',ts:Date.now(),input:10,output:20,cache_read:30,cache_write:40,device:d.fp};
 D.writeMessage(writer,m);D.writeMessage(writer,{...m,input:0,output:0,cache_read:0,cache_write:0});
 const other='abcdef1234567890';D.device(db,{...d,fp:other});db.prepare('INSERT INTO observations VALUES(?,?,?)').run(m.email,m.id,other);
 assert.equal(D.snapshot(db).total.replies,1);assert.equal(D.snapshot(db,'all',m.email,other).total.input,10);assert.equal(D.snapshot(db,'all','second@example.com',other).total.replies,0);
 }finally{db.close();fs.rmSync(dir,{recursive:true,force:true});}
});
