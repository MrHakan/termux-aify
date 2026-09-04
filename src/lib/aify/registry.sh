#!/usr/bin/env bash
# aify - arac kayit defteri (registry)
# shellcheck shell=bash

# Kayit dizinleri: dahili paylasim dizini + kullanicinin kendi tanimlari.
# Ayni id icin kullanici dosyasi dahili olani ezer.
aify_registry_dirs() {
	printf '%s\n' "$AIFY_SHAREDIR/registry.d"
	printf '%s\n' "$AIFY_HOME/registry.d"
	[ -n "${AIFY_EXTRA_REGISTRY:-}" ] && printf '%s\n' "$AIFY_EXTRA_REGISTRY"
	return 0
}

# Tum arac id'leri (alfabetik, tekil)
aify_tool_ids() {
	local d f
	while read -r d; do
		[ -d "$d" ] || continue
		for f in "$d"/*.tool; do
			[ -e "$f" ] || continue
			basename "$f" .tool
		done
	done < <(aify_registry_dirs) | sort -u
}

# id -> dosya yolu (son bulunan kazanir)
aify_tool_file() {
	local id="$1" d found=''
	while read -r d; do
		[ -f "$d/$id.tool" ] && found="$d/$id.tool"
	done < <(aify_registry_dirs)
	[ -n "$found" ] || return 1
	printf '%s\n' "$found"
}

aify_tool_exists() { aify_tool_file "$1" >/dev/null 2>&1; }

# Arac tanimini yukler; TOOL_* degiskenlerini doldurur.
aify_tool_load() {
	local id="$1" file
	file="$(aify_tool_file "$id")" || return 1

	# Onceki tanimdan kalanlari temizle
	unset TOOL_ID TOOL_NAME TOOL_SUMMARY TOOL_HOMEPAGE TOOL_KIND TOOL_PACKAGE \
	      TOOL_BIN TOOL_ALIASES TOOL_RUNTIME TOOL_BACKENDS TOOL_DEPS TOOL_NPM_OS \
	      TOOL_NPM_CPU TOOL_NPM_LIBC TOOL_NATIVE_BINARY TOOL_INSTALLER_URL \
	      TOOL_INSTALLER_ARGS TOOL_PKG TOOL_NOTES TOOL_AUTH TOOL_TAGS TOOL_ENV \
	      TOOL_PROOT_INSTALL TOOL_VERSION_ARGS
	unset -f tool_post_install 2>/dev/null || true
	# shellcheck disable=SC2034  # arac tanimlari ve run.sh kullanir
	TOOL_ENV=()

	# shellcheck disable=SC1090
	. "$file"

	TOOL_ID="${TOOL_ID:-$id}"
	TOOL_NAME="${TOOL_NAME:-$id}"
	TOOL_BIN="${TOOL_BIN:-$id}"
	TOOL_KIND="${TOOL_KIND:-npm}"
	TOOL_BACKENDS="${TOOL_BACKENDS:-native}"
	TOOL_VERSION_ARGS="${TOOL_VERSION_ARGS:---version}"
	# shellcheck disable=SC2034  # disaridan okunabilsin diye tutuluyor
	TOOL_FILE="$file"
	return 0
}

# Kurulu/kurulu degil isareti ile tek satirlik ozet
aify_tool_line() {
	local id="$1" mark status backend
	aify_tool_load "$id" || return 1
	if aify_is_installed "$id"; then
		backend="$(aify_state_get "$id" backend || echo '?')"
		mark="${C_GREEN}*${C_RESET}"
		status="${C_DIM}kurulu (${backend})${C_RESET}"
	else
		mark=" "
		status="${C_DIM}-${C_RESET}"
	fi
	printf '%s %-12s %-22s %s\n' "$mark" "$TOOL_ID" "$TOOL_NAME" "$status"
}

aify_cmd_list() {
	local id
	printf '%sAraclar%s  (%s: kurulu)\n\n' "$C_BOLD" "$C_RESET" "${C_GREEN}*${C_RESET}"
	while read -r id; do
		aify_tool_line "$id"
	done < <(aify_tool_ids)
	printf '\n%sKurmak icin:%s aify install <id>\n' "$C_DIM" "$C_RESET"
}

aify_cmd_info() {
	local id="${1:-}"
	[ -n "$id" ] || aify_die "kullanim: aify info <id>"
	aify_tool_load "$id" || aify_die "bilinmeyen arac: $id"

	printf '%s%s%s (%s)\n' "$C_BOLD" "$TOOL_NAME" "$C_RESET" "$TOOL_ID"
	[ -n "${TOOL_SUMMARY:-}" ]  && printf '  %s\n' "$TOOL_SUMMARY"
	printf '\n'
	printf '  %-14s %s\n' 'komut:'     "$TOOL_BIN"
	printf '  %-14s %s\n' 'kaynak:'    "$TOOL_KIND${TOOL_PACKAGE:+ / $TOOL_PACKAGE}${TOOL_PKG:+ / $TOOL_PKG}"
	printf '  %-14s %s\n' 'backend:'   "$TOOL_BACKENDS"
	[ -n "${TOOL_DEPS:-}" ]     && printf '  %-14s %s\n' 'gereksinim:' "$TOOL_DEPS"
	[ -n "${TOOL_HOMEPAGE:-}" ] && printf '  %-14s %s\n' 'adres:'      "$TOOL_HOMEPAGE"
	[ -n "${TOOL_AUTH:-}" ]     && printf '  %-14s %s\n' 'giris:'      "$TOOL_AUTH"

	if aify_is_installed "$id"; then
		printf '\n  %sdurum:%s kurulu\n' "$C_GREEN" "$C_RESET"
		local k
		for k in backend version path installed_at; do
			local v; v="$(aify_state_get "$id" "$k" 2>/dev/null || true)"
			[ -n "$v" ] && printf '  %-14s %s\n' "$k:" "$v"
		done
	else
		printf '\n  %sdurum:%s kurulu degil\n' "$C_DIM" "$C_RESET"
	fi

	if [ -n "${TOOL_NOTES:-}" ]; then
		printf '\n%sNotlar:%s\n' "$C_BOLD" "$C_RESET"
		printf '%s\n' "$TOOL_NOTES" | sed 's/^/  /'
	fi
}
