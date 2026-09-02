#!/usr/bin/env bash
# §48 Phase 11 — reproducible Web build (custom portal shell included).
# Output: web-export/ (~10.9 MB gz transfer; raw wasm ~39 MB — portals
# serve brotli/gzip, the §19-relevant number is the COMPRESSED transfer).
# Templates must be installed at
#   ~/.local/share/godot/export_templates/4.7.2.stable/  (web_*.zip set).
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . --import
godot --headless --path . --export-release "Web"
echo "---- artifacts ----"
ls -la web-export/
python3 - <<'PY'
import gzip, os
total = 0
for f in sorted(os.listdir("web-export")):
    p = os.path.join("web-export", f)
    raw = os.path.getsize(p)
    with open(p, "rb") as fh:
        gz = len(gzip.compress(fh.read(), 6))
    total += gz
    print(f"{f:34s} raw {raw/1048576:7.2f} MB  gz {gz/1048576:7.2f} MB")
print(f"{'TRANSFER TOTAL (gz)':34s} {total/1048576:7.2f} MB  (budget 25 MB)")
PY
