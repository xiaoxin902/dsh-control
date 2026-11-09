#!/bin/bash
# 巨魔（TrollStore）版构建：编 .app、ldid 签名带 entitlements、打成 .tipa。
#
#   SDKROOT=<iPhoneOS SDK 路径> ./trollstore/build-tipa.sh [输出目录，默认 build/]
#
# 依赖：clang（命令行工具链）、iPhoneOS SDK、ldid、lipo、zip。
# 与越狱版的区别：不编译 Helper、不打包守护进程和 deb，只出 .app + .tipa；
# 代码用 -DTROLLSTORE=1 编译，导出走 App 直连、不依赖控制守护进程。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build}"
ARCHES=(arm64 arm64e)
DEPLOYMENT=16.0

: "${SDKROOT:?需要设置 SDKROOT（iPhoneOS SDK 路径）}"
CC="${CC:-clang}"
command -v "$CC" >/dev/null 2>&1 || { echo "找不到 clang，先装命令行工具链" >&2; exit 1; }

APP="$OUT/Payload/DSHControl.app"
rm -rf "$OUT/Payload" "$OUT/DSHControl.tipa"
mkdir -p "$APP" "$OUT/obj" "$OUT/link"

SOURCES=(
  Sources/main.m
  Sources/AppDelegate.m
  Sources/SceneDelegate.m
  Sources/RootViewController.m
  Sources/DSHService.m
  Sources/DSHConfig.m
  Sources/DSHWebViewController.m
)

LINKED=()
for arch in "${ARCHES[@]}"; do
  mkdir -p "$OUT/link/$arch"
  arch_objs=()
  for src in "${SOURCES[@]}"; do
    obj="$OUT/obj/${arch}-$(basename "${src%.m}").o"
    "$CC" -isysroot "$SDKROOT" -arch "$arch" -mios-version-min="$DEPLOYMENT" \
      -fobjc-arc -Wall -Wextra -O2 -DTROLLSTORE=1 \
      -DAPELIN_VERSION='"1.3.1-ts"' -DAPELIN_BUILD_ID='"trollstore"' \
      -DAPELIN_PACKAGE_ID='"bc.8848.dshcontrol"' -DAPELIN_PRODUCT_NAME='"DSHControl"' \
      -I"$ROOT/Sources" -c "$ROOT/$src" -o "$obj"
    arch_objs+=("$obj")
  done
  "$CC" -isysroot "$SDKROOT" -arch "$arch" -mios-version-min="$DEPLOYMENT" -fobjc-arc \
    -framework Foundation -framework UIKit -framework WebKit -framework QuartzCore \
    "${arch_objs[@]}" -o "$OUT/link/$arch/DSHControl"
  LINKED+=("$OUT/link/$arch/DSHControl")
done

lipo -create "${LINKED[@]}" -output "$APP/DSHControl"
cp "$ROOT/trollstore/Info.plist" "$APP/Info.plist"
ldid -S"$ROOT/trollstore/entitlements.plist" "$APP/DSHControl"

(cd "$OUT" && zip -qry DSHControl.tipa Payload)
echo "$OUT/DSHControl.tipa"
