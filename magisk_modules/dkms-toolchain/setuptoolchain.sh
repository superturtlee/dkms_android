#!/system/bin/sh
# Setup LLVM/Clang 19.1.0 build environment for DKMS
# TOOLCHAIN_DIR is exported by dkms_android.sh before sourcing

TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$(dirname "$0")/}"
CLANG_DIR="${TOOLCHAIN_DIR}clang+llvm-19.1.0-aarch64-linux-gnu"

export PATH="${CLANG_DIR}/wrapper:${CLANG_DIR}/bin:$PATH"

export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export STRIP=llvm-strip
export READELF=llvm-readelf

export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-

export LLVM=1
export LLVM_IAS=1
