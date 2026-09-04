#!/usr/bin/env bash
# aify - etkilesimli terminal arayuzu (bare 'aify' komutu bunu acar)
# shellcheck shell=bash

# --- Yetenek tespiti ---------------------------------------------------------
aify_ui_supported() { [ -t 0 ] && [ -t 1 ]; }

_ui_unicode() {
	[ -n "${AIFY_ASCII:-}" ] && return 1
	case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
		*UTF-8*|*utf-8*|*UTF8*|*utf8*) return 0 ;;
		'') return 0 ;;   # Termux'ta genelde tanimsiz ama UTF-8'dir
		*) return 1 ;;
	esac
}

_ui_cols() {
	local c
	c="$(tput cols 2>/dev/null || echo 72)"
	[ "$c" -gt 78 ] 2>/dev/null && c=78
	[ "$c" -lt 46 ] 2>/dev/null && c=46
	printf '%s\n' "$c"
}

# Claude Code'un turuncusuna yakin bir vurgu rengi
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
	C_ACCENT=$'\033[38;5;209m'
else
	C_ACCENT=''
fi

# --- Ekran yonetimi ----------------------------------------------------------
_ui_enter()  { printf '\033[?1049h\033[?25l'; }
_ui_leave()  { printf '\033[?25h\033[?1049l'; }
_ui_clear()  { printf '\033[H\033[2J'; }
_ui_cleanup() { _ui_leave; stty echo 2>/dev/null || true; }

# --- Cizim yardimcilari ------------------------------------------------------
_ui_repeat() { local n="$1" ch="$2" out='' i=0; while [ "$i" -lt "$n" ]; do out="$out$ch"; i=$((i+1)); done; printf '%s' "$out"; }

# Gorunur genislik: ANSI dizileri sayilmaz; cok baytli glifler tek sutun sayilir
# (yerel ayar C ise ${#s} bayt saydigi icin glifleri once ASCII'ye indiriyoruz)
_ui_width() {
	local s="$1"
	s="$(printf '%s' "$s" | sed 's/\x1b\[[0-9;]*m//g')"
	s="${s//$UI_CUR/>}"
	s="${s//$UI_OK/*}"
	s="${s//$UI_NO/.}"
	s="${s//$UI_V/|}"
	printf '%s' "${#s}"
}

_ui_line() { # sol_kose orta sag_kose genislik
	local l="$1" m="$2" r="$3" w="$4"
	printf '%s%s%s%s%s\n' "$C_DIM" "$l" "$(_ui_repeat $((w-2)) "$m")" "$r" "$C_RESET"
}

_ui_row() { # icerik genislik
	local content="$1" w="$2" vis pad
	vis="$(_ui_width "$content")"
	pad=$((w - 4 - vis)); [ "$pad" -lt 0 ] && pad=0
	printf '%s%s%s %s%s %s%s%s\n' "$C_DIM" "$UI_V" "$C_RESET" "$content" "$(_ui_repeat "$pad" ' ')" "$C_DIM" "$UI_V" "$C_RESET"
}

_ui_set_chars() {
	if _ui_unicode; then
		UI_TL='╭'; UI_TR='╮'; UI_BL='╰'; UI_BR='╯'; UI_H='─'; UI_V='│'
		UI_CUR='❯'; UI_OK='●'; UI_NO='○'
	else
		UI_TL='+'; UI_TR='+'; UI_BL='+'; UI_BR='+'; UI_H='-'; UI_V='|'
		UI_CUR='>'; UI_OK='*'; UI_NO='.'
	fi
}

aify_banner() {
	_ui_set_chars
	printf '\n'
	if _ui_unicode; then
		printf '  %s▄▀█ █ █▀▀ █▄█%s   %saify%s %sv%s%s\n' \
			"$C_ACCENT$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET" "$C_DIM" "$AIFY_VERSION" "$C_RESET"
		printf '  %s█▀█ █ █▀░  █ %s   %sTermux icin yapay zeka CLI yoneticisi%s\n' \
			"$C_ACCENT$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
	else
		printf '  %s  __ _(_)/ _|_   _ %s\n'  "$C_ACCENT$C_BOLD" "$C_RESET"
		printf '  %s / _` | | |_| | | |%s   %saify v%s%s\n' "$C_ACCENT$C_BOLD" "$C_RESET" "$C_BOLD" "$AIFY_VERSION" "$C_RESET"
		printf '  %s| (_| | |  _| |_| |%s   %sTermux icin yapay zeka CLI yoneticisi%s\n' "$C_ACCENT$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
		printf '  %s \\__,_|_|_|  \\__, |%s\n' "$C_ACCENT$C_BOLD" "$C_RESET"
		printf '  %s             |___/ %s\n' "$C_ACCENT$C_BOLD" "$C_RESET"
	fi
	printf '\n'
}

_ui_env_line() {
	local parts=()
	if aify_is_termux; then parts+=("Termux"); else parts+=("$(uname -s)"); fi
	parts+=("$(uname -m)")
	if aify_have node; then parts+=("node $(node --version 2>/dev/null | tr -d v)"); else parts+=("node yok"); fi
	local backends=''
	local b
	for b in native glibc proot; do
		aify_backend_available "$b" && backends="${backends:+$backends,}$b"
	done
	parts+=("arka uc: ${backends:-yok}")
	local sep out=''
	if _ui_unicode; then sep=' · '; else sep=' | '; fi
	local p
	for p in "${parts[@]}"; do out="${out:+$out$sep}$p"; done
	printf '  %s%s%s\n' "$C_DIM" "$out" "$C_RESET"
}

# --- Ana liste ---------------------------------------------------------------
_ui_load_tools() {
	UI_IDS=(); UI_NAMES=(); UI_STATE=(); UI_BACKEND=()
	local id
	while read -r id; do
		aify_tool_load "$id" || continue
		UI_IDS+=("$id")
		UI_NAMES+=("$TOOL_NAME")
		if aify_is_installed "$id"; then
			UI_STATE+=("kurulu")
			UI_BACKEND+=("$(aify_state_get "$id" backend 2>/dev/null || echo '?')")
		else
			UI_STATE+=("-")
			UI_BACKEND+=("${TOOL_BACKENDS%% *}")
		fi
	done < <(aify_tool_ids)
}

_ui_draw_list() {
	local w; w="$(_ui_cols)"
	_ui_clear
	aify_banner
	_ui_env_line
	printf '\n'

	local title=" Araclar "
	printf '%s%s%s%s%s%s\n' "$C_DIM" "$UI_TL" "$UI_H" "$C_RESET$C_BOLD$title$C_RESET$C_DIM" \
		"$(_ui_repeat $((w - 3 - ${#title})) "$UI_H")" "$UI_TR$C_RESET"

	local i=0 row glyph namecol
	while [ "$i" -lt "${#UI_IDS[@]}" ]; do
		if [ "${UI_STATE[$i]}" = kurulu ]; then
			glyph="$C_GREEN$UI_OK$C_RESET"
		else
			glyph="$C_DIM$UI_NO$C_RESET"
		fi
		namecol="$(printf '%-11s %-24s' "${UI_IDS[$i]}" "${UI_NAMES[$i]:0:24}")"
		if [ "$i" -eq "$UI_SEL" ]; then
			row="$C_ACCENT$UI_CUR$C_RESET $C_BOLD$namecol$C_RESET $glyph $C_DIM${UI_BACKEND[$i]}$C_RESET"
		else
			row="  $C_DIM$namecol$C_RESET $glyph $C_DIM${UI_BACKEND[$i]}$C_RESET"
		fi
		_ui_row "$row" "$w"
		i=$((i+1))
	done
	_ui_line "$UI_BL" "$UI_H" "$UI_BR" "$w"

	printf '\n'
	printf '  %s%s%s kur   %s%s%s calistir   %s%s%s bilgi   %s%s%s sil   %s%s%s guncelle\n' \
		"$C_ACCENT" i "$C_RESET" "$C_ACCENT" r "$C_RESET" "$C_ACCENT" enter "$C_RESET" \
		"$C_ACCENT" d "$C_RESET" "$C_ACCENT" u "$C_RESET"
	printf '  %s%s%s arka uclar   %s%s%s teshis   %s%s%s komut   %s%s%s yardim   %s%s%s cikis\n' \
		"$C_ACCENT" b "$C_RESET" "$C_ACCENT" t "$C_RESET" "$C_ACCENT" / "$C_RESET" \
		"$C_ACCENT" '?' "$C_RESET" "$C_ACCENT" q "$C_RESET"
	printf '  %s(yukari/asagi ya da j/k ile gezin)%s\n' "$C_DIM" "$C_RESET"
}

# --- Tus okuma ---------------------------------------------------------------
_ui_key() {
	local k rest
	IFS= read -rsn1 k 2>/dev/null || { printf 'q\n'; return; }
	case "$k" in
		$'\033')
			IFS= read -rsn2 -t 0.2 rest 2>/dev/null || rest=''
			case "$rest" in
				'[A') printf 'up\n' ;;
				'[B') printf 'down\n' ;;
				'[C') printf 'right\n' ;;
				'[D') printf 'left\n' ;;
				*)    printf 'esc\n' ;;
			esac ;;
		'')  printf 'enter\n' ;;
		' ') printf 'space\n' ;;
		*)   printf '%s\n' "$k" ;;
	esac
}

# --- Komut calistirma (ekrandan cikip geri donerek) --------------------------
_ui_exec() {
	_ui_leave
	printf '\n%s%s aify %s%s\n\n' "$C_ACCENT$C_BOLD" "${UI_CUR:->}" "$*" "$C_RESET"
	( main "$@" ) || true
	printf '\n%s[devam etmek icin Enter]%s ' "$C_DIM" "$C_RESET"
	read -r _ || true
	_ui_enter
	_ui_load_tools
}

_ui_command_mode() {
	_ui_leave
	printf '\n%saify komutu%s (ornek: install gemini, doctor, config list)\n' "$C_BOLD" "$C_RESET"
	printf '%s%s%s ' "$C_ACCENT" "${UI_CUR:->}" "$C_RESET"
	local line
	if read -r line && [ -n "$line" ]; then
		printf '\n'
		# shellcheck disable=SC2086
		( main $line ) || true
	fi
	printf '\n%s[devam etmek icin Enter]%s ' "$C_DIM" "$C_RESET"
	read -r _ || true
	_ui_enter
	_ui_load_tools
}

_ui_help() {
	_ui_leave
	printf '\n'
	main help
	printf '\n%s[devam etmek icin Enter]%s ' "$C_DIM" "$C_RESET"
	read -r _ || true
	_ui_enter
}

# --- Secili arac icin islem menusu ------------------------------------------
_ui_actions() {
	local id="$1" sel=0
	local labels=("Bilgi" "Kur / yeniden kur" "Calistir" "Guncelle" "Kaldir" "Arka ucu degistir" "Geri")
	while :; do
		local w; w="$(_ui_cols)"
		_ui_clear
		aify_banner
		printf '  %s%s%s  %s%s%s\n\n' "$C_BOLD" "$id" "$C_RESET" "$C_DIM" "$(aify_tool_load "$id" && printf '%s' "$TOOL_SUMMARY")" "$C_RESET"
		local title=" Islem "
		printf '%s%s%s%s%s%s\n' "$C_DIM" "$UI_TL" "$UI_H" "$C_RESET$C_BOLD$title$C_RESET$C_DIM" \
			"$(_ui_repeat $((w - 3 - ${#title})) "$UI_H")" "$UI_TR$C_RESET"
		local i=0
		while [ "$i" -lt "${#labels[@]}" ]; do
			if [ "$i" -eq "$sel" ]; then
				_ui_row "$C_ACCENT$UI_CUR$C_RESET $C_BOLD${labels[$i]}$C_RESET" "$w"
			else
				_ui_row "  $C_DIM${labels[$i]}$C_RESET" "$w"
			fi
			i=$((i+1))
		done
		_ui_line "$UI_BL" "$UI_H" "$UI_BR" "$w"
		printf '\n  %syukari/asagi ile secin, enter onaylar, q geri%s\n' "$C_DIM" "$C_RESET"

		case "$(_ui_key)" in
			up|k)    sel=$(( (sel - 1 + ${#labels[@]}) % ${#labels[@]} )) ;;
			down|j)  sel=$(( (sel + 1) % ${#labels[@]} )) ;;
			q|esc|left) return 0 ;;
			enter|right)
				case "$sel" in
					0) _ui_exec info "$id" ;;
					1) _ui_exec install "$id" ;;
					2) _ui_exec run "$id" ;;
					3) _ui_exec update "$id" ;;
					4) _ui_exec remove "$id" ;;
					5) _ui_backend_pick "$id" ;;
					6) return 0 ;;
				esac ;;
		esac
	done
}

_ui_backend_pick() {
	local id="$1" sel=0
	local opts=("otomatik (varsayilan)" "native" "glibc" "proot")
	while :; do
		local w; w="$(_ui_cols)"
		_ui_clear
		aify_banner
		printf '  %s%s%s icin arka uc\n\n' "$C_BOLD" "$id" "$C_RESET"
		local title=" Arka uc "
		printf '%s%s%s%s%s%s\n' "$C_DIM" "$UI_TL" "$UI_H" "$C_RESET$C_BOLD$title$C_RESET$C_DIM" \
			"$(_ui_repeat $((w - 3 - ${#title})) "$UI_H")" "$UI_TR$C_RESET"
		local i=0 hint
		while [ "$i" -lt "${#opts[@]}" ]; do
			hint=''
			case "${opts[$i]}" in
				native) aify_backend_available native || hint=" $C_DIM(hazir degil)$C_RESET" ;;
				glibc)  aify_backend_available glibc  || hint=" $C_DIM(kurulmali)$C_RESET" ;;
				proot)  aify_backend_available proot  || hint=" $C_DIM(kurulmali)$C_RESET" ;;
			esac
			if [ "$i" -eq "$sel" ]; then
				_ui_row "$C_ACCENT$UI_CUR$C_RESET $C_BOLD${opts[$i]}$C_RESET$hint" "$w"
			else
				_ui_row "  $C_DIM${opts[$i]}$C_RESET$hint" "$w"
			fi
			i=$((i+1))
		done
		_ui_line "$UI_BL" "$UI_H" "$UI_BR" "$w"
		printf '\n  %senter secer, q geri%s\n' "$C_DIM" "$C_RESET"
		case "$(_ui_key)" in
			up|k)   sel=$(( (sel - 1 + ${#opts[@]}) % ${#opts[@]} )) ;;
			down|j) sel=$(( (sel + 1) % ${#opts[@]} )) ;;
			q|esc|left) return 0 ;;
			enter|right)
				if [ "$sel" -eq 0 ]; then
					_ui_exec config unset "tool.$id.backend"
				else
					_ui_exec config set "tool.$id.backend" "${opts[$sel]}"
				fi
				return 0 ;;
		esac
	done
}

_ui_backends_screen() {
	local sel=0
	local opts=("glibc arka ucunu kur" "proot arka ucunu kur" "durumu goster" "Geri")
	while :; do
		local w; w="$(_ui_cols)"
		_ui_clear
		aify_banner
		_ui_env_line
		printf '\n'
		local title=" Arka uclar "
		printf '%s%s%s%s%s%s\n' "$C_DIM" "$UI_TL" "$UI_H" "$C_RESET$C_BOLD$title$C_RESET$C_DIM" \
			"$(_ui_repeat $((w - 3 - ${#title})) "$UI_H")" "$UI_TR$C_RESET"
		local i=0
		while [ "$i" -lt "${#opts[@]}" ]; do
			if [ "$i" -eq "$sel" ]; then
				_ui_row "$C_ACCENT$UI_CUR$C_RESET $C_BOLD${opts[$i]}$C_RESET" "$w"
			else
				_ui_row "  $C_DIM${opts[$i]}$C_RESET" "$w"
			fi
			i=$((i+1))
		done
		_ui_line "$UI_BL" "$UI_H" "$UI_BR" "$w"
		printf '\n  %sglibc: hafif (~100MB) · proot: en uyumlu (~500MB)%s\n' "$C_DIM" "$C_RESET"
		case "$(_ui_key)" in
			up|k)   sel=$(( (sel - 1 + ${#opts[@]}) % ${#opts[@]} )) ;;
			down|j) sel=$(( (sel + 1) % ${#opts[@]} )) ;;
			q|esc|left) return 0 ;;
			enter|right)
				case "$sel" in
					0) _ui_exec backend setup glibc ;;
					1) _ui_exec backend setup proot ;;
					2) _ui_exec backend status ;;
					3) return 0 ;;
				esac ;;
		esac
	done
}

# --- Ana dongu ---------------------------------------------------------------
aify_ui() {
	if ! aify_ui_supported; then
		aify_banner
		aify_warn "etkilesimli arayuz icin bir terminal gerekli; 'aify help' cikti veriyor"
		main help
		return 0
	fi
	aify_ensure_dirs
	_ui_set_chars
	UI_SEL=0
	_ui_load_tools
	[ "${#UI_IDS[@]}" -gt 0 ] || aify_die "kayit defterinde arac yok"

	trap '_ui_cleanup; exit 0' INT TERM
	trap '_ui_cleanup' EXIT
	_ui_enter

	while :; do
		_ui_draw_list
		local id="${UI_IDS[$UI_SEL]}"
		case "$(_ui_key)" in
			up|k)      UI_SEL=$(( (UI_SEL - 1 + ${#UI_IDS[@]}) % ${#UI_IDS[@]} )) ;;
			down|j)    UI_SEL=$(( (UI_SEL + 1) % ${#UI_IDS[@]} )) ;;
			enter|right) _ui_actions "$id" ;;
			i)         _ui_exec install "$id" ;;
			r)         _ui_exec run "$id" ;;
			d)         _ui_exec remove "$id" ;;
			u)         _ui_exec update "$id" ;;
			b)         _ui_backends_screen ;;
			t)         _ui_exec doctor ;;
			s)         _ui_exec setup ;;
			/|:)       _ui_command_mode ;;
			'?'|h)     _ui_help ;;
			q)         break ;;
			esc)       : ;;
		esac
	done

	_ui_cleanup
	trap - EXIT INT TERM
	printf '%sgorusuruz.%s\n' "$C_DIM" "$C_RESET"
	return 0
}
