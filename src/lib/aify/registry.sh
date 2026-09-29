#!/usr/bin/env bash
# aify - arac kayit defteri (registry)
# shellcheck shell=bash

# Kayit dizinleri: dahili paylasim dizini + kullanicinin kendi tanimlari.
# Ayni id icin kullanici dosyasi dahili olani ezer.
# AIFY_REGISTRY_DIRS dizisi alt surec olmadan dolasilabilsin diye tutulur.
_aify_registry_init() {
	AIFY_REGISTRY_DIRS=("$AIFY_SHAREDIR/registry.d" "$AIFY_HOME/registry.d")
	[ -n "${AIFY_EXTRA_REGISTRY:-}" ] && AIFY_REGISTRY_DIRS+=("$AIFY_EXTRA_REGISTRY")
	return 0
}

aify_registry_dirs() {
	_aify_registry_init
	printf '%s\n' "${AIFY_REGISTRY_DIRS[@]}"
}

# Tum arac id'leri (alfabetik, tekil). sort/basename yerine saf bash:
# liste kucuk (onlarca oge) oldugu icin ekleme siralamasi yeterli.
_aify_tool_ids_var() { # -> AIFY_TOOL_IDS dizisi
	local d f id i j
	local -A seen=()
	AIFY_TOOL_IDS=()
	_aify_registry_init
	for d in "${AIFY_REGISTRY_DIRS[@]}"; do
		[ -d "$d" ] || continue
		for f in "$d"/*.tool; do
			[ -e "$f" ] || continue
			id="${f##*/}"; id="${id%.tool}"
			[ -n "${seen[$id]:-}" ] && continue
			seen[$id]=1
			# Siraya ekle
			i=${#AIFY_TOOL_IDS[@]}
			while [ "$i" -gt 0 ]; do
				j=$((i - 1))
				[[ "${AIFY_TOOL_IDS[$j]}" > "$id" ]] || break
				AIFY_TOOL_IDS[i]="${AIFY_TOOL_IDS[j]}"
				i=$j
			done
			AIFY_TOOL_IDS[i]="$id"
		done
	done
}

aify_tool_ids() {
	_aify_tool_ids_var
	[ ${#AIFY_TOOL_IDS[@]} -eq 0 ] || printf '%s\n' "${AIFY_TOOL_IDS[@]}"
}

# id -> dosya yolu (son bulunan kazanir); REPLY'ye yazar
_aify_tool_file_var() {
	local d
	REPLY=''
	_aify_registry_init
	for d in "${AIFY_REGISTRY_DIRS[@]}"; do
		[ -f "$d/$1.tool" ] && REPLY="$d/$1.tool"
	done
	[ -n "$REPLY" ]
}

aify_tool_file() {
	_aify_tool_file_var "$1" || return 1
	printf '%s\n' "$REPLY"
}

aify_tool_exists() { _aify_tool_file_var "$1"; }

# Arac tanimini yukler; TOOL_* degiskenlerini doldurur.
aify_tool_load() {
	local id="$1" file
	_aify_tool_file_var "$id" || return 1
	file="$REPLY"

	# Onceki tanimdan kalanlari temizle
	unset TOOL_ID TOOL_NAME TOOL_SUMMARY TOOL_HOMEPAGE TOOL_KIND TOOL_PACKAGE \
	      TOOL_BIN TOOL_ALIASES TOOL_RUNTIME TOOL_BACKENDS TOOL_DEPS TOOL_NPM_OS \
	      TOOL_NPM_CPU TOOL_NPM_LIBC TOOL_NATIVE_BINARY TOOL_INSTALLER_URL \
	      TOOL_INSTALLER_ARGS TOOL_PKG TOOL_NOTES TOOL_AUTH TOOL_TAGS TOOL_ENV \
	      TOOL_PROOT_INSTALL TOOL_VERSION_ARGS TOOL_GH_REPO TOOL_GH_MATCH
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
		aify_state_var "$id" backend '?'; backend="$REPLY"
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
	_aify_tool_ids_var
	for id in "${AIFY_TOOL_IDS[@]}"; do
		aify_tool_line "$id"
	done
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
			aify_state_var "$id" "$k"
			[ -n "$REPLY" ] && printf '  %-14s %s\n' "$k:" "$REPLY"
		done
	else
		printf '\n  %sdurum:%s kurulu degil\n' "$C_DIM" "$C_RESET"
	fi

	if [ -n "${TOOL_NOTES:-}" ]; then
		printf '\n%sNotlar:%s\n' "$C_BOLD" "$C_RESET"
		printf '%s\n' "$TOOL_NOTES" | sed 's/^/  /'
	fi
}
