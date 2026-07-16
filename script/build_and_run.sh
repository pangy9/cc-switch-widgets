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

# Files copied from a downloaded/cloned workspace can inherit provenance metadata.
# ExtensionKit may then reject a locally development-signed nested extension even
# though the signature itself is valid. Clear only the staged bundle metadata
# before verification and installation; source files are never touched.
xattr -cr "${BUILT_APP}"
codesign --verify --deep --strict --verbose=2 "${BUILT_APP}" >/dev/null

mkdir -p "${INSTALL_DIR}"
pkill -x CCSwitchWidgets 2>/dev/null || true
pkill -x CCSwitchWidgetsWidget 2>/dev/null || true
for _ in {1..50}; do
  if ! pgrep -x CCSwitchWidgets >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

# Xcode and older project-local build directories are also discovered by
# ExtensionKit. Multiple registered copies with the same bundle identifier make
# chronod pick stale executables and render placeholders. Unregister stale build
# copies, but preserve the current installed-path registration so ExtensionKit
# keeps its stable instance identifier across upgrades.
INSTALLED_EXTENSION="${INSTALLED_APP}/Contents/PlugIns/CCSwitchWidgetsWidget.appex"
HAS_INSTALLED_EXTENSION=0
while IFS= read -r registered_extension; do
  if [[ "${registered_extension}" == "${INSTALLED_EXTENSION}" ]]; then
    HAS_INSTALLED_EXTENSION=1
  elif [[ -n "${registered_extension}" ]]; then
    pluginkit -r "${registered_extension}" 2>/dev/null || true
  fi
done < <(
  pluginkit -m -A -D -v -i com.pangyun.CCSwitchWidgets.Widget 2>/dev/null \
    | awk -F '\t' 'NF >= 4 { print $4 }'
)

if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -u "${BUILT_APP}" 2>/dev/null || true
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
xattr -cr "${INSTALLED_APP}"
codesign --verify --deep --strict --verbose=2 "${INSTALLED_APP}" >/dev/null

if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -f "${INSTALLED_APP}" 2>/dev/null || true
fi
if [[ "${HAS_INSTALLED_EXTENSION}" -eq 0 ]]; then
  pluginkit -a "${INSTALLED_EXTENSION}" 2>/dev/null || true
fi
# Replacing an appex changes its ExtensionKit instance identifier even at the
# same path. Restart only chronod after stale registrations are gone so it cannot
# keep launching the previous identifier. NotificationCenter is intentionally
# left untouched.
killall chronod 2>/dev/null || true
open "${INSTALLED_APP}" || true

echo "Installed ${INSTALLED_APP}"
echo "Wait 30-60 seconds, then open Edit Widgets and search: CC Switch"
