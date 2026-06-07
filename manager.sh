#!/bin/sh
set -e
cd "$(dirname "$0")"

MODULE_DIR="magisk_modules/dkms-manager"
OUTPUT_DIR="output"

mkdir -p "$OUTPUT_DIR"
VERSION=$(grep '^version=' "$MODULE_DIR/module.prop" | cut -d= -f2)
OUTFILE="$OUTPUT_DIR/dkms-manager-${VERSION}.zip"
rm -f "$OUTFILE"

echo "Packaging $OUTFILE ..."
(cd "$MODULE_DIR" && zip -r "../../$OUTFILE" . -x '*.git*')

echo "Done: $OUTFILE ($(du -h "$OUTFILE" | cut -f1))"
