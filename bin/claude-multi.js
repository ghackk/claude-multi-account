#!/usr/bin/env node
const { execSync } = require('child_process');
const path = require('path');
const os = require('os');

const rootDir = path.resolve(__dirname, '..');

try {
    if (os.platform() === 'win32') {
        const script = path.join(rootDir, 'claude-menu.ps1');
        execSync(`powershell -ExecutionPolicy Bypass -File "${script}"`, { stdio: 'inherit' });
    } else {
        const script = path.join(rootDir, 'unix', 'claude-menu.sh');
        execSync(`bash "${script}"`, { stdio: 'inherit' });
    }
} catch (e) {
    process.exit(e.status || 1);
}
