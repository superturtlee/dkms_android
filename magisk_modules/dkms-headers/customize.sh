#!/system/bin/sh
SKIPUNZIP=1

ui_print "- Installing DKMS Linux Headers"

ui_print "- Extracting module files ..."
unzip -o "$ZIPFILE" -x 'META-INF/*' -d "$MODPATH" >&2

ui_print "- Extracting kernel headers ..."
if [ -f "$MODPATH/header.tar.gz" ]; then
    mkdir -p "$MODPATH/header"
    tar -xzf "$MODPATH/header.tar.gz" -C "$MODPATH/header"
    rm -f "$MODPATH/header.tar.gz"
    ui_print "- Headers extracted to $MODPATH/header/"
else
    abort "! header.tar.gz not found"
fi

ui_print "- Done"
