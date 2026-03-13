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


def ensure_path():
    """Make sure the scripts directory is on PATH so `multi-claude` works next time."""
    scripts_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
    if not scripts_dir:
        return

    if platform.system() == "Windows":
        # Check the persistent user PATH from the registry, not the session PATH
        try:
            result = subprocess.run(
                ["powershell", "-Command",
                 '[Environment]::GetEnvironmentVariable("PATH", "User")'],
                capture_output=True, text=True, timeout=5,
            )
            user_path = result.stdout.strip() if result.returncode == 0 else ""
        except Exception:
            return

        user_dirs = [d.lower().rstrip("\\") for d in user_path.split(";") if d]
        if scripts_dir.lower().rstrip("\\") in user_dirs:
            return

        new_path = f"{scripts_dir};{user_path}" if user_path else scripts_dir
        try:
            subprocess.run(
                ["powershell", "-Command",
                 f'[Environment]::SetEnvironmentVariable("PATH", "{new_path}", "User")'],
                capture_output=True, timeout=5,
            )
            print(f"Added {scripts_dir} to PATH. Restart your terminal for the change to take effect.")
        except Exception:
            pass
    else:
        # Linux / macOS — check for ~/.local/bin
        local_bin = os.path.join(pathlib.Path.home(), ".local", "bin")
        current_path = os.environ.get("PATH", "")
        if local_bin in current_path.split(":"):
            return

        line = 'export PATH="$HOME/.local/bin:$PATH"'
        home = pathlib.Path.home()
        added = False
        for rc in [home / ".bashrc", home / ".zshrc"]:
            if not rc.exists():
                continue
            contents = rc.read_text()
            if line in contents:
                continue
            with open(rc, "a") as f:
                f.write(f"\n# Added by multi-claude\n{line}\n")
            added = True

        if added:
            print(f"Added {local_bin} to PATH in shell config. Restart your terminal for the change to take effect.")


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
