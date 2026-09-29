#!/usr/bin/env bash
# aify - etkilesimli terminal arayuzu (bare 'aify' komutu bunu acar)
# shellcheck shell=bash
#
# Performans: Android'de her alt surec (fork+exec) birkac ms, bazen onlarca ms
# tutar. Onceki surum her tus basisinda ~75 alt surec ve bir 'node --version'
# calistiriyordu (telefonda tus basina yarim saniyeyi asan gecikme). Burada:
#   - cizim tamamen bash yerlesikleriyle yapilir (printf -v, parametre acilimi),
#   - kare bir tampona (UI_BUF) yazilir ve tek printf ile basilir; ekran
#     silinmez, imlec basa alinip satirlar ustune yazilir (titreme olmaz),
#   - ortam satiri, arac listesi ve terminal genisligi yalnizca bir komut
#     calistiktan / pencere boyutu degistikten sonra yeniden hesaplanir.

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

# Claude Code'un turuncusuna yakin bir vurgu rengi
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
	C_ACCENT=$'\033[38;5;209m'
else
	C_ACCENT=''
fi

# Satir sonu: arayuz icinde satirin kalanini da siler (ustune yazarken eski
# karenin artiklari kalmasin), duz ciktida (aify banner) yalnizca \n.
UI_EOL=$'\n'
UI_BUF=''

# --- Ekran yonetimi ----------------------------------------------------------
_ui_enter()   { printf '\033[?1049h\033[?25l\033[H\033[2J'; }
_ui_leave()   { printf '\033[?25h\033[?1049l'; }
_ui_cleanup() { _ui_leave; stty echo 2>/dev/null || true; }

# Terminal genisligi: acilista ve SIGWINCH sonrasinda bir kez olculur.
_ui_measure() {
	local size='' cols=''
	size="$(stty size </dev/tty 2>/dev/null)" && cols="${size#* }"
	case "$cols" in ''|0|*[!0-9]*) cols="${COLUMNS:-72}" ;; esac
	case "$cols" in ''|*[!0-9]*) cols=72 ;; esac
	[ "$cols" -gt 78 ] && cols=78
	[ "$cols" -lt 46 ] && cols=46
	UI_W="$cols"
	UI_RESIZED=''
}

# --- Cizim yardimcilari (hepsi yerlesik; sonuc REPLY'de ya da UI_BUF'ta) ----
_ui_repeat() { # n karakter -> REPLY
	REPLY=''
	[ "$1" -gt 0 ] 2>/dev/null || return 0
	printf -v REPLY '%*s' "$1" ''
	REPLY="${REPLY// /$2}"
}

_ui_put() { UI_BUF+="$1$UI_EOL"; }

_ui_box_top() { # baslik
	local t=" $1 "
	_ui_repeat $((UI_W - 3 - ${#t})) "$UI_H"
	_ui_put "$C_DIM$UI_TL$UI_H$C_RESET$C_BOLD$t$C_RESET$C_DIM$REPLY$UI_TR$C_RESET"
}

_ui_box_bottom() {
	_ui_repeat $((UI_W - 2)) "$UI_H"
	_ui_put "$C_DIM$UI_BL$REPLY$UI_BR$C_RESET"
}

# Icerigin gorunur genisligini cagiran verir: renk kodlarini sonradan
# ayiklamak (sed) her satir icin bir alt surec demekti.
_ui_box_row() { # icerik gorunur_genislik
	local pad=$((UI_W - 4 - $2))
	[ "$pad" -lt 0 ] && pad=0
	printf -v REPLY '%*s' "$pad" ''
	_ui_put "$C_DIM$UI_V$C_RESET $1$REPLY $C_DIM$UI_V$C_RESET"
}

_ui_flush() { printf '%s\033[J' "$UI_BUF"; UI_BUF=''; }

_ui_set_chars() {
	if _ui_unicode; then
		UI_UNI=1
		UI_TL='╭'; UI_TR='╮'; UI_BL='╰'; UI_BR='╯'; UI_H='─'; UI_V='│'
		UI_CUR='❯'; UI_OK='●'; UI_NO='○'; UI_SEP=' · '
	else
		UI_UNI=''
		UI_TL='+'; UI_TR='+'; UI_BL='+'; UI_BR='+'; UI_H='-'; UI_V='|'
		UI_CUR='>'; UI_OK='*'; UI_NO='.'; UI_SEP=' | '
	fi
}

_ui_banner_lines() {
	local a="$C_ACCENT$C_BOLD"
	_ui_put ''
	if [ -n "$UI_UNI" ]; then
		_ui_put "  $a▄▀█ █ █▀▀ █▄█$C_RESET   ${C_BOLD}aify$C_RESET ${C_DIM}v$AIFY_VERSION$C_RESET"
		_ui_put "  $a█▀█ █ █▀░  █ $C_RESET   ${C_DIM}Termux icin yapay zeka CLI yoneticisi$C_RESET"
	else
		_ui_put "  $a  __ _(_)/ _|_   _ $C_RESET"
		_ui_put "  $a / _\` | | |_| | | |$C_RESET   ${C_BOLD}aify v$AIFY_VERSION$C_RESET"
		_ui_put "  $a| (_| | |  _| |_| |$C_RESET   ${C_DIM}Termux icin yapay zeka CLI yoneticisi$C_RESET"
		_ui_put "  $a \\__,_|_|_|  \\__, |$C_RESET"
		_ui_put "  $a             |___/ $C_RESET"
	fi
	_ui_put ''
}

aify_banner() {
	_ui_set_chars
	local UI_BUF='' UI_EOL=$'\n'
	_ui_banner_lines
	printf '%s' "$UI_BUF"
}

# --- Onbellege alinan durum --------------------------------------------------
# Ortam satiri: 'node --version' telefonda yuzlerce ms surebilir; yalnizca
# acilista ve bir komut calistiktan sonra hesaplanir.
_ui_refresh_env() {
	local out b backends='' v
	if aify_is_termux; then out="Termux"; else out="$(uname -s)"; fi
	out+="$UI_SEP$(uname -m)"
	if aify_have node && v="$(node --version 2>/dev/null)"; then
		out+="${UI_SEP}node ${v#v}"
	else
		out+="${UI_SEP}node yok"
	fi
	for b in native glibc proot; do
		aify_backend_available "$b" && backends="${backends:+$backends,}$b"
	done
	out+="${UI_SEP}arka uc: ${backends:-yok}"
	UI_ENV_LINE="  $C_DIM$out$C_RESET"
}

_ui_load_tools() {
	UI_IDS=(); UI_NAMECOL=(); UI_INST=(); UI_BACKEND=(); UI_SUMMARY=(); UI_INSTALLED=0
	local id nc
	_aify_tool_ids_var
	for id in "${AIFY_TOOL_IDS[@]}"; do
		aify_tool_load "$id" || continue
		UI_IDS+=("$id")
		printf -v nc '%-11s %-24s' "$id" "${TOOL_NAME:0:24}"
		UI_NAMECOL+=("$nc")
		UI_SUMMARY+=("${TOOL_SUMMARY:-}")
		if aify_is_installed "$id"; then
			UI_INST+=(1)
			UI_INSTALLED=$((UI_INSTALLED + 1))
			aify_state_var "$id" backend '?'
			UI_BACKEND+=("$REPLY")
		else
			UI_INST+=('')
			UI_BACKEND+=("${TOOL_BACKENDS%% *}")
		fi
	done
	[ "$UI_SEL" -lt "${#UI_IDS[@]}" ] || UI_SEL=0
}

_ui_keyhint() { # tus aciklama ... -> REPLY
	local out='  '
	while [ $# -ge 2 ]; do
		out+="$C_ACCENT$1$C_RESET $2   "
		shift 2
	done
	REPLY="${out%   }"
}

# --- Ana liste ---------------------------------------------------------------
_ui_draw_list() {
	local i n="${#UI_IDS[@]}" glyph vis desc
	UI_BUF=$'\033[H'
	_ui_banner_lines
	_ui_put "$UI_ENV_LINE"
	_ui_put ''
	_ui_box_top "Araclar ($UI_INSTALLED/$n kurulu)"
	for ((i = 0; i < n; i++)); do
		if [ -n "${UI_INST[$i]}" ]; then
			glyph="$C_GREEN$UI_OK$C_RESET"
		else
			glyph="$C_DIM$UI_NO$C_RESET"
		fi
		vis=$((2 + ${#UI_NAMECOL[$i]} + 3 + ${#UI_BACKEND[$i]}))
		if [ "$i" -eq "$UI_SEL" ]; then
			_ui_box_row "$C_ACCENT$UI_CUR$C_RESET $C_BOLD${UI_NAMECOL[$i]}$C_RESET $glyph $C_DIM${UI_BACKEND[$i]}$C_RESET" "$vis"
		else
			_ui_box_row "  $C_DIM${UI_NAMECOL[$i]}$C_RESET $glyph $C_DIM${UI_BACKEND[$i]}$C_RESET" "$vis"
		fi
	done
	_ui_box_bottom
	# Secili aracin aciklamasi: gezinirken ne oldugunu gosterir (tek satira sigar)
	desc="${UI_SUMMARY[$UI_SEL]}"
	[ "${#desc}" -gt $((UI_W - 4)) ] && desc="${desc:0:UI_W-7}..."
	_ui_put "  $C_ACCENT$desc$C_RESET"
	_ui_put ''
	_ui_put "$UI_HINT1"
	_ui_put "$UI_HINT2"
	_ui_put "  ${C_DIM}(yukari/asagi ya da j/k ile gezin)$C_RESET"
	_ui_flush
}

# --- Tus okuma (sonuc REPLY'de; alt kabuk yok) ------------------------------
_ui_key() {
	local k='' rest='' rc=0
	IFS= read -rsn1 k || rc=$?
	if [ "$rc" -ne 0 ]; then
		# >128: bir sinyal (SIGWINCH) okumayi kesti; aksi halde girdi bitti
		if [ "$rc" -gt 128 ]; then REPLY=resize; else REPLY=q; fi
		return 0
	fi
	case "$k" in
		$'\033')
			IFS= read -rsn2 -t 0.2 rest || rest=''
			case "$rest" in
				'[A') REPLY=up ;;
				'[B') REPLY=down ;;
				'[C') REPLY=right ;;
				'[D') REPLY=left ;;
				*)    REPLY=esc ;;
			esac ;;
		'')  REPLY=enter ;;
		' ') REPLY=space ;;
		*)   REPLY="$k" ;;
	esac
}

# --- Komut calistirma (ekrandan cikip geri donerek) --------------------------
_ui_pause() {
	printf '\n%s[devam etmek icin Enter]%s ' "$C_DIM" "$C_RESET"
	read -r _ || true
}

# Komut sonrasi: durum degismis olabilir (kurulum, arka uc), yeniden oku.
_ui_return() {
	_ui_enter
	_ui_load_tools
	_ui_refresh_env
	UI_RESIZED=1   # komut calisirken pencere boyutu degismis olabilir
}

_ui_exec() {
	_ui_leave
	printf '\n%s%s aify %s%s\n\n' "$C_ACCENT$C_BOLD" "$UI_CUR" "$*" "$C_RESET"
	local rc=0
	( main "$@" ) || rc=$?
	if [ "$rc" -ne 0 ]; then
		if [ "$rc" -ge 128 ]; then
			printf '\n%skomut sinyal %s ile sonlandi (cikis %s)%s\n' "$C_RED" "$((rc-128))" "$rc" "$C_RESET"
			printf '%saify doctor%s teshis icin yardimci olabilir\n' "$C_BOLD" "$C_RESET"
		else
			printf '\n%s(cikis kodu %s)%s\n' "$C_DIM" "$rc" "$C_RESET"
		fi
	fi
	_ui_pause
	_ui_return
}

_ui_command_mode() {
	_ui_leave
	printf '\n%saify komutu%s (ornek: install codex, doctor, config list)\n' "$C_BOLD" "$C_RESET"
	printf '%s%s%s ' "$C_ACCENT" "$UI_CUR" "$C_RESET"
	local line
	if read -r line && [ -n "$line" ]; then
		printf '\n'
		# shellcheck disable=SC2086
		( main $line ) || true
	fi
	_ui_pause
	_ui_return
}

_ui_help() {
	_ui_leave
	printf '\n'
	main help
	_ui_pause
	_ui_enter
}

# --- Genel secenek menusu ----------------------------------------------------
# _ui_menu baslik ipucu secenek...
#   UI_MENU_HEAD : kutunun ustune basilacak hazir satirlar (UI_EOL ile)
#   UI_MENU_TAGS : secenek basina soluk ek aciklama (istege bagli)
#   UI_MENU_SEL  : baslangic secimi; donuste son secim
# REPLY: secilen indeks, geri icin -1
_ui_menu() {
	local title="$1" hint="$2"; shift 2
	local n=$# i sel="${UI_MENU_SEL:-0}" label tag
	local -a opts=("$@")
	[ "$sel" -lt "$n" ] || sel=0
	while :; do
		[ -n "$UI_RESIZED" ] && _ui_measure
		UI_BUF=$'\033[H'
		_ui_banner_lines
		UI_BUF+="$UI_MENU_HEAD"
		_ui_box_top "$title"
		for ((i = 0; i < n; i++)); do
			label="${opts[$i]}"
			tag="${UI_MENU_TAGS[$i]:-}"
			if [ "$i" -eq "$sel" ]; then
				_ui_box_row "$C_ACCENT$UI_CUR$C_RESET $C_BOLD$label$C_RESET${tag:+ $C_DIM$tag$C_RESET}" \
					$((2 + ${#label} + ${#tag} + (${#tag} ? 1 : 0)))
			else
				_ui_box_row "  $C_DIM$label$C_RESET${tag:+ $C_DIM$tag$C_RESET}" \
					$((2 + ${#label} + ${#tag} + (${#tag} ? 1 : 0)))
			fi
		done
		_ui_box_bottom
		_ui_put ''
		_ui_put "  $C_DIM$hint$C_RESET"
		_ui_flush
		_ui_key
		case "$REPLY" in
			up|k)        sel=$(( (sel - 1 + n) % n )) ;;
			down|j)      sel=$(( (sel + 1) % n )) ;;
			q|esc|left)  UI_MENU_SEL=$sel; REPLY=-1; return 0 ;;
			enter|right) UI_MENU_SEL=$sel; REPLY=$sel; return 0 ;;
		esac
	done
}

# --- Secili arac icin islem menusu ------------------------------------------
_ui_actions() {
	local id="$1" summary='' max
	aify_tool_load "$id" && summary="${TOOL_SUMMARY:-}"
	# Ozet tek satira sigsin: tasarsa satir kayar ve kutu asagi itilir
	max=$((UI_W - 4 - ${#id}))
	[ "${#summary}" -gt "$max" ] && summary="${summary:0:max-3}..."
	UI_MENU_HEAD="  $C_BOLD$id$C_RESET  $C_DIM$summary$C_RESET$UI_EOL$UI_EOL"
	UI_MENU_TAGS=()
	UI_MENU_SEL=0
	while :; do
		_ui_menu Islem "yukari/asagi ile secin, enter onaylar, q geri" \
			"Bilgi" "Kur / yeniden kur" "Calistir" "Guncelle" "Kaldir" "Arka ucu degistir" "Geri"
		case "$REPLY" in
			0) _ui_exec info "$id" ;;
			1) _ui_exec install "$id" ;;
			2) _ui_exec run "$id" ;;
			3) _ui_exec update "$id" ;;
			4) _ui_exec remove "$id" ;;
			5) _ui_backend_pick "$id"
			   UI_MENU_HEAD="  $C_BOLD$id$C_RESET  $C_DIM$summary$C_RESET$UI_EOL$UI_EOL"
			   UI_MENU_TAGS=(); UI_MENU_SEL=5 ;;
			*) return 0 ;;
		esac
	done
}

_ui_backend_pick() {
	local id="$1" b
	local -a opts=("otomatik (varsayilan)" native glibc proot)
	UI_MENU_TAGS=('')
	for b in native glibc proot; do
		if aify_backend_available "$b"; then UI_MENU_TAGS+=('')
		else UI_MENU_TAGS+=("(kurulmali)"); fi
	done
	UI_MENU_HEAD="  $C_BOLD$id$C_RESET icin arka uc$UI_EOL$UI_EOL"
	UI_MENU_SEL=0
	_ui_menu "Arka uc" "enter secer, q geri" "${opts[@]}"
	case "$REPLY" in
		-1) ;;
		0)  _ui_exec config unset "tool.$id.backend" ;;
		*)  _ui_exec config set "tool.$id.backend" "${opts[$REPLY]}" ;;
	esac
}

_ui_backends_screen() {
	UI_MENU_SEL=0
	while :; do
		UI_MENU_HEAD="$UI_ENV_LINE$UI_EOL$UI_EOL"
		UI_MENU_TAGS=()
		_ui_menu "Arka uclar" "glibc: hafif (~100MB)${UI_SEP}proot: en uyumlu (~500MB)" \
			"glibc arka ucunu kur" "proot arka ucunu kur" "durumu goster" "Geri"
		case "$REPLY" in
			0) _ui_exec backend setup glibc ;;
			1) _ui_exec backend setup proot ;;
			2) _ui_exec backend status ;;
			*) return 0 ;;
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
	UI_EOL=$'\033[K\n'
	UI_SEL=0
	UI_MENU_HEAD='' UI_MENU_SEL=0
	UI_MENU_TAGS=()
	_ui_measure
	_ui_load_tools
	[ "${#UI_IDS[@]}" -gt 0 ] || aify_die "kayit defterinde arac yok"
	_ui_refresh_env
	_ui_keyhint i kur r calistir enter bilgi d sil u guncelle;         UI_HINT1="$REPLY"
	_ui_keyhint b 'arka uclar' t teshis / komut '?' yardim q cikis;  UI_HINT2="$REPLY"

	trap '_ui_cleanup; exit 0' INT TERM
	trap '_ui_cleanup' EXIT
	trap 'UI_RESIZED=1' WINCH
	_ui_enter

	local id
	while :; do
		[ -n "$UI_RESIZED" ] && _ui_measure
		_ui_draw_list
		id="${UI_IDS[$UI_SEL]}"
		_ui_key
		case "$REPLY" in
			up|k)        UI_SEL=$(( (UI_SEL - 1 + ${#UI_IDS[@]}) % ${#UI_IDS[@]} )) ;;
			down|j)      UI_SEL=$(( (UI_SEL + 1) % ${#UI_IDS[@]} )) ;;
			enter|right) _ui_actions "$id" ;;
			i)           _ui_exec install "$id" ;;
			r)           _ui_exec run "$id" ;;
			d)           _ui_exec remove "$id" ;;
			u)           _ui_exec update "$id" ;;
			b)           _ui_backends_screen ;;
			t)           _ui_exec doctor ;;
			s)           _ui_exec setup ;;
			/|:)         _ui_command_mode ;;
			'?'|h)       _ui_help ;;
			q)           break ;;
			*)           : ;;   # esc, resize, bilinmeyen tus: yeniden ciz
		esac
	done

	_ui_cleanup
	trap - EXIT INT TERM WINCH
	printf '%sgorusuruz.%s\n' "$C_DIM" "$C_RESET"
	return 0
}
