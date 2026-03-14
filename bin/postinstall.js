#!/usr/bin/env node
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

if (os.platform() === 'win32') process.exit(0); // Windows npm bin is typically on PATH already

try {
    const npmBin = execSync('npm bin -g', { encoding: 'utf-8' }).trim();
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
