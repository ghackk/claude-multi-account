'use strict';
const fs = require('fs');
const path = require('path');
const {isIP} = require('net');
const COUNTERS = ['input', 'output', 'cache_read', 'cache_write'];
function open(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const { DatabaseSync } = require('node:sqlite');
  const db = new DatabaseSync(file);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
    CREATE TABLE IF NOT EXISTS messages (email TEXT NOT NULL,id TEXT NOT NULL,profile TEXT,session TEXT,date TEXT,model TEXT,ts INTEGER,input INTEGER,output INTEGER,cache_read INTEGER,cache_write INTEGER,device TEXT,PRIMARY KEY(email,id));
    CREATE INDEX IF NOT EXISTS messages_email_date ON messages(email,date);
    CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY,size INTEGER,offset INTEGER);
    CREATE TABLE IF NOT EXISTS devices(fp TEXT PRIMARY KEY,hostname TEXT,os TEXT,first_seen INTEGER,last_seen INTEGER);
    CREATE TABLE IF NOT EXISTS profiles(instance TEXT,device TEXT,email TEXT,name TEXT,account_uuid TEXT,first_seen INTEGER,last_seen INTEGER,stats TEXT,limits TEXT,limit_checked INTEGER,limit_status TEXT,PRIMARY KEY(instance,device));
    CREATE TABLE IF NOT EXISTS observations(email TEXT,id TEXT,device TEXT,PRIMARY KEY(email,id,device));
    CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT);
    CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY,ts INTEGER,type TEXT,device TEXT,source_device TEXT,accounts TEXT,transfer TEXT);
    CREATE TABLE IF NOT EXISTS transfers(route TEXT PRIMARY KEY,device TEXT,accounts TEXT,type TEXT,expires INTEGER);
    CREATE TABLE IF NOT EXISTS limit_snapshots(device TEXT,instance TEXT,checked INTEGER,data TEXT,status TEXT,PRIMARY KEY(device,instance,checked));`);
  db.exec('CREATE INDEX IF NOT EXISTS observations_device ON observations(device,email,id); CREATE TABLE IF NOT EXISTS device_ips(device TEXT,ip TEXT,first_seen INTEGER,last_seen INTEGER,PRIMARY KEY(device,ip));');
  db.exec('CREATE TABLE IF NOT EXISTS account_ips(email TEXT,device TEXT,ip TEXT,first_seen INTEGER,last_seen INTEGER,PRIMARY KEY(email,device,ip));');
  const add = (table, name, type) => {
    if (!db.prepare(`PRAGMA table_info(${table})`).all().some(x => x.name === name)) db.exec(`ALTER TABLE ${table} ADD COLUMN ${name} ${type}`);
  };
  add('messages', 'device', 'TEXT');
  add('messages', 'dirty', 'INTEGER DEFAULT 1');
  add('messages', 'subagent', 'INTEGER DEFAULT 0');
  add('files', 'signature', 'TEXT');
  add('files', 'mtime', 'REAL');
  add('files', 'identity', 'TEXT');
  add('devices', 'username', 'TEXT');
  add('devices', 'label', "TEXT DEFAULT ''");
  add('devices', 'known', 'INTEGER DEFAULT 0');
  add('devices', 'owner', "TEXT DEFAULT ''");
  add('devices', 'identity_source', "TEXT DEFAULT ''");
  add('devices', 'ip_address', 'TEXT');
  add('devices', 'ip_seen', 'INTEGER');
  return db;
}
function transaction(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try { const result = fn(); db.exec('COMMIT'); return result; }
  catch (e) { db.exec('ROLLBACK'); throw e; }
}
function device(db, d, now = Date.now()) {
  db.prepare(`INSERT INTO devices(fp,hostname,os,username,first_seen,last_seen,identity_source) VALUES(?,?,?,?,?,?,?)
    ON CONFLICT(fp) DO UPDATE SET hostname=excluded.hostname,os=excluded.os,username=excluded.username,last_seen=excluded.last_seen,
    identity_source=CASE WHEN excluded.identity_source<>'' THEN excluded.identity_source ELSE devices.identity_source END`)
    .run(d.fp,d.hostname,d.os,d.username || '',now,now,d.identity_source || '');
}
function recordIp(db,fp,ip,now=Date.now(),emails=[]) {
  if(typeof ip!=='string'||!isIP(ip))return;
  db.prepare('UPDATE devices SET ip_address=?,ip_seen=? WHERE fp=?').run(ip,now,fp);
  db.prepare('INSERT INTO device_ips VALUES(?,?,?,?) ON CONFLICT(device,ip) DO UPDATE SET last_seen=excluded.last_seen').run(fp,ip,now,now);
  const write=db.prepare('INSERT INTO account_ips VALUES(?,?,?,?,?) ON CONFLICT(email,device,ip) DO UPDATE SET last_seen=excluded.last_seen');
  for(const email of new Set(emails))if(typeof email==='string'&&email.includes('@'))write.run(email.trim().toLowerCase(),fp,ip,now,now);
}
function labelDevice(db,body) {
  if(!/^[a-f0-9]{16,64}$/.test(body?.fp||'')||typeof body.label!=='string'||body.label.length>120||typeof body.known!=='boolean'||(body.owner!==undefined&&(typeof body.owner!=='string'||body.owner.length>120)))throw Error('Invalid device name');
  const result=db.prepare('UPDATE devices SET label=?,known=?,owner=COALESCE(?,owner) WHERE fp=?').run(body.label.trim(),body.known?1:0,body.owner===undefined?null:body.owner.trim(),body.fp);
  if(!result.changes)throw Error('Device not found');
}
function messageWriter(db) {
  return db.prepare(`INSERT INTO messages(email,id,profile,session,date,model,ts,input,output,cache_read,cache_write,device,subagent,dirty)
    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,1) ON CONFLICT(email,id) DO UPDATE SET
    input=max(messages.input,excluded.input),output=max(messages.output,excluded.output),
    cache_read=max(messages.cache_read,excluded.cache_read),cache_write=max(messages.cache_write,excluded.cache_write),
    subagent=max(messages.subagent,excluded.subagent),dirty=1
    WHERE excluded.input>messages.input OR excluded.output>messages.output OR excluded.cache_read>messages.cache_read
      OR excluded.cache_write>messages.cache_write OR excluded.subagent>messages.subagent`);
}
function writeMessage(stmt, m) {
  stmt.run(m.email.trim().toLowerCase(),m.id,m.profile || '',m.session || '',new Date(m.ts).toISOString().slice(0,10),m.model,m.ts,
    ...COUNTERS.map(k => m[k]),m.device,m.subagent ? 1 : 0);
}
function setMeta(db, key, value) { db.prepare('INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value').run(key,JSON.stringify(value)); }
function getMeta(db, key, fallback = null) { const row = db.prepare('SELECT value FROM meta WHERE key=?').get(key); return row ? JSON.parse(row.value) : fallback; }
function snapshot(db, range = 'all', email = '', deviceFp = '') {
  const now = new Date(), since = range === 'year' ? `${now.getUTCFullYear()}-01-01` : ['7','30'].includes(range)
    ? new Date(Date.now() - (Number(range)-1)*864e5).toISOString().slice(0,10) : '0000';
  const where = 'date>=? AND (?=\'\' OR email=?) AND (?=\'\' OR device=? OR EXISTS(SELECT 1 FROM observations o WHERE o.email=messages.email AND o.id=messages.id AND o.device=?))', args = [since,email,email,deviceFp,deviceFp,deviceFp];
  const sum = 'COALESCE(SUM(input),0) input,COALESCE(SUM(output),0) output,COALESCE(SUM(cache_read),0) cache_read,COALESCE(SUM(cache_write),0) cache_write,COUNT(*) replies,COUNT(DISTINCT session) sessions';
  const profiles = db.prepare('SELECT * FROM profiles WHERE (?=\'\' OR email=?) AND (?=\'\' OR device=?) ORDER BY email,name').all(email,email,deviceFp,deviceFp).map(p => ({...p,stats:JSON.parse(p.stats || 'null'),limits:JSON.parse(p.limits || 'null')}));
  const links=db.prepare('SELECT device,email FROM profiles UNION SELECT device,email FROM observations UNION SELECT device,email FROM messages').all();
  const devices=db.prepare('SELECT * FROM devices ORDER BY last_seen DESC').all().map(d=>({...d,accounts:links.filter(l=>l.device===d.fp).map(l=>l.email),ips:db.prepare('SELECT ip,first_seen,last_seen FROM device_ips WHERE device=? ORDER BY last_seen DESC').all(d.fp)}));
  return {generated:Date.now(),since,range,email,device:deviceFp,
    accounts:db.prepare('SELECT DISTINCT email FROM messages UNION SELECT DISTINCT email FROM profiles ORDER BY email').all().map(x=>x.email),
    total:db.prepare(`SELECT ${sum} FROM messages WHERE ${where}`).get(...args),
    byAccount:db.prepare(`SELECT email,${sum} FROM messages WHERE ${where} GROUP BY email`).all(...args),
    models:db.prepare(`SELECT model,${sum} FROM messages WHERE ${where} GROUP BY model ORDER BY SUM(input+output+cache_read+cache_write) DESC`).all(...args),
    daily:db.prepare(`SELECT date,${sum} FROM messages WHERE ${where} GROUP BY date ORDER BY date`).all(...args),
    months:db.prepare(`SELECT substr(date,1,7) month,${sum} FROM messages WHERE ${where} GROUP BY month ORDER BY month DESC`).all(...args),
    devices,
    accountIps:db.prepare("SELECT * FROM account_ips WHERE (?='' OR email=?) AND (?='' OR device=?) ORDER BY last_seen DESC").all(email,email,deviceFp,deviceFp),
    byDevice:db.prepare(`SELECT device,${sum} FROM messages WHERE ${where} GROUP BY device`).all(...args),
    observations:db.prepare('SELECT device,COUNT(*) replies FROM observations WHERE (?=\'\' OR email=?) GROUP BY device').all(email,email),
    observedByDevice:db.prepare(`SELECT o.device,COALESCE(SUM(m.input+m.output+m.cache_read+m.cache_write),0) tokens,COUNT(*) replies FROM observations o JOIN messages m ON m.email=o.email AND m.id=o.id WHERE m.date>=? AND (?='' OR m.email=?) GROUP BY o.device`).all(since,email,email),
    profiles,events:db.prepare('SELECT * FROM events ORDER BY ts DESC LIMIT 200').all().map(x=>({...x,accounts:JSON.parse(x.accounts)})),
    upload:getMeta(db,'upload'), collection:getMeta(db,'collection'),
    note:'UTC calendar dates. Includes subagents. Replies deduplicated per email and reply ID. Device totals attribute usage to the first reporting device, not necessarily the device that generated it.'};
}
module.exports = {open,transaction,device,recordIp,labelDevice,messageWriter,writeMessage,setMeta,getMeta,snapshot,COUNTERS};
