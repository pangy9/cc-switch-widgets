#!/usr/bin/env bash
# 构建并打包 Release 版本，产出 dist/CCSwitchWidgets-<version>.dmg 供 GitHub Release 下载。
# .dmg 带「拖进 Applications」布局（app 图标 + Applications 替身）。
# 用法：
#   bash script/build_release.sh                 # 用项目默认团队
#   DEVELOPMENT_TEAM=你的TeamID bash script/build_release.sh   # 用你自己的团队
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="CCSwitchWidgets.app"
BUILD_DIR=".build/xcode-release"
BUILT_APP="${BUILD_DIR}/Build/Products/Release/${APP_NAME}"
TEAM="${DEVELOPMENT_TEAM:-63BU9WWKS2}"
VERSION="$(grep -m1 MARKETING_VERSION project.yml | sed 's/.*: *//; s/"//g')"
VOL_NAME="CC Switch Widgets"
VOL_PATH="/Volumes/${VOL_NAME}"
OUT_DIR="dist"
OUT="${OUT_DIR}/CCSwitchWidgets-${VERSION}.dmg"

echo "⚙️  生成 Xcode 工程..."
xcodegen generate

echo "⚙️  构建 Release (Team=${TEAM}, Version=${VERSION})..."
xcodebuild \
  -scheme CCSwitchWidgets \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "${BUILD_DIR}" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="${TEAM}" \
  CODE_SIGN_STYLE=Automatic \
  build

echo "📦  打包 .dmg -> ${OUT}"
STAGE="$(mktemp -d)"
TMP_DMG="$(mktemp -u).dmg"
trap 'hdiutil detach "${VOL_PATH}" -force >/dev/null 2>&1 || true; rm -rf "${STAGE}" "${TMP_DMG}"' EXIT

# 1) 暂存：app + Applications 替身
ln -s /Applications "${STAGE}/Applications"
cp -R "${BUILT_APP}" "${STAGE}/"

# 2) 预清理同名残留卷，再建读写 dmg 并挂载到 /Volumes（让 Finder 能按卷名寻址）
hdiutil detach "${VOL_PATH}" -force >/dev/null 2>&1 || true
hdiutil create -size 220m -fs HFS+ -volname "${VOL_NAME}" "${TMP_DMG}" >/dev/null
hdiutil attach "${TMP_DMG}" -nobrowse -noautoopen >/dev/null
cp -R "${STAGE}/." "${VOL_PATH}/"

# 3) Finder 图标布局（best-effort，失败不影响生成）
osascript <<APPLE || true
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {120, 120, 660, 380}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set position of item "${APP_NAME}" of container window to {160, 130}
        set position of item "Applications" of container window to {430, 130}
        close
        open
    end tell
end tell
APPLE

# 4) 卸载并转只读压缩
hdiutil detach "${VOL_PATH}" -force >/dev/null
mkdir -p "${OUT_DIR}"
rm -f "${OUT}"
hdiutil convert "${TMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${OUT}" >/dev/null

echo "✅  发布包: ${OUT}"
echo "    上传到 GitHub Release。用户打开 .dmg，把 ${APP_NAME} 拖进 Applications。"
echo "    首次启动若被 Gatekeeper 拦：xattr -dr com.apple.quarantine /Applications/${APP_NAME}"
