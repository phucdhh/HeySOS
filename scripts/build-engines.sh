#!/usr/bin/env bash
# =============================================================================
# HeySOS — Build Engine Binaries
# =============================================================================
# Compiles TestDisk/PhotoRec for both arm64 (Apple Silicon) and x86_64 (Intel),
# then creates a Universal Binary (fat binary) using lipo.
#
# Prerequisites:
#   brew install autoconf automake libtool pkg-config e2fsprogs ntfs-3g
#   Xcode Command Line Tools (xcode-select --install)
#
# Usage:
#   chmod +x scripts/build-engines.sh
#   ./scripts/build-engines.sh
#
# Output:
#   HeySOS/Resources/Binaries/photorec  (Universal Binary)
#   HeySOS/Resources/Binaries/testdisk  (Universal Binary)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARIES_DIR="$REPO_ROOT/Sources/Resources/Binaries"
BUILD_DIR="$REPO_ROOT/.build/engines"
TESTDISK_VERSION="7.2"
TESTDISK_TARBALL="testdisk-${TESTDISK_VERSION}.tar.bz2"
TESTDISK_URL="https://www.cgsecurity.org/testdisk-${TESTDISK_VERSION}.tar.bz2"

ARM64_PREFIX="$BUILD_DIR/arm64"
X86_64_PREFIX="$BUILD_DIR/x86_64"

echo "=== HeySOS Engine Builder ==="
echo "TestDisk/PhotoRec version: $TESTDISK_VERSION"
echo "Output: $BINARIES_DIR"
echo ""

# -----------------------------------------------------------------------
# 1. Download source
# -----------------------------------------------------------------------
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -f "$TESTDISK_TARBALL" ]; then
    echo "[1/5] Downloading TestDisk $TESTDISK_VERSION..."
    curl -L -o "$TESTDISK_TARBALL" "$TESTDISK_URL"
else
    echo "[1/5] Tarball already downloaded, skipping."
fi

# -----------------------------------------------------------------------
# 2. Build for arm64 (Apple Silicon)
# -----------------------------------------------------------------------
echo "[2/5] Building for arm64..."
rm -rf "$ARM64_PREFIX/src"
mkdir -p "$ARM64_PREFIX/src"
tar -xjf "$TESTDISK_TARBALL" -C "$ARM64_PREFIX/src" --strip-components=1

cd "$ARM64_PREFIX/src"
./configure \
    CFLAGS="-arch arm64" \
    CXXFLAGS="-arch arm64" \
    LDFLAGS="-arch arm64" \
    --prefix="$ARM64_PREFIX/install" \
    --disable-silent-rules \
    --without-ntfs3g \
    --without-ncurses

make -j"$(sysctl -n hw.ncpu)"
make install

# -----------------------------------------------------------------------
# 3. Build for x86_64 (Intel)
# -----------------------------------------------------------------------
echo "[3/5] Building for x86_64..."
rm -rf "$X86_64_PREFIX/src"
mkdir -p "$X86_64_PREFIX/src"
tar -xjf "$TESTDISK_TARBALL" -C "$X86_64_PREFIX/src" --strip-components=1

cd "$X86_64_PREFIX/src"
./configure \
    CFLAGS="-arch x86_64" \
    CXXFLAGS="-arch x86_64" \
    LDFLAGS="-arch x86_64" \
    CC="clang -target x86_64-apple-macos14.0" \
    CXX="clang++ -target x86_64-apple-macos14.0" \
    --prefix="$X86_64_PREFIX/install" \
    --disable-silent-rules \
    --without-ntfs3g \
    --without-ncurses \
    --host=x86_64-apple-darwin

make -j"$(sysctl -n hw.ncpu)"
make install

# -----------------------------------------------------------------------
# 4. Create Universal Binaries with lipo
# -----------------------------------------------------------------------
echo "[4/5] Creating Universal Binaries..."
mkdir -p "$BINARIES_DIR"

for TOOL in photorec testdisk; do
    ARM_BIN="$ARM64_PREFIX/install/bin/$TOOL"
    X86_BIN="$X86_64_PREFIX/install/bin/$TOOL"
    OUT_BIN="$BINARIES_DIR/$TOOL"

    if [ -f "$ARM_BIN" ] && [ -f "$X86_BIN" ]; then
        lipo -create -output "$OUT_BIN" "$ARM_BIN" "$X86_BIN"
        chmod +x "$OUT_BIN"
        echo "  ✓ $TOOL -> $OUT_BIN"
        lipo -info "$OUT_BIN"
    else
        echo "  ✗ ERROR: Could not find $TOOL binary in one or both build outputs."
        exit 1
    fi
done

# -----------------------------------------------------------------------
# 5. Smoke test
# -----------------------------------------------------------------------
echo "[5/5] Smoke testing binaries..."
"$BINARIES_DIR/photorec" --version 2>&1 | head -2
"$BINARIES_DIR/testdisk" --version 2>&1 | head -2

echo ""
echo "=== Build complete! ==="
echo "Binaries are at: $BINARIES_DIR"
echo ""
echo "Next steps:"
echo "  1. Open HeySOS.xcodeproj in Xcode"
echo "  2. Ensure the binaries are added to the Xcode target's 'Copy Bundle Resources'"
echo "  3. Build and run (⌘R)"
