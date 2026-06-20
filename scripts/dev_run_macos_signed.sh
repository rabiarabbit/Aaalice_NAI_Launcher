#!/usr/bin/env bash
# macOS 本地开发：flutter build + 用稳定的本地证书重签 + 启动。
#
# 目的：避免 ad-hoc 签名（flutter run 默认）导致 flutter_secure_storage
#       每次访问 Keychain 都弹授权框。用稳定证书签名后，Keychain 的
#       "Always Allow" 一次永久生效（即使反复 rebuild）。
#
# 用法：scripts/dev_run_macos_signed.sh [debug|release]   （默认 debug）
# 依赖：先用 scripts/create_macos_dev_cert.sh 创建证书。
#       证书名默认 "NAI Launcher Local Dev"，可用环境变量 SIGN_IDENTITY 覆盖。
set -euo pipefail
cd "$(dirname "$0")/.."
export LANG="${LANG:-en_US.UTF-8}"

MODE="${1:-debug}"
IDENTITY="${SIGN_IDENTITY:-NAI Launcher Local Dev}"

if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
  echo "[ERROR] 找不到代码签名证书 '$IDENTITY'。"
  echo "        请先运行: scripts/create_macos_dev_cert.sh"
  exit 1
fi

if [ "$MODE" = "release" ]; then
  SUBDIR="Release"; ENT="macos/Runner/Release.entitlements"
else
  MODE="debug"; SUBDIR="Debug"; ENT="macos/Runner/DebugProfile.entitlements"
fi

echo "[1/3] flutter build macos --$MODE ..."
pkill -f "Aaalice NAI Launcher.app/Contents/MacOS" 2>/dev/null || true
flutter build macos --"$MODE"

APP="build/macos/Build/Products/$SUBDIR/Aaalice NAI Launcher.app"
echo "[2/3] 用 '$IDENTITY' 重签 ..."
codesign --force --deep --sign "$IDENTITY" --entitlements "$ENT" "$APP"

echo "[3/3] 启动 $APP"
open "$APP"
