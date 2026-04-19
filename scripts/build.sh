#!/bin/bash
# shellcheck shell=bash
# tcproxy — release builder.
# Concatenates lib/*.sh into bin/tcproxy in the correct order to produce
# a single self-contained script, replacing the source-time block with
# the inline lib bodies.
#
# Output: ./tcproxy (in the repo root), executable.
#
# Usage:  ./scripts/build.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$REPO_ROOT/lib"
BIN_FILE="$REPO_ROOT/bin/tcproxy"
OUT_FILE="$REPO_ROOT/tcproxy"

# Order matters: each module may reference symbols/vars defined in an
# earlier one.
LIBS=(
    config.sh
    common.sh
    ui.sh
    vm.sh
    mount.sh
    provision.sh
    systemd.sh
    updater.sh
    installer.sh
)

for f in "${LIBS[@]}"; do
    [[ -f "$LIB_DIR/$f" ]] || { echo "[ERROR] missing $LIB_DIR/$f"; exit 1; }
done
[[ -f "$BIN_FILE" ]] || { echo "[ERROR] missing $BIN_FILE"; exit 1; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# 1. Emit the shebang + a provenance header.
{
    echo "#!/bin/bash"
    echo "# tcproxy — single-file release build."
    echo "# Source: https://github.com/leobrigassi/tcproxy"
    echo "# Built: $(date -u +%Y-%m-%dT%H:%M:%SZ) from commit $(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo ""
} > "$TMP"

# 2. Inline each lib, stripping its shebang and shellcheck directive.
for f in "${LIBS[@]}"; do
    {
        echo "# === lib/$f ==="
        # Drop the first line if it is a bash shebang, and drop any top
        # "# shellcheck shell=bash" directive (file-level directives in a
        # concatenated script would be redundant).
        awk 'NR==1 && /^#!\/bin\/bash/ { next }
             NR<=3 && /^# shellcheck shell=bash/ { next }
             { print }' "$LIB_DIR/$f"
        echo ""
    } >> "$TMP"
done

# 3. Append bin/tcproxy with the source-time block stripped.
{
    echo "# === bin/tcproxy dispatcher ==="
    awk '
        /^#!\/bin\/bash/ { next }
        /^# === BEGIN SOURCE-TIME BLOCK/ { skip=1; next }
        /^# === END SOURCE-TIME BLOCK/   { skip=0; next }
        skip { next }
        { print }
    ' "$BIN_FILE"
} >> "$TMP"

# 4. Verify the output parses.
bash -n "$TMP"

mv "$TMP" "$OUT_FILE"
chmod +x "$OUT_FILE"
trap - EXIT

LINES=$(wc -l < "$OUT_FILE")
echo "Built $OUT_FILE ($LINES lines)."
