#!/usr/bin/env bash
# Build MangoHud modified with SHM output for NothingLess notch
#
# Patches MangoHud's overlay.cpp to write FPS data to
# /dev/shm/nothingless_fps every frame, so NothingLess can display
# real-time FPS in the notch metrics overlay.
#
# The patch is inserted right after the fps calculation line in the
# overlay update loop — it runs every frame regardless of whether the
# overlay is visible (uses background_alpha=0 for hidden mode).
set -euo pipefail

MANGOHUD_VERSION="v0.8.3"
MANGOHUD_DIR="/tmp/mangohud-build"
INSTALL_DIR="$HOME/.local/lib"
PATCH_FILE="/tmp/nothingless-mangohud-patch.cpp"

echo "=== Building MangoHud $MANGOHUD_VERSION with NothingLess FPS output ==="

# ── Clone MangoHud source ─────────────────────────────────────────
if [ ! -d "$MANGOHUD_DIR/MangoHud" ]; then
    mkdir -p "$MANGOHUD_DIR"
    git clone --depth 1 --branch "$MANGOHUD_VERSION" \
        https://github.com/flightlessmango/MangoHud.git \
        "$MANGOHUD_DIR/MangoHud"
fi

cd "$MANGOHUD_DIR/MangoHud"

# ── Apply FPS output patch ────────────────────────────────────────
if ! grep -q "nothingless_fps" src/overlay.cpp 2>/dev/null; then
    echo "Applying FPS output patch..."

    # Write the patch snippet to a temp file (avoids fragile sed escaping)
    cat > "$PATCH_FILE" << 'PATCHEOF'
        // Write FPS to /dev/shm/nothingless_fps for NothingLess notch.
        // This runs every frame in the overlay update loop — even when
        // the overlay is hidden (background_alpha=0), the update loop
        // still executes and writes FPS to shared memory.
        FILE *nfps = fopen("/dev/shm/nothingless_fps", "w");
        if (nfps) {
            fprintf(nfps, "fps=%.1f\npid=%d\nframes=%lu\nsource=mangohud\n",
                    sw_stats.fps, getpid(),
                    (unsigned long)sw_stats.n_frames_since_update);
            fclose(nfps);
        }
PATCHEOF

    # Find the line where fps is calculated in the overlay update loop
    LINE=$(grep -n "sw_stats\.fps\s*=" src/overlay.cpp | head -1 | cut -d: -f1)
    if [ -z "$LINE" ]; then
        echo "WARNING: Could not find 'sw_stats.fps =' in overlay.cpp." >&2
        echo "  The MangoHud API may have changed in version $MANGOHUD_VERSION." >&2
        echo "  FPS output to shm will NOT be patched. Build will continue" >&2
        echo "  but nothing-fps will rely on libambfps.so fallback instead." >&2
    else
        # Insert the patch file after the fps calculation line
        sed -i "${LINE}r ${PATCH_FILE}" src/overlay.cpp
        echo "Patch applied after line $LINE."
    fi
    rm -f "$PATCH_FILE"
else
    echo "Patch already applied (nothingless_fps found in source)."
fi

# ── Build ─────────────────────────────────────────────────────────
echo "Building..."
pip3 install --user mako --break-system-packages 2>/dev/null || true

if ! command -v meson &>/dev/null; then
    echo "ERROR: meson is required. Install: sudo pacman -S meson" >&2
    exit 1
fi

meson setup build --buildtype=release --wipe 2>/dev/null || \
    meson setup build --buildtype=release
ninja -C build

# ── Install ───────────────────────────────────────────────────────
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp build/src/libMangoHud.so "$INSTALL_DIR/"
cp build/src/libMangoHud_shim.so "$INSTALL_DIR/"
cp build/src/libMangoHud_opengl.so "$INSTALL_DIR/"
cp build/src/mangohud "$INSTALL_DIR/../bin/mangohud-nothingless" 2>/dev/null || true

echo "✓ Done. Patched MangoHud installed to $INSTALL_DIR"
echo "  Use: nothing-fps %command%  to launch games with FPS in the notch."
