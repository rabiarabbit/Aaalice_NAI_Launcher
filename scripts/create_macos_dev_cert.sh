#!/usr/bin/env bash
# 创建本地自签名「代码签名」证书，放入独立钥匙串。
#
# 目的：给 macOS 调试版一个【稳定】的代码签名身份，避免 ad-hoc 签名
#       （flutter run 默认）导致 flutter_secure_storage 每次访问 Keychain
#       都弹出授权框。仅用于本地开发，不用于分发。
#
# 用法：scripts/create_macos_dev_cert.sh
# 证书名默认 "NAI Launcher Local Dev"，可用环境变量 SIGN_IDENTITY 覆盖。
set -euo pipefail

IDENTITY="${SIGN_IDENTITY:-NAI Launcher Local Dev}"
KC="$HOME/Library/Keychains/nai-codesign.keychain-db"
KC_PASS="naidev"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -keyout "$TMP/k.key" -out "$TMP/c.crt" \
  -days 3650 -nodes -config "$TMP/cert.conf"
# -legacy：用 macOS security 兼容的 PKCS12 算法（OpenSSL 3.x 默认算法 security 不认）
openssl pkcs12 -export -legacy -out "$TMP/c.p12" -inkey "$TMP/k.key" -in "$TMP/c.crt" \
  -passout "pass:$KC_PASS" -name "$IDENTITY"

security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings "$KC"                 # 不自动锁定
security unlock-keychain -p "$KC_PASS" "$KC"
security import "$TMP/c.p12" -k "$KC" -P "$KC_PASS" -T /usr/bin/codesign -A
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" >/dev/null
# 把新钥匙串加入搜索列表（保留原有的）
security list-keychains -d user -s "$KC" $(security list-keychains -d user | sed 's/"//g')

echo "已创建代码签名证书 '$IDENTITY'："
security find-identity -p codesigning "$KC"
echo
echo "接下来用 scripts/dev_run_macos_signed.sh 构建并以该证书签名运行。"
