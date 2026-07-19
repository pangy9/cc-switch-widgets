#!/usr/bin/env bash
# Rebuild and reinstall CC Switch Widgets to renew a free Personal Team profile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT="${PROJECT_DIR}/script/build_and_run.sh"
INSTALL_APP="${HOME}/Applications/CCSwitchWidgets.app"

# GUI launchers often have a minimal PATH without Homebrew.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "❌ 请先通过环境变量设置你自己的 Apple Development Team ID：" >&2
  echo "   DEVELOPMENT_TEAM=你的TeamID bash script/rebuild_personal_team.sh" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ 找不到 xcodegen。请先运行：brew install xcodegen" >&2
  exit 1
fi

if [[ ! -f "${BUILD_SCRIPT}" ]]; then
  echo "❌ 找不到构建脚本：${BUILD_SCRIPT}" >&2
  exit 1
fi

echo "🔁 开始重建 CC Switch Widgets，并请求 Xcode 更新 provisioning profile…"

BUILD_LOG="$(mktemp -t rebuild_ccswitch_widgets)"
trap 'rm -f "${BUILD_LOG}"' EXIT

if ! bash "${BUILD_SCRIPT}" 2>&1 | tee "${BUILD_LOG}"; then
  echo ""
  if grep -qE "No Accounts|No profiles for|were found" "${BUILD_LOG}"; then
    echo "❌ Xcode 没有可用于签名的 Apple 账户或 provisioning profile。"
    echo "   请打开 Xcode → Settings → Accounts，登录 Apple ID 后重试。"
  else
    echo "❌ 重建失败，请检查上方 xcodebuild 日志。"
  fi
  exit 1
fi

# When an expired profile caused WidgetKit to drop the extension, restarting
# chronod alone may not refresh the widget gallery. Notification Center relaunches
# automatically; existing desktop widgets may briefly flash during this step.
killall NotificationCenter 2>/dev/null || true

if [[ ! -d "${INSTALL_APP}" ]]; then
  echo "❌ 构建结束后未找到 ${INSTALL_APP}" >&2
  exit 1
fi

echo ""
echo "✅ 重建完成。免费 Personal Team 的 profile 已由 Xcode 重新生成。"
echo "   请等待几十秒，让桌面组件重新加载。"
