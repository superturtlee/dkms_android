#!/system/bin/sh
SKIPUNZIP=1

ui_print "- Installing DKMS Clang Toolchain"

ui_print "- Extracting module files ..."
unzip -o "$ZIPFILE" -x 'META-INF/*' -d "$MODPATH" >&2

CLANG_DIR="$MODPATH/clang+llvm-19.1.0-aarch64-linux-gnu"
SYSROOT_DIR="$CLANG_DIR/sysroot"
WRAPPER_DIR="$CLANG_DIR/wrapper"

ui_print "- Extracting clang toolchain ..."
if [ -f "$MODPATH/toolchain.tar.xz" ]; then
    tar -xJf "$MODPATH/toolchain.tar.xz" -C "$MODPATH"
    rm -f "$MODPATH/toolchain.tar.xz"
else
    abort "! toolchain.tar.xz not found"
fi

ui_print "- Installing glibc sysroot ..."
mkdir -p "$SYSROOT_DIR"
tar -xzf "$MODPATH/sysroot.tar.gz" -C "$SYSROOT_DIR"
rm -f "$MODPATH/sysroot.tar.gz"

ui_print "- Installing make ..."
mv "$MODPATH/make" "$CLANG_DIR/bin/make"

ui_print "- Creating tool wrappers ..."
mkdir -p "$WRAPPER_DIR"

LOADER="$SYSROOT_DIR/ld-linux-aarch64.so.1"

for tool in clang clang++ clang-19 lld ld.lld llvm-ar llvm-nm llvm-objcopy \
            llvm-objdump llvm-strip llvm-readelf llvm-readobj llvm-symbolizer \
            llvm-as llvm-dis llvm-link opt; do
    if [ -e "$CLANG_DIR/bin/$tool" ]; then
        cat > "$WRAPPER_DIR/$tool" <<WRAPPER
#!/system/bin/sh
exec $LOADER --library-path $SYSROOT_DIR $CLANG_DIR/bin/$tool "\$@"
WRAPPER
        chmod 0755 "$WRAPPER_DIR/$tool"
    fi
done

# make is statically linked, just symlink
ln -sf "$CLANG_DIR/bin/make" "$WRAPPER_DIR/make"

ui_print "- Done"
