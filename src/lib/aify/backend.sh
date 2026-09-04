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
	aify_glibc_write_etc || aify_warn "glibc /etc dosyalari yazilamadi"
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

# Termux'un glibc'i /etc yerine $PREFIX/glibc/etc okur (libc.so.6 icindeki
# yollar boyle yamalidir), ancak glibc paketi resolv.conf/nsswitch.conf/hosts
# gondermez. Bunlar olmadan getaddrinfo 127.0.0.1'e dusup DNS'i basarisiz kilar
# - Antigravity CLI'nin "token exchange failed" hatasinin sebebi budur.
aify_glibc_etc_dir() { printf '%s/glibc/etc\n' "$AIFY_PREFIX"; }

aify_glibc_nameservers() {
	local ns='' p v
	# Once Android'in kendi DNS'i (Android 9+ genelde bos birakir)
	if aify_have getprop; then
		for p in net.dns1 net.dns2; do
			v="$(getprop "$p" 2>/dev/null)"
			case "$v" in ''|0.0.0.0) ;; *) ns="${ns:+$ns }$v" ;; esac
		done
	fi
	[ -n "$ns" ] || ns="$(aify_config_get glibc.dns '1.1.1.1 8.8.8.8')"
	printf '%s\n' "$ns"
}

aify_glibc_write_etc() {
	local etc ns n
	etc="$(aify_glibc_etc_dir)"
	[ -d "$AIFY_PREFIX/glibc" ] || return 1
	mkdir -p "$etc" 2>/dev/null || return 1

	ns="$(aify_glibc_nameservers)"
	{
		printf '# aify tarafindan uretildi - glibc ikilileri icin DNS\n'
		for n in $ns; do printf 'nameserver %s\n' "$n"; done
		printf 'options timeout:2 attempts:3\n'
	} > "$etc/resolv.conf" || return 1

	[ -f "$etc/nsswitch.conf" ] || cat > "$etc/nsswitch.conf" <<'NSS'
# aify tarafindan uretildi
passwd: files
group: files
shadow: files
hosts: files dns
networks: files
protocols: files
services: files
NSS

	[ -f "$etc/hosts" ] || cat > "$etc/hosts" <<'HOSTS'
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
HOSTS

	aify_step "glibc ag ayarlari: $etc/resolv.conf (${ns// /, })"
	return 0
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

# glibc ikilisini dogru sekilde baslatir.
#   non-PIE (EXEC): ld.so bir EXEC dosyasini yukleyemez (segfault) - ikili
#     kurulumda patchelf ile yamalandigi icin DOGRUDAN calistirilir.
#     GitHub Copilot CLI 158MB'lik non-PIE bir Node SEA'dir; segfault'un sebebi
#     tam olarak buydu.
#   PIE (DYN): ld.so modu (grun BINARY) yamadan bagimsiz calisir; kendini
#     guncelleyen araclar (agy) icin daha dayaniklidir.
# Her iki durumda da Termux'un bionic libtermux-exec.so'su LD_PRELOAD'dan
# cikarilmali, yoksa glibc sureci onu yuklemeye calisip patlar.
# glibc yiginini gercekten sinar: getent ile ad cozumleme.
# Tahmin yerine gercek hatayi gosterir ("token exchange failed" gibi
# kirpilmis mesajlarin ardindaki sebebi bulmak icin).
# glibc'in kendi getent'i Termux yorumlayicisiyla derlenmistir, dogrudan calisir.
aify_glibc_dns_test() {
	local host="${1:-oauth2.googleapis.com}" getent out rc
	getent="$AIFY_PREFIX/glibc/bin/getent"
	[ -x "$getent" ] || { echo "getent yok ($getent)"; return 2; }
	# shellcheck disable=SC2030  # PATH degisikligi bilerek alt kabukta kaliyor
	out="$(
		unset LD_PRELOAD
		PATH="$AIFY_PREFIX/glibc/bin:$PATH"
		if aify_have timeout; then timeout 10 "$getent" ahosts "$host" 2>&1
		else "$getent" ahosts "$host" 2>&1; fi
	)"
	rc=$?
	if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
		printf '%s\n' "$(printf '%s' "$out" | head -n1)"
		return 0
	fi
	printf '%s\n' "${out:-cozumleme basarisiz (cikis kodu $rc)}"
	return 1
}

# Calistirma yolu karari: grun (PIE -> ld.so modu) | proot (non-PIE)
aify_glibc_mode() {
	case "$(aify_elf_type "$1")" in
		exec) echo proot ;;
		*)    echo grun ;;
	esac
}

# glibc ikilisini ld.so modunda baslatir (ikili DEGISTIRILMEZ).
# Termux'un bionic libtermux-exec.so'su LD_PRELOAD'da kalirsa glibc sureci
# onu yuklemeye calisip patlar; once temizliyoruz.
aify_glibc_exec() {
	local path="$1"; shift
	if [ "$(aify_glibc_mode "$path")" = proot ]; then
		aify_err "$path non-PIE: glibc arka ucu bunu calistiramaz"
		aify_die "proot ile kurun:  aify install <arac> --backend proot"
	fi
	unset LD_PRELOAD
	# shellcheck disable=SC2031  # ustteki alt kabukla ilgisi yok; exec edilecek
	export PATH="$AIFY_PREFIX/glibc/bin:$PATH"
	if aify_have grun; then exec grun "$path" "$@"; fi
	exec glibc-runner "$path" "$@"
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
