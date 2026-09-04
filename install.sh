#!/usr/bin/env bash
# aify hizli kurulum
#   curl -fsSL https://raw.githubusercontent.com/MrHakan/termux-aify/main/install.sh | bash
# Secenekler:  --source (surum yerine kaynaktan kur)   --ref <dal/etiket>
set -euo pipefail

REPO="${AIFY_REPO:-MrHakan/termux-aify}"
REF="${AIFY_REF:-main}"
MODE="auto"
PREFIX_DIR="${PREFIX:-/usr/local}"

while [ $# -gt 0 ]; do
	case "$1" in
		--source) MODE=source; shift ;;
		--deb)    MODE=deb; shift ;;
		--ref)    REF="$2"; shift 2 ;;
		-h|--help) sed -n '2,6p' "$0"; exit 0 ;;
		*) echo "bilinmeyen secenek: $1" >&2; exit 1 ;;
	esac
done

say()  { printf '\033[34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31mhata:\033[0m %s\n' "$*" >&2; exit 1; }

is_termux() { [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux/files/usr ]; }

command -v curl >/dev/null 2>&1 || die "curl gerekli (pkg install curl)"
command -v tar  >/dev/null 2>&1 || die "tar gerekli (pkg install tar)"

install_from_deb() {
	is_termux || return 1
	command -v apt >/dev/null 2>&1 || return 1
	local url tmp
	say "son surum araniyor"
	url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
		| tr ',' '\n' \
		| sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.deb\)".*/\1/p' | head -n1)"
	[ -n "$url" ] || { say "yayinlanmis .deb bulunamadi"; return 1; }
	tmp="$(mktemp -d)"
	say "indiriliyor: $url"
	curl -fL --progress-bar -o "$tmp/aify.deb" "$url" || { rm -rf "$tmp"; return 1; }
	say "kuruluyor (apt)"
	apt install -y "$tmp/aify.deb" || { rm -rf "$tmp"; return 1; }
	rm -rf "$tmp"
	return 0
}

install_from_source() {
	local tmp
	tmp="$(mktemp -d)"
	say "kaynak indiriliyor: $REPO@$REF"
	curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar -xz -C "$tmp" \
		|| die "kaynak indirilemedi"
	local src; src="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -n1)"
	[ -d "$src" ] || die "kaynak agaci bulunamadi"
	say "kuruluyor: $PREFIX_DIR"
	make -C "$src" install PREFIX="$PREFIX_DIR" || die "make install basarisiz"
	rm -rf "$tmp"
}

case "$MODE" in
	deb)    install_from_deb || die ".deb kurulumu basarisiz" ;;
	source) install_from_source ;;
	auto)   install_from_deb || install_from_source ;;
esac

printf '\n'
say "aify kuruldu: $(command -v aify || echo "$PREFIX_DIR/bin/aify")"
printf '   Siradaki adim:  \033[1maify setup\033[0m  ve  \033[1maify list\033[0m\n\n'
