#!/bin/bash
# ─── Release Script — Update all distribution channels at once ───────────────
# Usage: ./release.sh 1.0.1 "Fixed a bug in shared settings sync"

set -e

VERSION="$1"
MESSAGE="$2"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$VERSION" ]; then
    echo -e "\033[31mUsage: ./release.sh <version> [\"release message\"]\033[0m"
    echo "  Example: ./release.sh 1.0.1 \"Fixed shared settings sync\""
    exit 1
fi

[ -z "$MESSAGE" ] && MESSAGE="Release v$VERSION"

echo ""
echo -e "\033[36m======================================\033[0m"
echo -e "\033[36m  Releasing multi-claude v$VERSION    \033[0m"
echo -e "\033[36m======================================\033[0m"
echo ""

cd "$REPO_DIR"

# ─── 1. Update version in all files ─────────────────────────────────────────

echo -e "\033[33m[1/7] Updating version numbers...\033[0m"

# package.json
sed -i "s/\"version\": \".*\"/\"version\": \"$VERSION\"/" package.json

# pyproject.toml
sed -i "s/^version = \".*\"/version = \"$VERSION\"/" pyproject.toml

# Python __init__.py
sed -i "s/__version__ = \".*\"/__version__ = \"$VERSION\"/" multi_claude/__init__.py

echo "  Updated package.json, pyproject.toml, multi_claude/__init__.py"

# ─── 2. Git commit, tag, push ───────────────────────────────────────────────

echo -e "\033[33m[2/7] Committing and tagging...\033[0m"

git add -A
git commit -m "Release v$VERSION" 2>/dev/null || echo "  Nothing to commit"
git tag "v$VERSION"
git push
git push origin "v$VERSION"

echo "  Pushed tag v$VERSION"

# ─── 3. GitHub Release ──────────────────────────────────────────────────────

echo -e "\033[33m[3/7] Creating GitHub release...\033[0m"

gh release create "v$VERSION" \
    --repo ghackk/claude-multi-account \
    --title "v$VERSION" \
    --notes "$MESSAGE"

echo "  Release created"

# ─── 4. npm publish ─────────────────────────────────────────────────────────

echo -e "\033[33m[4/7] Publishing to npm...\033[0m"

npm publish --access=public 2>&1 | tail -3

echo "  npm published"

# ─── 5. pip publish ─────────────────────────────────────────────────────────

echo -e "\033[33m[5/7] Publishing to PyPI...\033[0m"

rm -rf dist/build/ dist/*.whl dist/*.tar.gz build/ *.egg-info multi_claude.egg-info
python -m build 2>&1 | tail -1
python -m twine upload dist/multi_claude-${VERSION}* 2>&1 | tail -3

echo "  PyPI published"

# ─── 6. Update Homebrew tap ─────────────────────────────────────────────────

echo -e "\033[33m[6/7] Updating Homebrew tap...\033[0m"

TARBALL_SHA=$(curl -fsSL "https://github.com/ghackk/claude-multi-account/archive/refs/tags/v${VERSION}.tar.gz" | sha256sum | cut -d' ' -f1)

HOMEBREW_DIR="$HOME/homebrew-tap"
if [ ! -d "$HOMEBREW_DIR" ]; then
    git clone https://github.com/ghackk/homebrew-tap.git "$HOMEBREW_DIR"
fi
cd "$HOMEBREW_DIR"
git pull

cat > Formula/multi-claude.rb << ENDRUBY
class MultiClaude < Formula
  desc "Run multiple Claude CLI accounts with shared settings and plugins"
  homepage "https://github.com/ghackk/claude-multi-account"
  url "https://github.com/ghackk/claude-multi-account/archive/refs/tags/v${VERSION}.tar.gz"
  sha256 "${TARBALL_SHA}"
  license "MIT"

  head "https://github.com/ghackk/claude-multi-account.git", branch: "master"

  def install
    libexec.install Dir["*"]
    (bin/"multi-claude").write_env_script libexec/"unix/claude-menu.sh"
  end

  test do
    assert_predicate bin/"multi-claude", :exist?
  end
end
ENDRUBY

git add -A
git commit -m "Update multi-claude to v$VERSION"
git push

cd "$REPO_DIR"
echo "  Homebrew tap updated"

# ─── 7. Update Scoop bucket ─────────────────────────────────────────────────

echo -e "\033[33m[7/7] Updating Scoop bucket...\033[0m"

ZIP_SHA=$(curl -fsSL "https://github.com/ghackk/claude-multi-account/archive/refs/tags/v${VERSION}.zip" | sha256sum | cut -d' ' -f1)

SCOOP_DIR="$HOME/scoop-multi-claude"
if [ ! -d "$SCOOP_DIR" ]; then
    git clone https://github.com/ghackk/scoop-multi-claude.git "$SCOOP_DIR"
fi
cd "$SCOOP_DIR"
git pull

cat > bucket/multi-claude.json << ENDJSON
{
    "version": "${VERSION}",
    "description": "Run multiple Claude CLI accounts with shared settings, plugins, and backup/restore",
    "homepage": "https://github.com/ghackk/claude-multi-account",
    "license": "MIT",
    "url": "https://github.com/ghackk/claude-multi-account/archive/refs/tags/v${VERSION}.zip",
    "hash": "${ZIP_SHA}",
    "extract_dir": "claude-multi-account-${VERSION}",
    "bin": "claude-menu.bat",
    "shortcuts": [
        ["claude-menu.bat", "Claude Multi-Account"]
    ],
    "checkver": "github",
    "autoupdate": {
        "url": "https://github.com/ghackk/claude-multi-account/archive/refs/tags/v\$version.zip",
        "extract_dir": "claude-multi-account-\$version"
    }
}
ENDJSON

git add -A
git commit -m "Update multi-claude to v$VERSION"
git push

cd "$REPO_DIR"
echo "  Scoop bucket updated"

# ─── Done ────────────────────────────────────────────────────────────────────

echo ""
echo -e "\033[32m======================================\033[0m"
echo -e "\033[32m  v$VERSION released everywhere!      \033[0m"
echo -e "\033[32m======================================\033[0m"
echo ""
echo "  npm:      @ghackk/multi-claude@$VERSION"
echo "  pip:      multi-claude $VERSION"
echo "  brew:     ghackk/tap/multi-claude $VERSION"
echo "  scoop:    multi-claude $VERSION"
echo "  GitHub:   v$VERSION"
echo ""
