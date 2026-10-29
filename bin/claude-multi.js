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
    const selected = updater.current(rootDir);
    // A newer downloaded release takes over the whole command, so its own subcommands work too
    // (this installed entry point may predate them).
    if (selected !== rootDir) {
        process.env.MULTI_CLAUDE_UPDATE_BOOTSTRAPPED = '1';
        const next = spawnSync(process.execPath, [path.join(selected, 'bin', 'claude-multi.js'), ...process.argv.slice(2)], { stdio: 'inherit' });
        process.exit(next.status ?? 1);
    }
}
process.env.MULTI_CLAUDE_UPDATE_BOOTSTRAPPED = '1';

if (process.argv.includes('--version')) {
    console.log(require(path.join(rootDir, 'package.json')).version);
    process.exit(0);
}
// Session mesh: share every account's live-session list (on by default), plus the
// sessions/read/spawn/mesh subcommands for working across accounts.
const meshScript = path.join(rootDir, 'mesh', 'mesh.js');
if (['sessions', 'read', 'spawn', 'mesh'].includes(process.argv[2])) {
    const mesh = spawnSync(process.execPath, [meshScript, ...process.argv.slice(2)], { stdio: 'inherit' });
    process.exit(mesh.status ?? 1);
}
if (process.env.MULTI_CLAUDE_MESH !== '0') {
    spawnSync(process.execPath, [meshScript, 'mesh', 'link', '--quiet'], { stdio: 'ignore', windowsHide: true });
}

const windows = os.platform() === 'win32';
const result = spawnSync(windows ? 'powershell' : '/bin/bash', windows
    ? ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(rootDir, 'claude-menu.ps1')]
    : [path.join(rootDir, 'unix', 'claude-menu.sh')], { stdio: 'inherit' });
if (result.error) console.error('Unable to start multi-claude: ' + result.error.message);
process.exit(result.status ?? 1);
