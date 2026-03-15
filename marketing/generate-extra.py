"""Generate extra marketing images and animated GIF."""
import subprocess, os, time, struct, zlib

EDGE = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'images')

def capture(name, html, w=1200, h=628):
    html_path = os.path.join(OUT, f'{name}.html')
    png_path = os.path.join(OUT, f'{name}.png')
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(html)
    file_url = 'file:///' + html_path.replace(os.sep, '/')
    cmd = [EDGE, '--headless', '--disable-gpu', f'--screenshot={png_path}',
           f'--window-size={w},{h}', '--hide-scrollbars', file_url]
    subprocess.run(cmd, capture_output=True, timeout=15)
    time.sleep(0.5)
    os.remove(html_path)
    if os.path.exists(png_path):
        print(f'  OK  {name}.png ({os.path.getsize(png_path)//1024} KB)')
        return True
    print(f'  FAIL {name}.png')
    return False

# ─── Common styles ──────────────────────────────────────────────────────────

GRAD1 = 'linear-gradient(135deg, #0d1117 0%, #161b22 50%, #1a1f2e 100%)'
GRAD2 = 'linear-gradient(160deg, #0a0e14 0%, #1a1f2e 50%, #0d1117 100%)'
GRAD3 = 'linear-gradient(135deg, #0d1117 0%, #0f172a 50%, #1e1b4b 100%)'
FONT = "'Segoe UI', -apple-system, sans-serif"
MONO = "'Cascadia Code', 'Consolas', monospace"

# ─── Image 11: Feature Highlights Grid ──────────────────────────────────────

capture('11-features-grid', f'''<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{background:{GRAD3};width:1200px;height:628px;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:50px;font-family:{FONT};}}
.title{{font-size:42px;font-weight:800;color:#f0f6fc;margin-bottom:8px;text-align:center}}
.title span{{color:#58a6ff}}
.sub{{font-size:18px;color:#8b949e;margin-bottom:40px;text-align:center}}
.grid{{display:grid;grid-template-columns:repeat(3,1fr);gap:20px;width:100%}}
.card{{background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.08);border-radius:14px;padding:24px;text-align:center}}
.card-icon{{font-size:32px;margin-bottom:10px}}
.card-title{{font-size:16px;font-weight:700;color:#f0f6fc;margin-bottom:6px}}
.card-desc{{font-size:13px;color:#8b949e;line-height:1.4}}
</style></head><body>
<div class="title"><span>multi-claude</span> Features</div>
<div class="sub">Everything you need to manage multiple Claude CLI accounts</div>
<div class="grid">
<div class="card"><div class="card-icon">&#x1f512;</div><div class="card-title">Isolated Profiles</div><div class="card-desc">Each account gets its own config directory. No conflicts, no data leaks.</div></div>
<div class="card"><div class="card-icon">&#x1f517;</div><div class="card-title">Shared MCP Servers</div><div class="card-desc">Define MCP servers once, auto-applied to every account on launch.</div></div>
<div class="card"><div class="card-icon">&#x26a1;</div><div class="card-title">Direct Launch</div><div class="card-desc">Type claude-work in any terminal. No menu needed.</div></div>
<div class="card"><div class="card-icon">&#x2601;&#xfe0f;</div><div class="card-title">Cloud Backup</div><div class="card-desc">Sync all profiles to cloud. Restore on any machine with one code.</div></div>
<div class="card"><div class="card-icon">&#x1f50c;</div><div class="card-title">Plugins & Marketplace</div><div class="card-desc">Enable plugins globally or per-account. Browse marketplace indexes.</div></div>
<div class="card"><div class="card-icon">&#x1f4dd;</div><div class="card-title">Global CLAUDE.md</div><div class="card-desc">Write instructions once. Applied across every account automatically.</div></div>
</div>
</body></html>''', 1200, 628)

# ─── Image 12: Before/After Split ───────────────────────────────────────────

capture('12-before-after', f'''<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{background:{GRAD1};width:1200px;height:628px;display:flex;align-items:center;justify-content:center;gap:40px;padding:60px;font-family:{FONT}}}
.panel{{flex:1;border-radius:16px;padding:36px;height:100%}}
.before{{background:rgba(248,81,73,0.06);border:1px solid rgba(248,81,73,0.15)}}
.after{{background:rgba(63,185,80,0.06);border:1px solid rgba(63,185,80,0.15)}}
.label{{font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:3px;margin-bottom:24px}}
.label-red{{color:#f85149}}
.label-green{{color:#3fb950}}
h3{{font-size:22px;color:#f0f6fc;margin-bottom:20px;font-weight:700}}
.item{{display:flex;align-items:center;gap:12px;margin-bottom:14px;font-size:15px}}
.x{{color:#f85149;font-size:18px;flex-shrink:0}}
.check{{color:#3fb950;font-size:18px;flex-shrink:0}}
.text{{color:#c9d1d9}}
.vs{{font-size:36px;color:#484f58;font-weight:800;align-self:center}}
</style></head><body>
<div class="panel before">
<div class="label label-red">WITHOUT multi-claude</div>
<h3>The Pain</h3>
<div class="item"><span class="x">&#x2717;</span><span class="text">Log out, log in every time</span></div>
<div class="item"><span class="x">&#x2717;</span><span class="text">One account at a time</span></div>
<div class="item"><span class="x">&#x2717;</span><span class="text">Reconfigure MCP servers each switch</span></div>
<div class="item"><span class="x">&#x2717;</span><span class="text">CLAUDE.md lost on account change</span></div>
<div class="item"><span class="x">&#x2717;</span><span class="text">No backup or portability</span></div>
<div class="item"><span class="x">&#x2717;</span><span class="text">Settings conflicts between accounts</span></div>
</div>
<div class="vs">VS</div>
<div class="panel after">
<div class="label label-green">WITH multi-claude</div>
<h3>The Fix</h3>
<div class="item"><span class="check">&#x2713;</span><span class="text">Switch instantly, no logout</span></div>
<div class="item"><span class="check">&#x2713;</span><span class="text">Unlimited isolated profiles</span></div>
<div class="item"><span class="check">&#x2713;</span><span class="text">Shared MCP — define once</span></div>
<div class="item"><span class="check">&#x2713;</span><span class="text">Global CLAUDE.md for all accounts</span></div>
<div class="item"><span class="check">&#x2713;</span><span class="text">Cloud backup + one-code restore</span></div>
<div class="item"><span class="check">&#x2713;</span><span class="text">Zero config conflicts</span></div>
</div>
</body></html>''', 1200, 628)

# ─── Image 13: Platform Support ─────────────────────────────────────────────

capture('13-platforms', f'''<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{background:{GRAD2};width:1200px;height:628px;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:60px;font-family:{FONT}}}
.title{{font-size:44px;font-weight:800;color:#f0f6fc;margin-bottom:10px}}
.title span{{color:#58a6ff}}
.sub{{font-size:18px;color:#8b949e;margin-bottom:50px}}
.platforms{{display:flex;gap:32px}}
.plat{{background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.08);border-radius:16px;padding:30px 40px;text-align:center;min-width:160px}}
.plat-icon{{font-size:42px;margin-bottom:12px}}
.plat-name{{font-size:18px;font-weight:700;color:#f0f6fc;margin-bottom:4px}}
.plat-detail{{font-size:13px;color:#8b949e}}
.install{{margin-top:40px;display:flex;gap:16px}}
.pill{{background:rgba(88,166,255,0.1);border:1px solid rgba(88,166,255,0.2);color:#58a6ff;padding:10px 22px;border-radius:24px;font-family:{MONO};font-size:14px}}
</style></head><body>
<div class="title">Works <span>Everywhere</span></div>
<div class="sub">One tool, every platform</div>
<div class="platforms">
<div class="plat"><div class="plat-icon">&#x1f5a5;&#xfe0f;</div><div class="plat-name">Windows</div><div class="plat-detail">PowerShell 5.1+</div></div>
<div class="plat"><div class="plat-icon">&#x1f427;</div><div class="plat-name">Linux</div><div class="plat-detail">Bash 4+</div></div>
<div class="plat"><div class="plat-icon">&#x1f34e;</div><div class="plat-name">macOS</div><div class="plat-detail">Homebrew ready</div></div>
<div class="plat"><div class="plat-icon">&#x1f4f1;</div><div class="plat-name">Termux</div><div class="plat-detail">Android CLI</div></div>
</div>
<div class="install">
<div class="pill">npm</div>
<div class="pill">pip</div>
<div class="pill">brew</div>
<div class="pill">scoop</div>
<div class="pill">AUR</div>
</div>
</body></html>''', 1200, 628)

# ─── Image 14: How It Works Flow ────────────────────────────────────────────

capture('14-how-it-works', f'''<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{background:{GRAD1};width:1200px;height:628px;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:60px;font-family:{FONT}}}
.title{{font-size:42px;font-weight:800;color:#f0f6fc;margin-bottom:40px}}
.title span{{color:#58a6ff}}
.flow{{display:flex;align-items:center;gap:20px}}
.step{{background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.08);border-radius:16px;padding:28px 24px;text-align:center;width:220px}}
.step-num{{background:#58a6ff;color:#0d1117;width:32px;height:32px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:16px;margin:0 auto 12px}}
.step-title{{font-size:16px;font-weight:700;color:#f0f6fc;margin-bottom:6px}}
.step-desc{{font-size:13px;color:#8b949e;line-height:1.4}}
.arrow{{color:#484f58;font-size:28px;font-weight:800}}
</style></head><body>
<div class="title">How <span>multi-claude</span> Works</div>
<div class="flow">
<div class="step"><div class="step-num">1</div><div class="step-title">Pick Account</div><div class="step-desc">Select from menu or type claude-work directly</div></div>
<div class="arrow">&#x2192;</div>
<div class="step"><div class="step-num">2</div><div class="step-title">Settings Merged</div><div class="step-desc">Shared MCP, plugins, CLAUDE.md auto-applied</div></div>
<div class="arrow">&#x2192;</div>
<div class="step"><div class="step-num">3</div><div class="step-title">Claude Launches</div><div class="step-desc">Isolated config, full environment ready</div></div>
<div class="arrow">&#x2192;</div>
<div class="step"><div class="step-num">4</div><div class="step-title">Cloud Sync</div><div class="step-desc">Backup & restore across all your machines</div></div>
</div>
</body></html>''', 1200, 628)

# ─── Image 15: Quick Start / CTA ────────────────────────────────────────────

capture('15-quick-start', f'''<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{background:{GRAD3};width:1200px;height:628px;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:60px;font-family:{FONT};position:relative;overflow:hidden}}
body::before{{content:'';position:absolute;top:-50%;left:-50%;width:200%;height:200%;background:radial-gradient(circle at 50% 40%,rgba(88,166,255,0.08) 0%,transparent 50%),radial-gradient(circle at 70% 70%,rgba(188,140,255,0.06) 0%,transparent 50%)}}
.z{{position:relative;z-index:1;text-align:center}}
.title{{font-size:48px;font-weight:800;color:#f0f6fc;margin-bottom:12px}}
.title span{{color:#58a6ff}}
.sub{{font-size:20px;color:#8b949e;margin-bottom:40px;line-height:1.5}}
.cmd{{background:#0d1117;border:1px solid rgba(255,255,255,0.08);border-radius:12px;padding:20px 40px;font-family:{MONO};font-size:20px;color:#3fb950;margin-bottom:16px;display:inline-block}}
.or{{color:#484f58;font-size:14px;margin-bottom:16px}}
.cmd2{{background:#0d1117;border:1px solid rgba(255,255,255,0.08);border-radius:12px;padding:16px 32px;font-family:{MONO};font-size:16px;color:#8b949e;display:inline-block;margin-bottom:36px}}
.cmd2 span{{color:#58a6ff}}
.links{{display:flex;gap:24px;align-items:center}}
.link{{color:#58a6ff;font-size:15px;text-decoration:none;font-weight:600}}
.dot{{color:#484f58;font-size:12px}}
</style></head><body>
<div class="z">
<div class="title">Get Started in <span>10 Seconds</span></div>
<div class="sub">No config needed. Just install and run.</div>
<div class="cmd">$ npm install -g @ghackk/multi-claude</div>
<div class="or">or pip install multi-claude &bull; brew install ghackk/tap/multi-claude</div>
<div class="cmd2">$ <span>multi-claude</span></div>
<div class="links">
<span class="link">github.com/ghackk/claude-multi-account</span>
<span class="dot">&bull;</span>
<span class="link">npmjs.com/package/@ghackk/multi-claude</span>
<span class="dot">&bull;</span>
<span class="link">pypi.org/project/multi-claude</span>
</div>
</div>
</body></html>''', 1200, 628)

# ─── Image 16: LinkedIn Horizontal Banner ────────────────────────────────────

capture('16-linkedin-banner', f'''<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{background:{GRAD2};width:1200px;height:628px;display:flex;align-items:center;padding:70px;font-family:{FONT};position:relative;overflow:hidden}}
body::before{{content:'';position:absolute;top:0;right:0;bottom:0;width:50%;background:radial-gradient(circle at 80% 50%,rgba(88,166,255,0.05) 0%,transparent 60%)}}
.left{{position:relative;z-index:1;flex:1.2}}
.right{{position:relative;z-index:1;flex:1;display:flex;flex-direction:column;gap:14px}}
.title{{font-size:46px;font-weight:800;color:#f0f6fc;line-height:1.15;margin-bottom:16px}}
.title span{{color:#58a6ff}}
.sub{{font-size:18px;color:#8b949e;line-height:1.5;margin-bottom:24px}}
.install{{font-family:{MONO};font-size:16px;color:#3fb950;background:rgba(63,185,80,0.08);border:1px solid rgba(63,185,80,0.2);padding:12px 20px;border-radius:8px;display:inline-block}}
.feat{{background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.06);border-radius:10px;padding:14px 20px;display:flex;align-items:center;gap:14px}}
.feat-dot{{width:8px;height:8px;border-radius:50%;background:#58a6ff;flex-shrink:0}}
.feat-text{{color:#c9d1d9;font-size:15px}}
</style></head><body>
<div class="left">
<div class="title">Manage multiple<br><span>Claude CLI</span><br>accounts</div>
<div class="sub">Isolated profiles. Shared settings.<br>Cloud backup. One-command launch.</div>
<div class="install">$ npm i -g @ghackk/multi-claude</div>
</div>
<div class="right">
<div class="feat"><div class="feat-dot"></div><div class="feat-text">Isolated config per account</div></div>
<div class="feat"><div class="feat-dot"></div><div class="feat-text">Shared MCP servers & CLAUDE.md</div></div>
<div class="feat"><div class="feat-dot"></div><div class="feat-text">Cloud backup & restore</div></div>
<div class="feat"><div class="feat-dot"></div><div class="feat-text">Direct launch: claude-work</div></div>
<div class="feat"><div class="feat-dot"></div><div class="feat-text">Plugins & marketplace</div></div>
<div class="feat"><div class="feat-dot"></div><div class="feat-text">Windows / Linux / macOS / Termux</div></div>
</div>
</body></html>''', 1200, 628)

print('\nAll extra images done!')

# ─── Generate GIF from existing PNGs ─────────────────────────────────────────
print('\nGenerating animated GIF...')

# Use ImageMagick if available, otherwise ffmpeg
gif_frames = [
    '01-main-menu.png',
    '03-direct-launch.png',
    '02-create-account.png',
    '04-cloud-backup.png',
    '05-shared-settings.png',
    '07-export-profile.png',
    '08-folder-structure.png',
]

gif_path = os.path.join(OUT, 'demo.gif')

# Try ImageMagick
try:
    frame_paths = [os.path.join(OUT, f) for f in gif_frames if os.path.exists(os.path.join(OUT, f))]
    cmd = ['magick', '-delay', '250', '-loop', '0'] + frame_paths + [gif_path]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if os.path.exists(gif_path):
        print(f'  OK  demo.gif ({os.path.getsize(gif_path)//1024} KB) via ImageMagick')
    else:
        raise Exception('magick failed')
except Exception:
    # Try ffmpeg
    try:
        # Create a concat file
        concat = os.path.join(OUT, 'concat.txt')
        with open(concat, 'w') as f:
            for frame in gif_frames:
                fp = os.path.join(OUT, frame)
                if os.path.exists(fp):
                    f.write(f"file '{fp}'\nduration 2.5\n")
            # Last frame needs to be listed again for duration to work
            f.write(f"file '{os.path.join(OUT, gif_frames[-1])}'\n")

        cmd = ['ffmpeg', '-y', '-f', 'concat', '-safe', '0', '-i', concat,
               '-vf', 'scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer',
               '-loop', '0', gif_path]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        os.remove(concat)
        if os.path.exists(gif_path):
            print(f'  OK  demo.gif ({os.path.getsize(gif_path)//1024} KB) via ffmpeg')
        else:
            raise Exception('ffmpeg failed')
    except Exception as e:
        print(f'  GIF generation needs ImageMagick or ffmpeg. Install with:')
        print(f'    winget install ImageMagick.ImageMagick')
        print(f'    OR: winget install Gyan.FFmpeg')
        print(f'  Then re-run this script.')
