#!/usr/bin/env bash
#
# Creates a stable local code-signing identity for development builds.
#
# Why this exists: an ad-hoc signature is different on every build, so macOS
# treats each rebuild as a *different application*. Two things break as a
# result, and the second one is the reason this script is not optional for Cue:
#
#   * the Launch at Login registration is dropped, and
#   * the keychain refuses the new build access to the items the previous one
#     wrote — which is where the OAuth refresh token and the YouTube Music
#     cookie live. Without a stable identity you are signed out after every
#     single build, and the app looks broken when it is working perfectly.
#
# A constant identity — self-signed is fine — gives every local build the same
# designated requirement, so that state survives rebuilding.
#
# It is not a substitute for notarization: a build signed this way still shows
# Gatekeeper's "unverified developer" prompt if someone downloads it.
#
# Offline, free, no Apple account, and idempotent — run it as many times as you
# like.

set -euo pipefail

IDENTITY="Cue Signing"
KEYCHAIN="$HOME/Library/Keychains/cue-signing.keychain-db"
KEYCHAIN_NAME="cue-signing.keychain"
SECRET_DIR="$HOME/.config/cue"
SECRET_FILE="$SECRET_DIR/signing-keychain-password"
VALID_DAYS=3650

command -v openssl >/dev/null || { echo "error: openssl not found" >&2; exit 1; }

# Note the absence of `-v`. A self-signed certificate is not *trusted*, so it
# never appears in the "valid identities" list — but codesign will happily sign
# with it, and the resulting designated requirement is pinned to this
# certificate's root. Stability is what the keychain and the login item need;
# trust is what notarization provides, and that is a separate job.
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "▸ '$IDENTITY' already exists — nothing to do."
    echo "  Builds will pick it up automatically."
    exit 0
fi

echo "▸ Creating a local code-signing identity: $IDENTITY"

mkdir -p "$SECRET_DIR"
chmod 700 "$SECRET_DIR"

if [[ -f "$SECRET_FILE" ]]; then
    PASSWORD="$(cat "$SECRET_FILE")"
else
    PASSWORD="$(openssl rand -base64 24)"
    printf '%s' "$PASSWORD" > "$SECRET_FILE"
    chmod 600 "$SECRET_FILE"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The `codeSigning` extended key usage is what makes codesign willing to use
# the certificate at all; without it the identity simply does not appear.
cat > "$WORK/openssl.cnf" <<'CONF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = Cue Signing
O  = Cue
C  = US

[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CONF

echo "▸ Generating a key and a self-signed certificate"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days "$VALID_DAYS" -config "$WORK/openssl.cnf" 2>/dev/null

openssl pkcs12 -export -legacy \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout "pass:$PASSWORD" 2>/dev/null

# A dedicated keychain, so nothing here touches the login keychain and the
# whole thing can be removed by deleting one file.
if [[ ! -f "$KEYCHAIN" ]]; then
    echo "▸ Creating the keychain"
    security create-keychain -p "$PASSWORD" "$KEYCHAIN_NAME"
fi

security set-keychain-settings "$KEYCHAIN_NAME"          # no auto-lock timeout
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN_NAME"

echo "▸ Importing"
security import "$WORK/identity.p12" \
    -k "$KEYCHAIN_NAME" -P "$PASSWORD" -A -T /usr/bin/codesign -T /usr/bin/security

# Without this, codesign prompts for the keychain password on every build.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN_NAME" >/dev/null

# The keychain has to be in the search list for `find-identity` to see it.
EXISTING="$(security list-keychains -d user | sed -E 's/^ *"//; s/"$//')"
if ! grep -q "$KEYCHAIN_NAME" <<< "$EXISTING"; then
    echo "▸ Adding the keychain to the search list"
    # shellcheck disable=SC2086
    security list-keychains -d user -s $EXISTING "$KEYCHAIN_NAME"
fi

if security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "▸ Done. '$IDENTITY' is ready; ./Scripts/build.sh will use it automatically."
    echo "  Builds now keep a constant designated requirement across rebuilds,"
    echo "  so Launch at Login and your saved sign-ins survive them."
else
    echo "error: the identity was created but codesign cannot see it." >&2
    echo "       Check: security find-identity -p codesigning" >&2
    exit 1
fi
