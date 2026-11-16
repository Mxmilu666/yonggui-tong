#!/usr/bin/env bash
# Installs a release APK on the connected device/emulator, launches it and fails if the app
# crashes or is not running after startup. 1.1.0 shipped an APK that died at launch.
set -euo pipefail

apk="$1"
package=com.mxmilu.yonggui_tong

adb uninstall "$package" >/dev/null 2>&1 || true
adb install "$apk"
adb logcat -c
adb shell am start -W -n "$package/.MainActivity"
sleep 20

if adb logcat -d | grep -A20 "FATAL EXCEPTION" | grep -q "$package"; then
  adb logcat -d | grep -A40 "FATAL EXCEPTION"
  echo "App crashed at launch" >&2
  exit 1
fi
if [ -z "$(adb shell pidof "$package" | tr -d '\r')" ]; then
  echo "App is not running 20 s after launch" >&2
  exit 1
fi
echo "Launch smoke test passed: $apk"
