#!/system/bin/sh
# DKMS build script for hello_dkms
# Environment: KERNEL_VERSION, TOOLCHAIN_NAME, NAME, VERSION are set by dkms_android.sh

MODDIR="$(cd "$(dirname "$0")" && pwd)"

HEADER_DIR=""
for hmod in /data/adb/modules/*/; do
    if [ -f "${hmod}header.cfg" ] && [ -d "${hmod}header" ]; then
        hkver=$(grep '^KERNEL_VERSION=' "${hmod}header.cfg" | cut -d'=' -f2-)
        if [ "$hkver" = "$KERNEL_VERSION" ]; then
            HEADER_DIR="${hmod}header"
            break
        fi
    fi
done

if [ -z "$HEADER_DIR" ]; then
    echo "ERROR: No header module found for kernel $KERNEL_VERSION"
    exit 1
fi

echo "Building $NAME v$VERSION for kernel $KERNEL_VERSION with $TOOLCHAIN_NAME"
echo "Headers: $HEADER_DIR"
echo "Module dir: $MODDIR"

make -C "$HEADER_DIR" M="$MODDIR" LLVM=1 LLVM_IAS=1 \
    KCFLAGS="-Wno-error=debug-compression-unavailable" \
    LDFLAGS_MODULE="--compress-debug-sections=none" modules
