#!/system/bin/sh

MODDIR=${0%/*}
export MODDIR
sh "$MODDIR/bin/dkms_android.sh" boot
