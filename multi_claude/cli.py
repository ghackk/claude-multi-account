"""CLI entry point for claude-multi (pip install)."""
import os
import sys
import subprocess
import platform

REPO = "https://github.com/ghackk/claude-multi-account.git"
INSTALL_DIR = os.path.join(os.path.expanduser("~"), "claude-multi-account")


def ensure_installed():
    """Clone the repo on first run if not already present."""
    if os.path.isdir(os.path.join(INSTALL_DIR, "unix")):
        return
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


def main():
    ensure_installed()

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
