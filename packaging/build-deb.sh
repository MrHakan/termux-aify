#!/usr/bin/env bash
# aify icin Termux .deb paketi uretir (mimariden bagimsiz: Architecture: all)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
VERSION="$(sed -n 's/^AIFY_VERSION="\(.*\)"/\1/p' "$ROOT/src/lib/aify/core.sh" | head -n1)"
ARCH="all"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/deb}"
DEB="$OUT_DIR/aify_${VERSION}_${ARCH}.deb"

echo "==> aify $VERSION paketleniyor (prefix: $PREFIX)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/DEBIAN" "$OUT_DIR"

make -s -C "$ROOT" install DESTDIR="$BUILD_DIR" PREFIX="$PREFIX"

INSTALLED_SIZE="$(du -ks "$BUILD_DIR" | cut -f1)"

cat > "$BUILD_DIR/DEBIAN/control" <<CONTROL
Package: aify
Version: $VERSION
Architecture: $ARCH
Maintainer: @MrHakan
Installed-Size: $INSTALLED_SIZE
Depends: bash, coreutils, curl, tar, grep, sed, findutils
Recommends: nodejs-lts, git, ripgrep
Suggests: proot-distro, glibc-repo, gh, uv, unzip
Homepage: https://github.com/MrHakan/termux-aify
Description: Termux icin yapay zeka CLI yoneticisi
 aify; Claude Code, OpenAI Codex, Gemini CLI, Antigravity CLI (agy),
 GitHub CLI, opencode ve benzeri terminal yapay zeka araclarini Termux
 uzerinde tek komutla kurar, gunceller ve dogru arka uc ile calistirir.
 .
 Yerli calisamayan (glibc/musl'a bagli) ikililer icin glibc-runner veya
 proot-distro arka uclarini otomatik secer; her arac icin yalitilmis bir
 dizin ve PATH'e dusen ince bir shim olusturur.
CONTROL

cat > "$BUILD_DIR/DEBIAN/postinst" <<'POSTINST'
#!/data/data/com.termux/files/usr/bin/sh
set -e
if [ "$1" = "configure" ] || [ -z "${1:-}" ]; then
	echo ""
	echo "aify kuruldu. Baslamak icin:"
	echo "    aify setup     # dizinler ve temel paketler"
	echo "    aify list      # kurulabilir araclar"
	echo "    aify install gemini codex"
	echo ""
fi
exit 0
POSTINST
chmod 0755 "$BUILD_DIR/DEBIAN/postinst"

cat > "$BUILD_DIR/DEBIAN/prerm" <<'PRERM'
#!/data/data/com.termux/files/usr/bin/sh
set -e
# Kullanici verileri ($HOME/.aify) korunur; elle silmek icin: rm -rf ~/.aify
exit 0
PRERM
chmod 0755 "$BUILD_DIR/DEBIAN/prerm"

if command -v dpkg-deb >/dev/null 2>&1; then
	dpkg-deb --build --root-owner-group "$BUILD_DIR" "$DEB" >/dev/null
else
	echo "==> dpkg-deb yok, ar/tar ile paketleniyor"
	tmp="$(mktemp -d)"
	( cd "$BUILD_DIR/DEBIAN" && tar -czf "$tmp/control.tar.gz" . )
	( cd "$BUILD_DIR" && tar -czf "$tmp/data.tar.gz" --exclude='./DEBIAN' . )
	printf '2.0\n' > "$tmp/debian-binary"
	( cd "$tmp" && ar rc "$DEB" debian-binary control.tar.gz data.tar.gz )
	rm -rf "$tmp"
fi

echo "==> hazir: $DEB"
[ -n "${GITHUB_OUTPUT:-}" ] && printf 'deb=%s\n' "$DEB" >> "$GITHUB_OUTPUT"
exit 0
