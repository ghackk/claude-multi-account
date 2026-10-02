#!/usr/bin/env node
const { spawnSync } = require('child_process');
const path = require('path');
const os = require('os');

let rootDir = path.resolve(__dirname, '..');
const updater = require('../updater/update');
if (process.argv.includes('--update-now') || process.argv.includes('--update-status')) {
    const mode = process.argv.includes('--update-now') ? 'check' : 'status';
    const result = spawnSync(process.execPath, [path.join(rootDir, 'updater/update.js'), mode], {stdio:'inherit'});
    process.exit(result.status ?? 1);
}
if (process.env.MULTI_CLAUDE_UPDATE_BOOTSTRAPPED !== '1') {
    if (!process.argv.includes('--version')) updater.start(rootDir);
    rootDir = updater.current(rootDir);
}
process.env.MULTI_CLAUDE_UPDATE_BOOTSTRAPPED = '1';

if (process.argv.includes('--version')) {
    console.log(require(path.join(rootDir, 'package.json')).version);
    process.exit(0);
}
const windows = os.platform() === 'win32';
const result = spawnSync(windows ? 'powershell' : '/bin/bash', windows
    ? ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(rootDir, 'claude-menu.ps1')]
    : [path.join(rootDir, 'unix', 'claude-menu.sh')], { stdio: 'inherit' });
if (result.error) console.error('Unable to start multi-claude: ' + result.error.message);
process.exit(result.status ?? 1);
