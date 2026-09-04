#!/usr/bin/env bash
# aify - ortak yardimcilar (logging, yollar, config, state, ELF analizi)
# shellcheck shell=bash

# Bu degiskenler diger lib dosyalarinda ve bin/aify icinde kullanilir.
# shellcheck disable=SC2034
AIFY_VERSION="0.3.0"

# --- Yollar -----------------------------------------------------------------
AIFY_PREFIX="${PREFIX:-/usr}"
AIFY_HOME="${AIFY_HOME:-$HOME/.aify}"
AIFY_TOOLS_DIR="$AIFY_HOME/tools"
AIFY_BIN_DIR="$AIFY_HOME/bin"
AIFY_STATE_DIR="$AIFY_HOME/state"
AIFY_CACHE_DIR="$AIFY_HOME/cache"
AIFY_LOG_DIR="$AIFY_HOME/log"
AIFY_CONFIG_FILE="$AIFY_HOME/config"

# --- Renkler ----------------------------------------------------------------
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
	C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
	C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
	C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
	C_RESET=''; C_DIM=''; C_BOLD=''
	C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
fi

aify_say()  { printf '%s\n' "$*"; }
aify_info() { printf '%s==>%s %s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$*" >&2; }
aify_step() { printf '%s  ->%s %s\n' "$C_CYAN" "$C_RESET" "$*" >&2; }
aify_ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
aify_warn() { printf '%suyari:%s %s\n' "$C_YELLOW$C_BOLD" "$C_RESET" "$*" >&2; }
aify_err()  { printf '%shata:%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$*" >&2; }
aify_dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
aify_die()  { aify_err "$*"; exit 1; }
aify_debug() { [ -n "${AIFY_DEBUG:-}" ] && printf '%s[debug]%s %s\n' "$C_DIM" "$C_RESET" "$*" >&2; return 0; }

# --- Ortam ------------------------------------------------------------------
aify_have() { command -v "$1" >/dev/null 2>&1; }

aify_is_termux() {
	[ -n "${TERMUX_VERSION:-}" ] && return 0
	case "${PREFIX:-}" in */com.termux/files/usr) return 0 ;; esac
	[ -d /data/data/com.termux/files/usr ] && return 0
	return 1
}

# Termux'ta node process.platform == 'android' doner; npm bu yuzden
# os:["linux"] isaretli platform paketlerini atlar. Bunu --os ile asiyoruz.
aify_node_platform() {
	if aify_have node; then node -p 'process.platform' 2>/dev/null && return 0; fi
	aify_is_termux && { echo android; return 0; }
	echo linux
}

# uname -m -> npm cpu adi
aify_npm_cpu() {
	case "$(uname -m)" in
		aarch64|arm64) echo arm64 ;;
		x86_64|amd64)  echo x64 ;;
		armv7l|armv8l) echo arm ;;
		i686|i386)     echo ia32 ;;
		*)             uname -m ;;
	esac
}

aify_ensure_dirs() {
	mkdir -p "$AIFY_TOOLS_DIR" "$AIFY_BIN_DIR" "$AIFY_STATE_DIR" \
	         "$AIFY_CACHE_DIR" "$AIFY_LOG_DIR" "$AIFY_HOME/registry.d"
}

aify_confirm() {
	[ -n "${AIFY_YES:-}" ] && return 0
	[ -t 0 ] || return 0
	local reply
	printf '%s [E/h] ' "$1" >&2
	read -r reply || return 1
	case "$reply" in ''|e|E|y|Y|evet|yes) return 0 ;; *) return 1 ;; esac
}

# --- Config (key=value) ------------------------------------------------------
aify_config_get() {
	local key="$1" default="${2:-}" val=''
	if [ -f "$AIFY_CONFIG_FILE" ]; then
		val="$(sed -n "s/^$(printf '%s' "$key" | sed 's/[][\.*^$\/]/\\&/g')=//p" "$AIFY_CONFIG_FILE" | tail -n1)"
	fi
	printf '%s\n' "${val:-$default}"
}

aify_config_set() {
	local key="$1" value="$2" tmp
	aify_ensure_dirs
	touch "$AIFY_CONFIG_FILE"
	tmp="$AIFY_CONFIG_FILE.tmp.$$"
	grep -v "^$(printf '%s' "$key" | sed 's/[][\.*^$\/]/\\&/g')=" "$AIFY_CONFIG_FILE" > "$tmp" 2>/dev/null || true
	printf '%s=%s\n' "$key" "$value" >> "$tmp"
	mv "$tmp" "$AIFY_CONFIG_FILE"
}

aify_config_unset() {
	local key="$1" tmp
	[ -f "$AIFY_CONFIG_FILE" ] || return 0
	tmp="$AIFY_CONFIG_FILE.tmp.$$"
	grep -v "^$(printf '%s' "$key" | sed 's/[][\.*^$\/]/\\&/g')=" "$AIFY_CONFIG_FILE" > "$tmp" 2>/dev/null || true
	mv "$tmp" "$AIFY_CONFIG_FILE"
}

aify_config_list() {
	[ -f "$AIFY_CONFIG_FILE" ] || return 0
	sort "$AIFY_CONFIG_FILE"
}

# --- State (kurulu arac bilgisi) --------------------------------------------
aify_state_file() { printf '%s/%s\n' "$AIFY_STATE_DIR" "$1"; }
aify_is_installed() { [ -f "$(aify_state_file "$1")" ]; }

aify_state_get() {
	local id="$1" key="$2" f
	f="$(aify_state_file "$id")"
	[ -f "$f" ] || return 1
	sed -n "s/^$key=//p" "$f" | tail -n1
}

aify_state_put() {
	local id="$1"; shift
	aify_ensure_dirs
	local f; f="$(aify_state_file "$id")"
	: > "$f"
	local kv
	for kv in "$@"; do printf '%s\n' "$kv" >> "$f"; done
}

aify_state_del() { rm -f "$(aify_state_file "$1")"; }

# --- Indirme ----------------------------------------------------------------
aify_fetch() { # url -> stdout
	if aify_have curl; then curl -fsSL "$1"
	elif aify_have wget; then wget -qO- "$1"
	else aify_die "curl veya wget gerekli"; fi
}

aify_download() { # url dest
	if aify_have curl; then curl -fL --progress-bar -o "$2" "$1"
	elif aify_have wget; then wget -q --show-progress -O "$2" "$1"
	else aify_die "curl veya wget gerekli"; fi
}

# --- ELF analizi ------------------------------------------------------------
# Bir dosyanin Termux'ta dogrudan calisip calisamayacagini belirler.
# Cikti: script | static | glibc | musl | unknown | missing
aify_binary_class() {
	local f="$1" magic interp
	[ -f "$f" ] || { echo missing; return; }
	magic="$(head -c 4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
	if [ "$magic" != "7f454c46" ]; then echo script; return; fi

	if aify_have readelf; then
		interp="$(readelf -l "$f" 2>/dev/null | sed -n 's/.*\[Requesting program interpreter: \([^]]*\)\]/\1/p' | head -n1)"
	else
		interp="$(_aify_elf_interp "$f" || true)"
	fi

	case "$interp" in
		'')            echo static ;;
		*ld-musl*)     echo musl ;;
		*ld-linux*)    echo glibc ;;
		*linker*)      echo static ;;   # bionic linker: zaten Termux yerlisi
		*)             echo unknown ;;
	esac
}

# ELF basligindan kucuk bir tamsayi okur (host little-endian; hem aarch64
# hem x86_64 LE oldugu icin od'nin yerel siralamasi dogru sonucu verir)
_aify_u() { od -An -j"$2" -N"$3" -tu"$3" "$1" 2>/dev/null | tr -d ' \n'; }

# Yorumlayici (PT_INTERP) yolunu program basliklarindan okur.
# Dize taramasi yeterli degil: patchelf yamaladiginda .interp dosyanin
# ortasina tasinabiliyor (200MB'lik agy ikilisinde oyle oluyor) ve ikili
# yanlislikla "statik" sanilip yanlis arka uca yonleniyordu.
# readelf Termux'ta varsayilan gelmedigi icin basliklari elle cozuyoruz.
_aify_elf_interp() {
	local f="$1" cls phoff phentsize phnum i off ptype poff psz
	cls="$(_aify_u "$f" 4 1)"
	case "$cls" in
		2) phoff="$(_aify_u "$f" 32 8)"; phentsize="$(_aify_u "$f" 54 2)"; phnum="$(_aify_u "$f" 56 2)" ;;
		1) phoff="$(_aify_u "$f" 28 4)"; phentsize="$(_aify_u "$f" 42 2)"; phnum="$(_aify_u "$f" 44 2)" ;;
		*) return 1 ;;
	esac
	[ -n "$phoff" ] && [ -n "$phnum" ] && [ "${phnum:-0}" -gt 0 ] 2>/dev/null || return 1
	[ "$phnum" -le 128 ] 2>/dev/null || phnum=128

	i=0
	while [ "$i" -lt "$phnum" ]; do
		off=$(( phoff + i * phentsize ))
		ptype="$(_aify_u "$f" "$off" 4)"
		if [ "$ptype" = 3 ]; then   # PT_INTERP
			if [ "$cls" = 2 ]; then
				poff="$(_aify_u "$f" $((off + 8)) 8)"; psz="$(_aify_u "$f" $((off + 32)) 8)"
			else
				poff="$(_aify_u "$f" $((off + 4)) 4)"; psz="$(_aify_u "$f" $((off + 16)) 4)"
			fi
			[ -n "$poff" ] && [ -n "$psz" ] && [ "$psz" -gt 0 ] 2>/dev/null || return 1
			[ "$psz" -le 4096 ] 2>/dev/null || psz=4096
			dd if="$f" bs=1 skip="$poff" count="$psz" 2>/dev/null | tr -d '\000'
			return 0
		fi
		i=$((i + 1))
	done
	return 1   # PT_INTERP yok -> statik
}

# ELF tipi: exec (non-PIE) | dyn (PIE) | none
# e_type basligin 16. baytindadir; readelf Termux'ta varsayilan gelmez.
# Fark onemli: dinamik yukleyici (ld.so BINARY) non-PIE bir dosyayi
# yukleyemez, segfault ile duser - o yuzden onlari dogrudan calistiririz.
aify_elf_type() {
	aify_is_elf "$1" || { echo none; return; }
	case "$(od -An -tu2 -j16 -N2 "$1" 2>/dev/null | tr -d ' ')" in
		2) echo exec ;;
		3) echo dyn ;;
		*) echo none ;;
	esac
}

# Dosya ELF mi? (O(1) - calistirma yolunda tam siniflandirma pahali olurdu)
aify_is_elf() {
	[ -f "$1" ] || return 1
	[ "$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]
}

# Sinifa gore onerilen backend
aify_class_backend() {
	case "$1" in
		script|static) echo native ;;
		glibc)         echo glibc ;;
		musl)          echo proot ;;
		*)             echo native ;;
	esac
}

# Ikilinin gercekte hangi arka uctan calisabilecegi.
# glibc + non-PIE ozel durumu: glibc-runner ikiliyi 'ld.so BINARY' seklinde
# baslatir, dinamik yukleyici ise non-PIE (ET_EXEC) bir dosyayi yukleyemez.
# Tek alternatif ikiliyi patchelf ile yamalamaktir; baskasinin 100+MB'lik
# ikilisini yerinde degistirmek riskli oldugu icin bunu yapmiyoruz - boyle
# araclar proot kabinda gercek bir /lib/ld-linux ile sorunsuz calisir.
aify_runtime_backend() {
	local path="$1" class="$2"
	case "$class" in
		glibc)
			if [ "$(aify_elf_type "$path")" = exec ]; then echo proot; else echo glibc; fi
			;;
		*) aify_class_backend "$class" ;;
	esac
}

aify_human_class() {
	case "$1" in
		script)  echo "yorumlanan betik (node/python) - yerli calisir" ;;
		static)  echo "statik ELF - yerli calisir" ;;
		glibc)   echo "glibc'e bagli ELF - glibc-runner veya proot gerekir" ;;
		musl)    echo "musl'a bagli ELF - proot gerekir" ;;
		missing) echo "dosya yok" ;;
		*)       echo "bilinmiyor" ;;
	esac
}
