#!/bin/sh
set -e
cd "$(dirname "$0")"

INPUT="$1"
KERNEL_VERSION="$2"
if [ -z "$INPUT" ] || [ ! -f "$INPUT" ] || [ -z "$KERNEL_VERSION" ]; then
    echo "Usage: $0 <input-header.tar.gz> <kernel-version>"
    echo "Example: $0 headers.tar.gz 6.12.58-android16-6-g376529f3e739-ab15072794-4k"
    exit 1
fi

MODULE_DIR="magisk_modules/dkms-headers"
OUTPUT_DIR="output"

echo "KERNEL_VERSION=$KERNEL_VERSION" > "$MODULE_DIR/header.cfg"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Unpacking headers ..."
tar -xzf "$INPUT" -C "$TMPDIR"

echo "Wrapping ELF binaries ..."
sh wrapelf.sh "$TMPDIR"

echo "Repacking header.tar.gz ..."
tar -czf "$MODULE_DIR/header.tar.gz" -C "$TMPDIR" .

mkdir -p "$OUTPUT_DIR"
VERSION=$(grep '^version=' "$MODULE_DIR/module.prop" | cut -d= -f2)
OUTFILE="$OUTPUT_DIR/dkms-headers-${VERSION}.zip"
rm -f "$OUTFILE"

echo "Packaging $OUTFILE ..."
(cd "$MODULE_DIR" && zip -r "../../$OUTFILE" . -x '*.git*')

echo "Done: $OUTFILE ($(du -h "$OUTFILE" | cut -f1))"
