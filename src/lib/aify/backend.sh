#!/usr/bin/env bash
# aify - calistirma arka uclari: native / glibc (glibc-runner) / proot (proot-distro)
# shellcheck shell=bash

aify_proot_distro()  { aify_config_get proot.distro debian; }
aify_proot_rootfs()  { printf '%s/files/usr/var/lib/proot-distro/installed-rootfs/%s\n' "${TERMUX_ROOTFS:-/data/data/com.termux}" "$(aify_proot_distro)"; }

# --- Kullanilabilirlik -------------------------------------------------------
aify_backend_available() {
	case "$1" in
		native) return 0 ;;
		glibc)  aify_have grun || aify_have glibc-runner ;;
		proot)  aify_have proot-distro && [ -d "$(aify_proot_rootfs)" ] ;;
		*)      return 1 ;;
	esac
}

aify_backend_status() {
	local b
	printf '%sArka uclar%s\n\n' "$C_BOLD" "$C_RESET"
	for b in native glibc proot; do
		if aify_backend_available "$b"; then
			printf '  %s[hazir]%s   %-7s %s\n' "$C_GREEN" "$C_RESET" "$b" "$(aify_backend_desc "$b")"
		else
			printf '  %s[yok]%s     %-7s %s\n' "$C_DIM" "$C_RESET" "$b" "$(aify_backend_desc "$b")"
		fi
	done
	printf '\n%sKurmak icin:%s aify backend setup <glibc|proot>\n' "$C_DIM" "$C_RESET"
}

aify_backend_desc() {
	case "$1" in
		native) echo "Termux icinde dogrudan (node betikleri, statik ELF)" ;;
		glibc)  echo "glibc-runner ile glibc ELF calistirma (hafif)" ;;
		proot)  echo "proot-distro $(aify_proot_distro) kabi (en uyumlu, ~500MB)" ;;
	esac
}

# --- Kurulum -----------------------------------------------------------------
aify_backend_setup() {
	case "${1:-}" in
		glibc) _aify_setup_glibc ;;
		proot) _aify_setup_proot ;;
		native) aify_ok "native arka uc her zaman hazir" ;;
		*) aify_die "kullanim: aify backend setup <glibc|proot>" ;;
	esac
}

_aify_setup_glibc() {
	aify_backend_available glibc && { aify_ok "glibc-runner zaten kurulu"; return 0; }
	aify_is_termux || aify_die "glibc arka ucu yalnizca Termux'ta anlamli"
	aify_info "glibc-runner kuruluyor (termux-pacman glibc deposu)"
	aify_have pkg || aify_die "pkg bulunamadi"
	aify_step "pkg install glibc-repo"
	pkg install -y glibc-repo || aify_die "glibc-repo kurulamadi"
	aify_step "apt update"
	apt update -y >/dev/null 2>&1 || true
	aify_step "pkg install glibc-runner patchelf"
	pkg install -y glibc-runner patchelf || aify_die "glibc-runner kurulamadi"
	aify_backend_available glibc && aify_ok "glibc arka ucu hazir"
	return 0
}

_aify_setup_proot() {
	local distro; distro="$(aify_proot_distro)"
	aify_is_termux || aify_die "proot arka ucu yalnizca Termux'ta anlamli"
	if ! aify_have proot-distro; then
		aify_info "proot-distro kuruluyor"
		pkg install -y proot-distro || aify_die "proot-distro kurulamadi"
	fi
	if [ ! -d "$(aify_proot_rootfs)" ]; then
		aify_info "$distro rootfs kuruluyor (birkac yuz MB indirilecek)"
		proot-distro install "$distro" || aify_die "$distro kurulamadi"
	fi
	_aify_proot_bootstrap
	aify_ok "proot arka ucu hazir ($distro)"
}

# Kap icinde temel paketler + node
_aify_proot_bootstrap() {
	aify_step "kap icinde temel paketler"
	_aify_proot_raw "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates curl xz-utils git tar procps >/dev/null" \
		|| aify_warn "apt-get adimi tam basarili olmadi, devam ediliyor"
	_aify_proot_ensure_node
}

_aify_proot_ensure_node() {
	if _aify_proot_raw 'command -v node >/dev/null 2>&1 && node -e "process.exit(process.versions.node.split(\".\")[0] >= 22 ? 0 : 1)"'; then
		return 0
	fi
	local ver arch
	ver="$(aify_config_get proot.node_version "$(_aify_node_lts_version)")"
	case "$(uname -m)" in
		aarch64|arm64) arch=arm64 ;;
		x86_64|amd64)  arch=x64 ;;
		armv7l|armv8l) arch=armv7l ;;
		*) aify_die "kap icin desteklenmeyen mimari: $(uname -m)" ;;
	esac
	aify_step "kap icine Node.js $ver kuruluyor"
	_aify_proot_raw "set -e
url=https://nodejs.org/dist/${ver}/node-${ver}-linux-${arch}.tar.xz
cd /tmp && curl -fsSL -o node.tar.xz \"\$url\"
mkdir -p /usr/local/lib/nodejs && tar -xJf node.tar.xz -C /usr/local/lib/nodejs
rm -f node.tar.xz
ln -sf /usr/local/lib/nodejs/node-${ver}-linux-${arch}/bin/node /usr/local/bin/node
ln -sf /usr/local/lib/nodejs/node-${ver}-linux-${arch}/bin/npm /usr/local/bin/npm
ln -sf /usr/local/lib/nodejs/node-${ver}-linux-${arch}/bin/npx /usr/local/bin/npx" \
		|| aify_die "kap icine Node.js kurulamadi"
}

_aify_node_lts_version() {
	local v
	v="$(aify_fetch https://nodejs.org/dist/index.json 2>/dev/null \
		| tr '}' '\n' | grep '"lts":"[A-Za-z]' | head -n1 \
		| sed -n 's/.*"version":"\(v[0-9.]*\)".*/\1/p')"
	printf '%s\n' "${v:-v22.22.0}"
}

# --- Calistirma --------------------------------------------------------------
# Kap icinde ham komut (root, ev dizini bagli degil) - kurulum adimlari icin
_aify_proot_raw() {
	proot-distro login "$(aify_proot_distro)" --shared-tmp -- /bin/bash -lc "$1"
}

# Kap icinde kullanici baglamli komut: $HOME ve $PWD ayni yollarla baglanir,
# boylece ~/.claude gibi ayarlar yerli kurulumla ayni yerde durur.
aify_proot_exec() {
	local cmd="$1"
	local -a binds=(--bind "$HOME:$HOME")
	[ "$PWD" != "$HOME" ] && binds+=(--bind "$PWD:$PWD")
	[ -d /sdcard ] && binds+=(--bind "/sdcard:/sdcard")
	proot-distro login "$(aify_proot_distro)" --shared-tmp "${binds[@]}" -- \
		/usr/bin/env "HOME=$HOME" "TERM=${TERM:-xterm-256color}" \
		"PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin" \
		/bin/bash -lc "cd $(printf '%q' "$PWD") 2>/dev/null || cd $(printf '%q' "$HOME"); $cmd"
}

aify_grun() { if aify_have grun; then grun "$@"; else glibc-runner "$@"; fi; }

# Bir ELF'i glibc arka ucu icin hazirlar (interpreter/rpath yamasi)
aify_glibc_configure() {
	local bin="$1"
	aify_backend_available glibc || return 1
	aify_grun -c "$bin" >/dev/null 2>&1 || aify_warn "grun -c basarisiz: $bin"
	return 0
}

# Arac icin kullanilacak arka ucu secer:
#   1) tool.<id>.backend config'i
#   2) TOOL_BACKENDS listesindeki ilk kullanilabilir arka uc
aify_backend_pick() {
	local id="$1" forced b
	forced="$(aify_config_get "tool.$id.backend" '')"
	if [ -n "$forced" ]; then printf '%s\n' "$forced"; return 0; fi
	for b in $TOOL_BACKENDS; do
		aify_backend_available "$b" && { printf '%s\n' "$b"; return 0; }
	done
	# Hicbiri hazir degil: listedeki ilkini don (kurulum adimi onerilecek)
	printf '%s\n' "${TOOL_BACKENDS%% *}"
}
