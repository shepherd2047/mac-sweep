#!/bin/zsh
# One-time: creates a self-signed code-signing identity in its own keychain
# (~/Library/Keychains/macsweep-signing.keychain-db; the login keychain is not touched).
#
# Why: an ad-hoc signature changes on every build, so macOS treats each build as a new app
# and forgets Full Disk Access and folder permissions. Signing with a fixed certificate keeps
# the designated requirement (identifier + certificate) stable, so a grant survives rebuilds.
set -euo pipefail

KC=~/Library/Keychains/macsweep-signing.keychain-db
PASS=macsweep   # protects only this throwaway signing key
NAME="MacSweep Local Signing"

if [[ -f $KC ]] && security find-identity -p codesigning $KC | grep -q "$NAME"; then
  echo "signing identity already exists in $KC"
  exit 0
fi

T=$(mktemp -d)
trap 'rm -rf $T' EXIT
cat > $T/cert.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout $T/key.pem -out $T/cert.pem -days 3650 -config $T/cert.cnf 2>/dev/null
openssl pkcs12 -export -inkey $T/key.pem -in $T/cert.pem -out $T/id.p12 -passout pass:$PASS -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey $T/key.pem -in $T/cert.pem -out $T/id.p12 -passout pass:$PASS

[[ -f $KC ]] || security create-keychain -p $PASS $KC
security unlock-keychain -p $PASS $KC
security set-keychain-settings $KC
security import $T/id.p12 -k $KC -P $PASS -T /usr/bin/codesign -A >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k $PASS $KC >/dev/null 2>&1
echo "created \"$NAME\" in $KC"
