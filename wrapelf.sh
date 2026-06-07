#!/bin/sh
# wrapelf.sh - Wrap glibc-linked ELF binaries in kernel headers for Android
# Run on host BEFORE packaging the dkms-headers module
#
# Usage: ./wrapelf.sh <header_dir> [sysroot_path]

set -e

HEADER_DIR="$1"
SYSROOT="${2:-/data/adb/modules/dkms-toolchain/clang+llvm-19.1.0-aarch64-linux-gnu/sysroot}"
LOADER="$SYSROOT/ld-linux-aarch64.so.1"

if [ -z "$HEADER_DIR" ] || [ ! -d "$HEADER_DIR" ]; then
    echo "Usage: $0 <header_dir> [sysroot_path_on_device]"
    exit 1
fi

count=0

find "$HEADER_DIR" -type f ! -name '*.real' | while read -r f; do
    head -c 4 "$f" 2>/dev/null | grep -q "ELF" || continue

    # Skip if already wrapped
    [ -f "${f}.real" ] && continue

    # Get the path as it will appear on device
    rel="${f#$HEADER_DIR}"
    dev_path="/data/adb/modules/dkms-headers/header${rel}"

    mv "$f" "${f}.real"
    cat > "$f" <<EOF
#!/system/bin/sh
exec $LOADER --library-path $SYSROOT ${dev_path}.real "\$@"
EOF
    chmod 755 "$f"
    echo "Wrapped: $rel"
done

echo "Done."
