#!/bin/sh
set -e
cd "$(dirname "$0")"

TOOLCHAIN_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.0/clang+llvm-19.1.0-aarch64-linux-gnu.tar.xz"
MODULE_DIR="magisk_modules/dkms-toolchain"
OUTPUT_DIR="output"

if [ ! -f "$MODULE_DIR/toolchain.tar.xz" ]; then
    echo "Downloading toolchain (~1.1GB) ..."
    curl -L -C - --progress-bar -o "$MODULE_DIR/toolchain.tar.xz.tmp" "$TOOLCHAIN_URL"
    mv "$MODULE_DIR/toolchain.tar.xz.tmp" "$MODULE_DIR/toolchain.tar.xz"
else
    echo "toolchain.tar.xz already exists, skipping download"
fi

mkdir -p "$OUTPUT_DIR"
VERSION=$(grep '^version=' "$MODULE_DIR/module.prop" | cut -d= -f2)
OUTFILE="$OUTPUT_DIR/dkms-toolchain-${VERSION}.zip"
rm -f "$OUTFILE"

echo "Packaging $OUTFILE ..."
(cd "$MODULE_DIR" && zip -r "../../$OUTFILE" . -x '*.git*')

echo "Done: $OUTFILE ($(du -h "$OUTFILE" | cut -f1))"
