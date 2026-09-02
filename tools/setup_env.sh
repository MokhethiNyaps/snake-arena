#!/usr/bin/env bash
# =============================================================================
# CoilClash (Snake Arena) — sandbox environment bootstrap.
#
# The dev sandbox does NOT persist files outside /home/user, so the Godot
# engine binary (installed under /opt) must be re-fetched whenever a fresh
# sandbox starts. This script is idempotent and restores everything:
#
#   1. Godot 4.7.2 (official Linux x86_64 binary)  -> /opt/godot472/godot
#   2. Xvfb + Mesa (llvmpipe) for rendered runs + screenshots without a GPU
#   3. symlink: /usr/local/bin/godot
#
# Usage:  bash tools/setup_env.sh
# See docs/ENVIRONMENT.md for full environment details.
# =============================================================================

set -euo pipefail

GODOT_VERSION="4.7.2"
GODOT_TAG="${GODOT_VERSION}-stable"
GODOT_DIR="/opt/godot472"
GODOT_BIN="${GODOT_DIR}/godot"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_TAG}/Godot_v${GODOT_TAG}_linux.x86_64.zip"

echo "[setup_env] Checking Godot ${GODOT_VERSION}..."

if [ ! -x "${GODOT_BIN}" ]; then
    echo "[setup_env] Godot binary missing — downloading (~78 MB)..."
    TMP_ZIP="$(mktemp --suffix=.zip)"
    curl -sL --retry 5 --retry-delay 2 -o "${TMP_ZIP}" "${GODOT_URL}"
    sudo mkdir -p "${GODOT_DIR}"
    (cd "${GODOT_DIR}" && sudo unzip -o "${TMP_ZIP}" > /dev/null)
    sudo mv -f "${GODOT_DIR}/Godot_v${GODOT_TAG}_linux.x86_64" "${GODOT_BIN}"
    sudo chmod +x "${GODOT_BIN}"
    rm -f "${TMP_ZIP}"
fi

sudo ln -sf "${GODOT_BIN}" /usr/local/bin/godot

echo "[setup_env] Checking Xvfb + Mesa software GL..."
if ! command -v Xvfb >/dev/null 2>&1 || ! dpkg -s libgl1-mesa-dri >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq xvfb mesa-utils libgl1-mesa-dri libglx-mesa0 libegl-mesa0
fi

echo "[setup_env] Verifying..."
godot --version
echo "[setup_env] Done. Headless test:  godot --headless --path . --quit"
echo "[setup_env] Rendered test:  xvfb-run -a -s '-screen 0 1280x720x24' godot --path . --resolution 1280x720"

# --- git bootstrap (sandbox note: .git/config is NOT persisted across
# sessions — credential-path exclusion — so the remote + identity must be
# restored every fresh sandbox; credentials remain human-provided, see
# docs/ENVIRONMENT.md §4/§5) ---
cd "$(dirname "$0")/.." 2>/dev/null || true
if [ -d .git ]; then
  git remote get-url origin >/dev/null 2>&1 || git remote add origin https://github.com/MokhethiNyaps/snake-arena.git
  git config user.name >/dev/null 2>&1 || git config user.name "Arena Agent"
  git config user.email >/dev/null 2>&1 || git config user.email "agent@arena.local"
  echo "[git] remote + identity ready (push still needs a human-provided PAT)"
fi
