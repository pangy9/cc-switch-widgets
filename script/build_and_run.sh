#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="CCSwitchWidgets.app"
# 安装构建使用独立目录，避免与日常 Debug/Release 验证共享 build.db 而互相锁死。
BUILD_DIR=".build/xcode-install"
BUILT_APP="${BUILD_DIR}/Build/Products/Release/${APP_NAME}"
INSTALL_DIR="${HOME}/Applications"
INSTALLED_APP="${INSTALL_DIR}/${APP_NAME}"
LEGACY_APP="/Applications/${APP_NAME}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

xcodegen generate
xcodebuild \
  -quiet \
  -scheme CCSwitchWidgets \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "${BUILD_DIR}" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM:-63BU9WWKS2} \
  CODE_SIGN_STYLE=Automatic \
  build

codesign --verify --deep --strict --verbose=2 "${BUILT_APP}" >/dev/null

mkdir -p "${INSTALL_DIR}"
pkill -x CCSwitchWidgets 2>/dev/null || true
pkill -x CCSwitchWidgetsWidget 2>/dev/null || true

if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -u "${BUILT_APP}" 2>/dev/null || true
  "${LSREGISTER}" -u "${INSTALLED_APP}" 2>/dev/null || true
fi
if [[ -d "${INSTALLED_APP}/Contents/PlugIns/CCSwitchWidgetsWidget.appex" ]]; then
  pluginkit -r "${INSTALLED_APP}/Contents/PlugIns/CCSwitchWidgetsWidget.appex" 2>/dev/null || true
fi

if [[ -d "${LEGACY_APP}" && "${LEGACY_APP}" != "${INSTALLED_APP}" ]]; then
  if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -u "${LEGACY_APP}" 2>/dev/null || true
  fi
  if [[ -d "${LEGACY_APP}/Contents/PlugIns/CCSwitchWidgetsWidget.appex" ]]; then
    pluginkit -r "${LEGACY_APP}/Contents/PlugIns/CCSwitchWidgetsWidget.appex" 2>/dev/null || true
  fi
  rm -rf "${LEGACY_APP}"
fi

rm -rf "${INSTALLED_APP}"
ditto "${BUILT_APP}" "${INSTALLED_APP}"

if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -f "${INSTALLED_APP}" 2>/dev/null || true
fi
pluginkit -a "${INSTALLED_APP}/Contents/PlugIns/CCSwitchWidgetsWidget.appex" 2>/dev/null || true

killall chronod 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true
open "${INSTALLED_APP}" || true

echo "Installed ${INSTALLED_APP}"
echo "Wait 30-60 seconds, then open Edit Widgets and search: CC Switch"
