#!/usr/bin/env bash
# aify - ortam teshisi
# shellcheck shell=bash

_AIFY_DOCTOR_PROBLEMS=0

_d_ok()   { printf '  %s[ok]%s   %s\n' "$C_GREEN" "$C_RESET" "$*"; }
_d_warn() { printf '  %s[!!]%s   %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
_d_bad()  { printf '  %s[hata]%s %s\n' "$C_RED" "$C_RESET" "$*"; _AIFY_DOCTOR_PROBLEMS=$((_AIFY_DOCTOR_PROBLEMS+1)); }
_d_head() { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

_d_version() { "$1" --version 2>/dev/null | head -n1; }

aify_cmd_doctor() {
	printf '%saify %s teshis raporu%s\n' "$C_BOLD" "$AIFY_VERSION" "$C_RESET"

	_d_head "Sistem"
	if aify_is_termux; then
		_d_ok "Termux ($(uname -m))${TERMUX_VERSION:+ / uygulama $TERMUX_VERSION}"
		aify_have getprop && _d_ok "Android $(getprop ro.build.version.release 2>/dev/null) (API $(getprop ro.build.version.sdk 2>/dev/null))"
	else
		_d_warn "Termux disinda calisiyor ($(uname -s) $(uname -m)) - yalnizca native arka uc test edilebilir"
	fi
	local free
	free="$(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
	[ -n "$free" ] && _d_ok "bos alan ($HOME): $free"

	_d_head "Calisma zamanlari"
	local c
	for c in bash curl tar git; do
		if aify_have "$c"; then _d_ok "$c $(_d_version "$c" | head -c 40)"; else _d_bad "$c yok"; fi
	done
	if aify_have node; then
		_d_ok "node $(node --version) (platform: $(aify_node_platform))"
		local major; major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
		[ "${major:-0}" -lt 22 ] && _d_warn "bazi araclar Node >= 22 istiyor (pkg install nodejs-lts)"
	else
		_d_warn "node yok - npm tabanli araclar icin: pkg install nodejs-lts"
	fi
	if aify_have npm; then _d_ok "npm $(npm --version)"; else _d_warn "npm yok"; fi
	for c in rg gh python uv bun; do
		if aify_have "$c"; then _d_ok "$c bulundu"
		else printf '  %s[ ]%s    %s yok (istege bagli)\n' "$C_DIM" "$C_RESET" "$c"; fi
	done

	_d_head "Arka uclar"
	local b
	for b in native glibc proot; do
		if aify_backend_available "$b"; then _d_ok "$b hazir"
		else printf '  %s[ ]%s    %s hazir degil  (aify backend setup %s)\n' "$C_DIM" "$C_RESET" "$b" "$b"; fi
	done
	if aify_backend_available glibc; then
		# glibc /etc yoksa DNS calismaz (Antigravity/Go ikilileri buna takilir)
		if [ -f "$(aify_glibc_etc_dir)/resolv.conf" ]; then
			_d_ok "glibc DNS ayarli ($(aify_glibc_etc_dir)/resolv.conf)"
		else
			_d_bad "glibc DNS ayarsiz - ag hatalari verir: aify backend setup glibc"
		fi
		if [ -f "$AIFY_PREFIX/etc/tls/cert.pem" ]; then _d_ok "CA demeti bulundu (SSL_CERT_FILE)"
		else _d_warn "ca-certificates yok; glibc ikilileri TLS hatasi verebilir (pkg install ca-certificates)"; fi
		# Ayirt edici teshis: Termux'un kendi (bionic) agi calisiyor mu?
		# bionic OK + glibc FAIL  -> sorun glibc'in /etc'sinde (bizim alanimiz)
		# ikisi de FAIL           -> telefonun agi/DNS'i
		if [ -z "${AIFY_SKIP_NET:-}" ] && aify_have curl; then
			local code
			code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 \
				https://oauth2.googleapis.com/token 2>/dev/null || echo 000)"
			if [ "$code" != "000" ]; then _d_ok "Termux (bionic) agi calisiyor - oauth2.googleapis.com HTTP $code"
			else _d_bad "Termux'un kendi agi da erisemiyor; sorun glibc'te degil (veri/wifi, VPN, DNS engeli?)"; fi
		fi
		if [ -n "${AIFY_SKIP_NET:-}" ]; then
			printf '  %s[ ]%s    glibc ad cozumleme testi atlandi (AIFY_SKIP_NET)\n' "$C_DIM" "$C_RESET"
		else
			local dns
			if dns="$(aify_glibc_dns_test 2>&1)"; then
				_d_ok "glibc ad cozumleme calisiyor: $dns"
			else
				_d_bad "glibc ad cozumleme BASARISIZ: $dns"
				printf '       %saify backend setup glibc%s ile resolv.conf yazin;\n' "$C_BOLD" "$C_RESET"
				printf '       kendi DNS'"'"'inizi vermek icin: %saify config set glibc.dns "1.1.1.1 8.8.8.8"%s\n' "$C_BOLD" "$C_RESET"
			fi
		fi
	fi

	_d_head "PATH"
	case ":$PATH:" in
		*":$AIFY_BIN_DIR:"*) _d_ok "$AIFY_BIN_DIR PATH icinde" ;;
		*) _d_bad "$AIFY_BIN_DIR PATH'te degil - yeni bir kabuk acin veya: eval \"\$(aify env)\"" ;;
	esac

	_d_head "Kurulu araclar"
	local any=0 f id
	for f in "$AIFY_STATE_DIR"/*; do
		[ -f "$f" ] || continue
		any=1
		id="$(basename "$f")"
		aify_tool_load "$id" 2>/dev/null || { _d_warn "$id: kayit tanimi yok (registry'den silinmis)"; continue; }
		local backend path class
		backend="$(aify_state_get "$id" backend || echo '?')"
		path="$(aify_state_get "$id" path || echo '')"
		class="$(aify_state_get "$id" class || echo '')"
		if [ "$backend" = proot ]; then
			if aify_backend_available proot; then _d_ok "$id [proot] $path"
			else _d_bad "$id proot ile kurulu ama kap yok: aify backend setup proot"; fi
		elif [ -e "$path" ]; then
			local now; now="$(aify_binary_class "$path")"
			if [ "$now" = "$class" ]; then _d_ok "$id [$backend] $path"
			else _d_warn "$id ikilisi degismis ($class -> $now); 'aify install $id' onerilir"; fi
			[ "$backend" = glibc ] && ! aify_backend_available glibc && _d_bad "$id glibc istiyor ama glibc-runner yok"
			if [ "$backend" = glibc ] && ! aify_is_elf "$path"; then
				_d_bad "$id: glibc arka ucuna ELF olmayan dosya kayitli - 'aify install $id' ile duzelir"
			fi
			if [ "$backend" = glibc ] && [ "$(aify_elf_type "$path")" = exec ]; then
				_d_bad "$id: non-PIE ikili glibc arka ucunda - calistirilamaz"
				printf '       %saify install %s --backend proot%s ile duzelir\n' "$C_BOLD" "$id" "$C_RESET"
			fi
		else
			_d_bad "$id: ikili kayip ($path) - 'aify install $id'"
		fi
		[ -x "$AIFY_BIN_DIR/${TOOL_BIN:-$id}" ] || _d_warn "$id: shim eksik ($AIFY_BIN_DIR/$TOOL_BIN) - 'aify install $id'"
	done
	[ "$any" = 1 ] || printf '  %shic arac kurulu degil - aify list%s\n' "$C_DIM" "$C_RESET"

	if aify_is_termux; then
		_d_head "Termux ipuclari"
		if [ -d "$HOME/storage" ]; then _d_ok "termux-setup-storage yapilmis"
		else _d_warn "paylasimli depolama icin: termux-setup-storage"; fi
		[ -d "$AIFY_PREFIX/etc/profile.d" ] && _d_ok "profile.d destegi var"
	fi

	printf '\n'
	if [ "$_AIFY_DOCTOR_PROBLEMS" -eq 0 ]; then
		printf '%sSorun bulunamadi.%s\n' "$C_GREEN" "$C_RESET"
	else
		printf '%s%s sorun bulundu.%s\n' "$C_YELLOW" "$_AIFY_DOCTOR_PROBLEMS" "$C_RESET"
	fi
	return 0
}
