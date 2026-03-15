#!/usr/bin/env node
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

if (os.platform() === 'win32') process.exit(0); // Windows npm bin is typically on PATH already

try {
    // npm bin -g is deprecated in npm 9+; fall back to npm prefix -g + /bin
    let npmBin = '';
    try {
        npmBin = execSync('npm bin -g 2>/dev/null', { encoding: 'utf-8' }).trim();
    } catch (_) {}
    if (!npmBin) {
        const prefix = execSync('npm prefix -g', { encoding: 'utf-8' }).trim();
        if (prefix) npmBin = path.join(prefix, 'bin');
    }
    if (!npmBin) process.exit(0);

    // Check if already on PATH
    const pathDirs = (process.env.PATH || '').split(':');
    if (pathDirs.includes(npmBin)) process.exit(0);

    const home = os.homedir();
    const rcFiles = ['.bashrc', '.zshrc', '.profile'].map(f => path.join(home, f));
    const exportLine = `export PATH="${npmBin}:$PATH"`;

    let added = false;
    for (const rc of rcFiles) {
        if (!fs.existsSync(rc)) continue;
        const content = fs.readFileSync(rc, 'utf-8');
        if (content.includes(npmBin)) { added = true; break; }
    }

    if (!added) {
        // Find first existing rc file to append to
        for (const rc of rcFiles) {
            if (!fs.existsSync(rc)) continue;
            fs.appendFileSync(rc, `\n# npm global bin\n${exportLine}\n`);
            console.log(`  Added ${npmBin} to PATH in ${path.basename(rc)}`);
            console.log('  Restart your terminal or run: source ~/' + path.basename(rc));
            break;
        }
    }
} catch (_) {
    // Silent fail — non-critical
}
