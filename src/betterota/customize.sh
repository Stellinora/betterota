#!/system/bin/sh

export SKIPUNZIP=0

BOTA_VERSION=$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null | head -n1)

ui_print "*******************************"
ui_print " BetterOTA Root Keeper ${BOTA_VERSION}"
ui_print "*******************************"

if command -v set_perm_recursive >/dev/null 2>&1; then
  set_perm_recursive "$MODPATH/scripts" 0 0 0755 0644
  set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
  set_perm "$MODPATH/service.sh" 0 0 0755
  set_perm "$MODPATH/boot-completed.sh" 0 0 0755
  set_perm "$MODPATH/action.sh" 0 0 0755
  set_perm "$MODPATH/uninstall.sh" 0 0 0755
fi

mkdir -p /data/adb/betterota/state

ui_print "- module scripts set executable"
ui_print "- runtime data: /data/adb/betterota"
ui_print "- user config : /data/adb/betterota/config.sh"
ui_print "- verify bootctl support before relying on auto-abandon"
