#!/usr/bin/env bash
set -euo pipefail

NAME="Forge Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "identity already present: $NAME"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<'CONF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = Forge Local Signing

[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CONF

echo "generating a self-signed code signing certificate..."
/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf" 2>/dev/null

PASSPHRASE="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
  -out "$WORK/forge.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -passout "pass:$PASSPHRASE"

echo "importing into the login keychain (you may be asked to allow this)..."
security import "$WORK/forge.p12" -k "$KEYCHAIN" -P "$PASSPHRASE" -A -T /usr/bin/codesign

echo "trusting it for code signing..."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
security find-identity -v -p codesigning
