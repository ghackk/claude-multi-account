#!/usr/bin/env node
const { spawnSync } = require('child_process');
const path = require('path');
const os = require('os');

const rootDir = path.resolve(__dirname, '..');

if (process.argv.includes('--version')) {
    console.log(require('../package.json').version);
    process.exit(0);
}
const windows = os.platform() === 'win32';
const result = spawnSync(windows ? 'powershell' : '/bin/bash', windows
    ? ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(rootDir, 'claude-menu.ps1')]
    : [path.join(rootDir, 'unix', 'claude-menu.sh')], { stdio: 'inherit' });
if (result.error) console.error('Unable to start multi-claude: ' + result.error.message);
process.exit(result.status ?? 1);
