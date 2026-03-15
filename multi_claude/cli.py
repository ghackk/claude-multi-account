"""CLI entry point for multi-claude (pip install)."""
import os
import sys
import subprocess
import platform
import pathlib

REPO = "https://github.com/ghackk/claude-multi-account.git"
INSTALL_DIR = os.path.join(os.path.expanduser("~"), "claude-multi-account")


def ensure_installed():
    """Clone the repo on first run, pull updates if already present."""
    if os.path.isdir(os.path.join(INSTALL_DIR, ".git")):
        # Auto-update on each run (silent, non-blocking)
        try:
            subprocess.run(
                ["git", "-C", INSTALL_DIR, "pull", "--quiet"],
                timeout=10,
                capture_output=True,
            )
        except Exception:
            pass  # Offline or timeout — run with existing version
        return

    if os.path.isdir(os.path.join(INSTALL_DIR, "unix")):
        return  # Downloaded via archive, no git

    print("First run — downloading claude-multi-account...")
    try:
        subprocess.run(["git", "clone", "--quiet", REPO, INSTALL_DIR], check=True)
        print("Downloaded!")
    except FileNotFoundError:
        print("Error: git is required. Install git and try again.")
        sys.exit(1)
    except subprocess.CalledProcessError:
        print("Error: failed to clone repository.")
        sys.exit(1)


def _find_scripts_dirs():
    """Find all possible Python Scripts directories where pip puts entry points."""
    import sysconfig
    dirs = set()

    # 1. Where this script is actually running from
    if sys.argv[0]:
        dirs.add(os.path.dirname(os.path.abspath(sys.argv[0])))

    # 2. sysconfig schemes — covers standard, user, venv installs
    for scheme in sysconfig.get_scheme_names():
        try:
            d = sysconfig.get_path("scripts", scheme)
            if d and os.path.isdir(d):
                dirs.add(d)
        except (KeyError, AttributeError):
            pass

    # 3. User scripts dir (pip install --user) — works for all Python installs
    try:
        dirs.add(sysconfig.get_path("scripts", f"{os.name}_user"))
    except (KeyError, AttributeError):
        pass

    # 4. Same dir as python executable (some embeddable/store installs)
    dirs.add(os.path.dirname(sys.executable))

    # 5. site.getusersitepackages() → swap site-packages for Scripts/bin
    try:
        import site
        user_site = site.getusersitepackages()
        if user_site:
            if platform.system() == "Windows":
                dirs.add(os.path.join(os.path.dirname(user_site), "Scripts"))
            else:
                dirs.add(os.path.join(os.path.dirname(user_site), "bin"))
    except Exception:
        pass

    # Filter to only dirs that actually exist and aren't empty
    return {d for d in dirs if d and os.path.isdir(d)}


def ensure_path():
    """Make sure the scripts directory is on PATH so `multi-claude` works next time."""
    scripts_dirs = _find_scripts_dirs()
    if not scripts_dirs:
        return

    if platform.system() == "Windows":
        # Read the persistent user PATH from the registry
        try:
            result = subprocess.run(
                ["powershell", "-Command",
                 '[Environment]::GetEnvironmentVariable("PATH", "User")'],
                capture_output=True, text=True, timeout=5,
            )
            user_path = result.stdout.strip() if result.returncode == 0 else ""
        except Exception:
            return

        user_dirs = {d.lower().rstrip("\\") for d in user_path.split(";") if d}
        # Also check system PATH so we don't add dirs that are already there
        sys_path = os.environ.get("PATH", "")
        all_dirs = user_dirs | {d.lower().rstrip("\\") for d in sys_path.split(";") if d}

        missing = []
        for d in scripts_dirs:
            if d.lower().rstrip("\\") not in all_dirs:
                missing.append(d)

        if not missing:
            return

        new_path = ";".join(missing) + ";" + user_path if user_path else ";".join(missing)
        try:
            # Escape for PowerShell — single quotes to avoid variable expansion
            escaped = new_path.replace("'", "''")
            subprocess.run(
                ["powershell", "-Command",
                 f"[Environment]::SetEnvironmentVariable('PATH', '{escaped}', 'User')"],
                capture_output=True, timeout=5,
            )
            for d in missing:
                print(f"Added {d} to PATH.")
            print("Restart your terminal for the change to take effect.")
        except Exception:
            pass
    else:
        # Linux / macOS
        local_bin = os.path.join(pathlib.Path.home(), ".local", "bin")
        current_path = os.environ.get("PATH", "").split(":")

        # Check all scripts dirs + ~/.local/bin
        need_dirs = {local_bin} | scripts_dirs
        all_missing = [d for d in need_dirs if d not in current_path]
        if not all_missing:
            return

        line = 'export PATH="$HOME/.local/bin:$PATH"'
        home = pathlib.Path.home()
        added = False
        for rc in [home / ".bashrc", home / ".zshrc"]:
            if not rc.exists():
                continue
            contents = rc.read_text()
            if ".local/bin" in contents:
                continue
            with open(rc, "a") as f:
                f.write(f"\n# Added by multi-claude\n{line}\n")
            added = True

        if added:
            print(f"Added ~/.local/bin to PATH in shell config. Restart your terminal for the change to take effect.")


def main():
    ensure_installed()
    ensure_path()

    if platform.system() == "Windows":
        script = os.path.join(INSTALL_DIR, "claude-menu.ps1")
        result = subprocess.run(
            ["powershell", "-ExecutionPolicy", "Bypass", "-File", script]
        )
    else:
        script = os.path.join(INSTALL_DIR, "unix", "claude-menu.sh")
        os.chmod(script, 0o755)
        result = subprocess.run(["bash", script])

    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
