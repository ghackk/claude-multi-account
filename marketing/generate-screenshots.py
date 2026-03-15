"""Generate screenshot PNGs from HTML templates using Edge headless."""
import subprocess, os, time

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
OUT = os.path.join(os.path.dirname(__file__), "images")
os.makedirs(OUT, exist_ok=True)

STYLE = """
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { background: transparent; display: inline-block; }
.terminal {
  width: 720px;
  background: #0d1117;
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 20px 60px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.05);
}
.titlebar {
  background: #161b22;
  padding: 12px 16px;
  display: flex;
  align-items: center;
  gap: 8px;
}
.dot { width: 12px; height: 12px; border-radius: 50%; }
.dot.red { background: #ff5f57; }
.dot.yellow { background: #febc2e; }
.dot.green { background: #28c840; }
.titlebar-text { color: #8b949e; font-size: 13px; margin-left: auto; margin-right: auto; font-family: 'Cascadia Code', 'Consolas', monospace; }
.content {
  padding: 20px 24px 24px;
  font-family: 'Cascadia Code', 'Consolas', monospace;
  font-size: 14px;
  line-height: 1.6;
  color: #e6edf3;
  white-space: pre;
}
.cyan { color: #58a6ff; }
.green { color: #3fb950; }
.yellow { color: #d29922; }
.gray { color: #8b949e; }
.red { color: #f85149; }
.magenta { color: #bc8cff; }
.white { color: #f0f6fc; }
.prompt { color: #3fb950; }
.cmd { color: #f0f6fc; }
</style>
"""

BANNER_STYLE = """
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { background: transparent; display: inline-block; }
.banner {
  width: 1280px; height: 640px;
  background: linear-gradient(135deg, #0d1117 0%, #161b22 40%, #1c2333 100%);
  border-radius: 16px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 60px;
  position: relative;
  overflow: hidden;
}
.banner::before {
  content: '';
  position: absolute;
  top: -50%; left: -50%;
  width: 200%; height: 200%;
  background: radial-gradient(circle at 50% 50%, rgba(88,166,255,0.06) 0%, transparent 40%);
}
.gh-title {
  position: relative; z-index: 1;
  font-family: 'Segoe UI', sans-serif;
  font-size: 64px;
  font-weight: 800;
  color: #f0f6fc;
  margin-bottom: 16px;
  text-align: center;
}
.gh-title span { color: #58a6ff; }
.gh-sub {
  position: relative; z-index: 1;
  font-family: 'Segoe UI', sans-serif;
  font-size: 24px;
  color: #8b949e;
  text-align: center;
  margin-bottom: 40px;
  max-width: 900px;
  line-height: 1.4;
}
.gh-features {
  position: relative; z-index: 1;
  display: flex;
  gap: 28px;
  flex-wrap: wrap;
  justify-content: center;
}
.gh-feature {
  background: rgba(255,255,255,0.03);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 12px;
  padding: 16px 24px;
  text-align: center;
}
.gh-feature-icon { font-size: 28px; margin-bottom: 8px; }
.gh-feature-text { color: #c9d1d9; font-family: 'Segoe UI', sans-serif; font-size: 15px; font-weight: 500; }
</style>
"""

TWITTER_STYLE = """
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { background: transparent; display: inline-block; }
.banner {
  width: 1200px; height: 628px;
  background: linear-gradient(135deg, #0d1117 0%, #161b22 50%, #1a1f2e 100%);
  border-radius: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 60px;
  padding: 60px;
  position: relative;
  overflow: hidden;
}
.banner::before {
  content: '';
  position: absolute;
  top: -50%; left: -50%;
  width: 200%; height: 200%;
  background: radial-gradient(circle at 30% 40%, rgba(88,166,255,0.08) 0%, transparent 50%),
              radial-gradient(circle at 70% 60%, rgba(188,140,255,0.06) 0%, transparent 50%);
}
.left { position: relative; z-index: 1; flex: 1; }
.right { position: relative; z-index: 1; flex: 1; }
.title {
  font-family: 'Segoe UI', sans-serif;
  font-size: 52px;
  font-weight: 800;
  color: #f0f6fc;
  line-height: 1.15;
  margin-bottom: 20px;
}
.title span { color: #58a6ff; }
.subtitle {
  font-family: 'Segoe UI', sans-serif;
  font-size: 20px;
  color: #8b949e;
  line-height: 1.5;
  margin-bottom: 30px;
}
.badges { display: flex; gap: 12px; flex-wrap: wrap; }
.badge {
  background: rgba(88,166,255,0.1);
  border: 1px solid rgba(88,166,255,0.2);
  color: #58a6ff;
  padding: 8px 16px;
  border-radius: 20px;
  font-family: 'Cascadia Code', 'Consolas', monospace;
  font-size: 13px;
}
.mini-terminal {
  background: #0d1117;
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 20px 60px rgba(0,0,0,0.4), 0 0 0 1px rgba(255,255,255,0.05);
  width: 480px;
}
.mini-titlebar {
  background: #161b22;
  padding: 10px 14px;
  display: flex;
  align-items: center;
  gap: 6px;
}
.d { width: 10px; height: 10px; border-radius: 50%; }
.d.r { background: #ff5f57; }
.d.y { background: #febc2e; }
.d.g { background: #28c840; }
.mini-content {
  padding: 16px 20px;
  font-family: 'Cascadia Code', 'Consolas', monospace;
  font-size: 13px;
  line-height: 1.6;
  color: #e6edf3;
  white-space: pre;
}
.c { color: #58a6ff; }
.g2 { color: #3fb950; }
.gr { color: #8b949e; }
.w { color: #f0f6fc; }
</style>
"""

def titlebar(text="multi-claude"):
    return f'''<div class="titlebar"><div class="dot red"></div><div class="dot yellow"></div><div class="dot green"></div><span class="titlebar-text">{text}</span></div>'''

screenshots = {
    # Terminal screenshots
    "01-main-menu": {
        "style": STYLE,
        "body": f'''<div class="terminal">{titlebar()}<div class="content"><span class="cyan">======================================</span>
<span class="cyan">       Claude Account Manager         </span>
<span class="cyan">======================================</span>

  <span class="white">Current Accounts:</span>

  <span class="white">1. claude-work     </span><span class="green">[logged in]</span><span class="gray">  (last used: 14 Mar 2026 03:21 PM)</span>
  <span class="white">2. claude-personal </span><span class="green">[logged in]</span><span class="gray">  (last used: 13 Mar 2026 05:11 PM)</span>
  <span class="white">3. claude-client   </span><span class="green">[logged in]</span><span class="gray">  (last used: 13 Mar 2026 09:29 PM)</span>
  <span class="white">4. claude-dev      </span><span class="green">[logged in]</span><span class="gray">  (last used: 14 Mar 2026 01:51 PM)</span>

<span class="cyan">======================================</span>
  <span class="white">1.</span> List Accounts
  <span class="white">2.</span> Create New Account
  <span class="white">3.</span> Launch Account
  <span class="white">4.</span> Rename Account
  <span class="white">5.</span> Delete Account
  <span class="white">6.</span> Backup Sessions (Local)
  <span class="white">7.</span> Restore Sessions (Local)
  <span class="white">8.</span> Shared Settings (MCP/Skills)
  <span class="white">9.</span> Plugins &amp; Marketplace
  <span class="white">E.</span> Export Profile (Token)
  <span class="white">I.</span> Import Profile (Token)
  <span class="white">C.</span> Cloud Backup
  <span class="white">R.</span> Cloud Restore
  <span class="white">H.</span> Help
  <span class="white">0.</span> Exit
<span class="cyan">======================================</span>
  <span class="yellow">Choose: </span><span class="white">_</span></div></div>'''
    },

    "02-create-account": {
        "style": STYLE,
        "body": f'''<div class="terminal">{titlebar("Create Account")}<div class="content"><span class="cyan">======================================</span>
<span class="cyan">       Claude Account Manager         </span>
<span class="cyan">======================================</span>

<span class="magenta">CREATE NEW ACCOUNT</span>

  <span class="cyan">Account name (letters, numbers, hyphens): </span><span class="white">client-acme</span>

  <span class="green">Account created: claude-client-acme</span>
  <span class="gray">Config dir:  ~/.claude-client-acme</span>
  <span class="gray">Launcher:    ~/claude-accounts/claude-client-acme.sh</span>
  <span class="green">Registered on PATH: claude-client-acme</span>

  <span class="cyan">Shared settings synced.</span>

  <span class="yellow">Launch now? (y/n): </span><span class="white">_</span></div></div>'''
    },

    "03-direct-launch": {
        "style": STYLE,
        "body": f'''<div class="terminal">{titlebar("Terminal")}<div class="content"><span class="prompt">~$</span> <span class="cmd">claude-work</span>
<span class="gray">Loading Claude CLI with profile: claude-work</span>
<span class="cyan">Claude Code v1.0.38</span>
<span class="white">How can I help you today?</span>

<span class="prompt">~$</span> <span class="cmd">claude-personal</span>
<span class="gray">Loading Claude CLI with profile: claude-personal</span>
<span class="cyan">Claude Code v1.0.38</span>
<span class="white">How can I help you today?</span>

<span class="prompt">~$</span> <span class="gray"># No menu needed - just type the profile name!</span></div></div>'''
    },

    "04-cloud-backup": {
        "style": STYLE,
        "body": f'''<div class="terminal">{titlebar("Cloud Backup")}<div class="content"><span class="magenta">REMOTE SESSION BACKUP</span>
  <span class="gray">Server limit: 50 MB</span>

  <span class="cyan">Selected: claude-work claude-personal claude-client claude-dev</span>

  <span class="cyan">-- Size Breakdown --</span>

  <span class="green">ALWAYS INCLUDED:</span>
    Credentials + Settings         0.02 MB
    Launchers                      0.01 MB
    Shared settings                0.03 MB

  <span class="yellow">OPTIONAL (included by default):</span>
    session-env                    0.01 MB
    plans                          0.02 MB

  <span class="gray">Building backup...</span>
  <span class="gray">Generating profile tokens...</span>
  <span class="gray">Compressed: 0.04 MB</span>
  <span class="gray">Uploading (0.04 MB)...</span>

  <span class="green">+----------------------------------+</span>
  <span class="green">|  BACKUP CODE:   X3EAK-HPAVLD     |</span>
  <span class="green">+----------------------------------+</span>

  <span class="cyan">Profiles: 4</span>
  <span class="gray">Size: 0.04 MB</span>
  <span class="yellow">Code expires in 10 minutes. Save it!</span>

  <span class="green">Code copied to clipboard!</span></div></div>'''
    },

    "05-shared-settings": {
        "style": STYLE,
        "body": f'''<div class="terminal">{titlebar("Shared Settings")}<div class="content"><span class="cyan">======================================</span>
<span class="cyan">       Claude Account Manager         </span>
<span class="cyan">======================================</span>

<span class="magenta">SHARED SETTINGS (MCP / Skills)</span>
<span class="gray">Define once - applied to ALL accounts on launch</span>

  <span class="white">1.</span> Edit MCP + Settings <span class="gray">(opens in editor)</span>
  <span class="white">2.</span> Edit Skills / Instructions <span class="gray">(CLAUDE.md)</span>
  <span class="white">3.</span> View current shared settings
  <span class="white">4.</span> Sync shared settings to ALL accounts
  <span class="white">5.</span> Show MCP server list
  <span class="white">6.</span> Reset shared settings
  <span class="white">0.</span> Back

<span class="cyan">======================================</span>
  <span class="yellow">Choose: </span><span class="white">_</span></div></div>'''
    },

    "06-install": {
        "style": STYLE,
        "body": f'''<div class="terminal">{titlebar("Install multi-claude")}<div class="content"><span class="gray"># npm</span>
<span class="prompt">$</span> <span class="cmd">npm install -g @ghackk/multi-claude</span>

<span class="gray"># pip</span>
<span class="prompt">$</span> <span class="cmd">pip install multi-claude</span>

<span class="gray"># Homebrew (macOS / Linux)</span>
<span class="prompt">$</span> <span class="cmd">brew install ghackk/tap/multi-claude</span>

<span class="gray"># Scoop (Windows)</span>
<span class="prompt">$</span> <span class="cmd">scoop install multi-claude</span>

<span class="gray"># One-liner (Linux / macOS)</span>
<span class="prompt">$</span> <span class="cmd">curl -fsSL https://raw.githubusercontent.com/ghackk/claude-multi-account/master/install.sh | bash</span>

<span class="gray"># Then just run:</span>
<span class="prompt">$</span> <span class="cmd">multi-claude</span></div></div>'''
    },

    "07-export-profile": {
        "style": STYLE,
        "body": f'''<div class="terminal">{titlebar("Export Profile")}<div class="content"><span class="cyan">======================================</span>
<span class="cyan">       Claude Account Manager         </span>
<span class="cyan">======================================</span>

<span class="magenta">EXPORT PROFILE (Token)</span>

  1. claude-work     <span class="green">[logged in]</span>
  2. claude-personal <span class="green">[logged in]</span>
  3. claude-client   <span class="green">[logged in]</span>
  4. claude-dev      <span class="green">[logged in]</span>

  <span class="cyan">Pick account number to export: </span><span class="white">1</span>

  <span class="gray">Building token...</span>

  <span class="cyan">Profile: claude-dalvoy</span>
  <span class="gray">Token length: 4832 characters</span>

  <span class="green">Token copied to clipboard!</span>
  <span class="gray">Paste on another machine using Import (option I)</span></div></div>'''
    },

    "08-folder-structure": {
        "style": STYLE,
        "body": f'''<div class="terminal">{titlebar("How It Works")}<div class="content"><span class="prompt">$</span> <span class="cmd">tree ~/</span>
<span class="cyan">~/</span>
<span class="white">|-- claude-accounts/</span>            <span class="gray"># Launchers (auto-created)</span>
<span class="white">|   |-- claude-work.sh</span>          <span class="gray"># symlinked to ~/.local/bin/claude-work</span>
<span class="white">|   |-- claude-personal.sh</span>
<span class="white">|   +-- claude-client.sh</span>
<span class="white">|</span>
<span class="white">|-- claude-shared/</span>              <span class="gray"># Shared config (applied to ALL)</span>
<span class="white">|   |-- settings.json</span>           <span class="gray"># MCP servers, env vars</span>
<span class="white">|   +-- CLAUDE.md</span>               <span class="gray"># Global instructions</span>
<span class="white">|</span>
<span class="white">|-- .claude-work/</span>               <span class="gray"># Isolated: work account</span>
<span class="white">|-- .claude-personal/</span>           <span class="gray"># Isolated: personal account</span>
<span class="white">+-- .claude-client/</span>             <span class="gray"># Isolated: client account</span>

<span class="green">Each account = isolated config directory</span>
<span class="green">Shared settings = deep-merged on every launch</span>
<span class="green">Direct launch = just type the profile name</span></div></div>'''
    },
}

banners = {
    "09-twitter-card": {
        "style": TWITTER_STYLE,
        "width": 1200, "height": 628,
        "body": '''<div class="banner">
  <div class="left">
    <div class="title"><span>multi-claude</span></div>
    <div class="subtitle">Manage multiple Claude CLI accounts<br>with shared settings, cloud backup,<br>and one-command launch.</div>
    <div class="badges">
      <div class="badge">npm</div>
      <div class="badge">pip</div>
      <div class="badge">brew</div>
      <div class="badge">scoop</div>
    </div>
  </div>
  <div class="right">
    <div class="mini-terminal">
      <div class="mini-titlebar">
        <div class="d r"></div>
        <div class="d y"></div>
        <div class="d g"></div>
      </div>
      <div class="mini-content"><span class="c">==============================</span>
<span class="c">   Claude Account Manager</span>
<span class="c">==============================</span>

  <span class="w">1. claude-work</span>     <span class="g2">[logged in]</span>
  <span class="w">2. claude-personal</span> <span class="g2">[logged in]</span>
  <span class="w">3. claude-client</span>   <span class="g2">[logged in]</span>

<span class="gr">$ claude-work</span>  <span class="gr"># direct launch!</span></div>
    </div>
  </div>
</div>'''
    },

    "10-github-social": {
        "style": BANNER_STYLE,
        "width": 1280, "height": 640,
        "body": '''<div class="banner">
  <div class="gh-title"><span>claude-multi-account</span></div>
  <div class="gh-sub">Run multiple Claude CLI accounts with shared settings, plugins, cloud backup, and one-command launch.</div>
  <div class="gh-features">
    <div class="gh-feature"><div class="gh-feature-icon">&#x1f465;</div><div class="gh-feature-text">Isolated Profiles</div></div>
    <div class="gh-feature"><div class="gh-feature-icon">&#x1f517;</div><div class="gh-feature-text">Shared MCP</div></div>
    <div class="gh-feature"><div class="gh-feature-icon">&#x2601;&#xfe0f;</div><div class="gh-feature-text">Cloud Sync</div></div>
    <div class="gh-feature"><div class="gh-feature-icon">&#x26a1;</div><div class="gh-feature-text">Direct Launch</div></div>
    <div class="gh-feature"><div class="gh-feature-icon">&#x1f50c;</div><div class="gh-feature-text">Plugins</div></div>
    <div class="gh-feature"><div class="gh-feature-icon">&#x1f4e6;</div><div class="gh-feature-text">npm / pip / brew</div></div>
  </div>
</div>'''
    },
}

def render(name, data, is_banner=False):
    html_path = os.path.join(OUT, f"{name}.html")
    png_path = os.path.join(OUT, f"{name}.png")
    w = data.get("width", 800)
    h = data.get("height", 900)

    html = f'''<!DOCTYPE html><html><head><meta charset="UTF-8">{data["style"]}</head><body>{data["body"]}</body></html>'''
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html)

    # Use Windows-style paths for Edge
    png_path_win = png_path.replace("/", "\\")
    html_path_win = html_path.replace("/", "\\")
    file_url = "file:///" + html_path.replace("\\", "/")
    cmd = [
        EDGE,
        "--headless",
        "--disable-gpu",
        f"--screenshot={png_path_win}",
        f"--window-size={w},{h}",
        "--hide-scrollbars",
        file_url
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    time.sleep(1)
    if os.path.exists(png_path):
        size = os.path.getsize(png_path)
        print(f"  OK  {name}.png ({size//1024} KB)")
    else:
        print(f"  FAIL {name}.png")
        print(f"    stderr: {result.stderr[:200] if result.stderr else 'none'}")
        print(f"    html exists: {os.path.exists(html_path)}")
        print(f"    html_path: {html_path}")
        print(f"    png_path: {png_path}")

print("Generating terminal screenshots...")
for name, data in screenshots.items():
    render(name, data)

print("\nGenerating banners...")
for name, data in banners.items():
    render(name, data, is_banner=True)

print("\nDone! Images saved to:", OUT)
