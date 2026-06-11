#!/bin/sh
# sky-sqlgen installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/anzellai/sky-sqlgen/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/anzellai/sky-sqlgen/main/install.sh | sh -s -- --dir ~/.local/bin
#   curl -fsSL https://raw.githubusercontent.com/anzellai/sky-sqlgen/main/install.sh | sh -s -- --version v0.1.0
#
# Env overrides:
#   SKY_SQLGEN_VERSION       version tag to install (default: latest release)
#   SKY_SQLGEN_INSTALL_DIR   install directory (default: /usr/local/bin)
set -eu

REPO="anzellai/sky-sqlgen"
BIN="sky-sqlgen"

# ── args ────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --dir=*)     SKY_SQLGEN_INSTALL_DIR="${1#--dir=}" ;;
        --dir)       shift; SKY_SQLGEN_INSTALL_DIR="$1" ;;
        --version=*) SKY_SQLGEN_VERSION="${1#--version=}" ;;
        --version)   shift; SKY_SQLGEN_VERSION="$1" ;;
        -h|--help)
            sed -n '2,12p' "$0" 2>/dev/null || echo "see https://github.com/$REPO"
            exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

INSTALL_DIR="${SKY_SQLGEN_INSTALL_DIR:-/usr/local/bin}"

info()    { printf '  %s\n' "$1"; }
err()     { printf 'error: %s\n' "$1" >&2; exit 1; }
success() { printf '\033[32m✓\033[0m %s\n' "$1"; }

command -v curl >/dev/null 2>&1 || err "curl is required"

# ── detect os/arch (must match the release asset names) ─────────────
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    *) err "unsupported OS: $OS (sky-sqlgen ships linux and darwin binaries)" ;;
esac
case "$ARCH" in
    x86_64|amd64)  ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) err "unsupported architecture: $ARCH" ;;
esac

# ── resolve version ─────────────────────────────────────────────────
VERSION="${SKY_SQLGEN_VERSION:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | head -1 | sed 's/.*"\(v[^"]*\)".*/\1/')
    [ -n "$VERSION" ] || err "could not resolve the latest release (set --version vX.Y.Z)"
fi
case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac

ASSET="${BIN}-${VERSION}-${OS}-${ARCH}"
URL="https://github.com/$REPO/releases/download/${VERSION}/${ASSET}"

info "Installing $BIN $VERSION ($OS/$ARCH)"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

curl -fSL "$URL" -o "$TMPDIR/$BIN" 2>/dev/null \
    || err "download failed: $URL"

# ── best-effort checksum verification ───────────────────────────────
if curl -fsSL "https://github.com/$REPO/releases/download/${VERSION}/SHA256SUMS" -o "$TMPDIR/SHA256SUMS" 2>/dev/null; then
    want=$(grep " ${ASSET}\$" "$TMPDIR/SHA256SUMS" | awk '{print $1}')
    if [ -n "$want" ]; then
        if command -v sha256sum >/dev/null 2>&1; then
            got=$(sha256sum "$TMPDIR/$BIN" | awk '{print $1}')
        elif command -v shasum >/dev/null 2>&1; then
            got=$(shasum -a 256 "$TMPDIR/$BIN" | awk '{print $1}')
        else
            got=""
        fi
        [ -z "$got" ] || [ "$got" = "$want" ] || err "checksum mismatch for $ASSET"
        [ -z "$got" ] || info "checksum verified"
    fi
fi

chmod +x "$TMPDIR/$BIN"

# ── install ─────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR" 2>/dev/null || true
if [ -w "$INSTALL_DIR" ]; then
    mv "$TMPDIR/$BIN" "$INSTALL_DIR/$BIN"
else
    info "Requires sudo to install to $INSTALL_DIR"
    sudo mv "$TMPDIR/$BIN" "$INSTALL_DIR/$BIN"
fi

success "Installed $BIN -> $INSTALL_DIR/$BIN"
case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) info "Add $INSTALL_DIR to your PATH:  export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
esac
info "Run:  $BIN --version"
