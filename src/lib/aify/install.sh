#!/usr/bin/env bash
# aify - kurulum / kaldirma / guncelleme / calistirma
# shellcheck shell=bash

# --- Termux paket bagimliliklari --------------------------------------------
aify_pkg_installed() {
	if aify_have dpkg; then dpkg -s "$1" >/dev/null 2>&1; else command -v "$1" >/dev/null 2>&1; fi
}

aify_ensure_deps() {
	local deps="$1" missing='' d
	[ -n "$deps" ] || return 0
	for d in $deps; do
		aify_pkg_installed "$d" || missing="$missing $d"
	done
	[ -n "$missing" ] || return 0
	if ! aify_is_termux; then
		aify_warn "Termux disindayiz; su paketleri kendiniz saglayin:$missing"
		return 0
	fi
	aify_info "eksik Termux paketleri kuruluyor:$missing"
	# shellcheck disable=SC2086
	pkg install -y $missing || aify_die "paket kurulumu basarisiz:$missing"
}

# --- npm yardimcilari --------------------------------------------------------
# Termux'ta node process.platform=android oldugu icin npm, os:["linux"] isaretli
# platform paketlerini atlar. --os/--cpu/--libc ile hedefi acikca veriyoruz.
_aify_npm_flags() {
	local -n _out="$1"
	_out=(--no-audit --no-fund --loglevel=error)
	local os="${TOOL_NPM_OS:-}" cpu="${TOOL_NPM_CPU:-}" libc="${TOOL_NPM_LIBC:-}"
	if [ -z "$os" ] && [ "$(aify_node_platform)" = android ]; then os=linux; fi
	[ -n "$os" ]   && _out+=("--os=$os")
	[ -z "$cpu" ]  && cpu="$(aify_npm_cpu)"
	_out+=("--cpu=$cpu")
	[ -n "$libc" ] && _out+=("--libc=$libc")
	return 0
}

_aify_npm_installed_version() {
	local tdir="$1" pkg="$2" pj
	pj="$tdir/lib/node_modules/$pkg/package.json"
	[ -f "$pj" ] || return 1
	sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pj" | head -n1
}

# --- Ikili dosya cozumleme ---------------------------------------------------
# Bir npm "bin" sarmalayicisi gercek mi yoksa "yerli ikili kurulmadi" diyen
# yer tutucu mu? (claude-code 2.x boyle bir stub biraktigi icin gerekli)
_aify_is_stub() {
	local f="$1" size
	size="$(wc -c < "$f" 2>/dev/null || echo 0)"
	[ "$size" -lt 2048 ] || return 1
	grep -qiE 'not installed|unsupported|placeholder|desteklenmiyor' "$f" 2>/dev/null
}

# npm, platform paketlerini bazen tepeye tasir bazen ic ice birakir
# (@github/copilot ve @openai/codex ic ice birakiyor); ikisini de tarariz.
_aify_scan_platform_binary() {
	local tdir="$1" bin="$2" d f cpu
	cpu="$(aify_npm_cpu)"
	while read -r d; do
		[ -d "$d" ] || continue
		f="$(find "$d" -maxdepth 5 -type f -name "$bin" -perm -u+x 2>/dev/null | head -n1)"
		[ -n "$f" ] || f="$(find "$d" -maxdepth 5 -type f -name "$bin" 2>/dev/null | head -n1)"
		[ -n "$f" ] && { printf '%s\n' "$f"; return 0; }
	done < <(find "$tdir/lib/node_modules" -maxdepth 6 -type d \
		\( -name "*linux*$cpu*" -o -name "*linuxmusl*$cpu*" -o -name "*android*$cpu*" \) 2>/dev/null)
	return 1
}

# Sirasiyla: acik tanim > (acik tanim varsa) platform paketi > gecerli
# sarmalayici > platform paketi > ne bulursak.
# Acik tanimi olan araclar yerli ikiliyi ISTIYOR demektir; npm sarmalayicisi
# calisir gorunse bile (copilot'ta oldugu gibi) once ikiliyi ariyoruz.
_aify_resolve_binary() {
	local tdir="$1" bin="$2" glob="${3:-}" cand='' found='' wrapper
	wrapper="$tdir/bin/$bin"

	if [ -n "$glob" ]; then
		# shellcheck disable=SC2086
		for cand in $(cd "$tdir" 2>/dev/null && eval ls -d $glob 2>/dev/null); do
			[ -f "$tdir/$cand" ] && { printf '%s\n' "$tdir/$cand"; return 0; }
		done
		found="$(_aify_scan_platform_binary "$tdir" "$bin")" \
			&& { printf '%s\n' "$found"; return 0; }
	fi

	if [ -f "$wrapper" ] && [ "$(aify_binary_class "$wrapper")" = script ] \
		&& ! _aify_is_stub "$wrapper"; then
		printf '%s\n' "$wrapper"; return 0
	fi

	found="$(_aify_scan_platform_binary "$tdir" "$bin")" \
		&& { printf '%s\n' "$found"; return 0; }

	[ -e "$wrapper" ] && { printf '%s\n' "$wrapper"; return 0; }
	return 1
}

# --- Shim uretimi ------------------------------------------------------------
aify_write_shim() {
	local id="$1" bin="$2" self="${AIFY_SELF:-$AIFY_PREFIX/bin/aify}"
	aify_ensure_dirs
	local shim="$AIFY_BIN_DIR/$bin"
	cat > "$shim" <<SHIM
#!/usr/bin/env bash
# aify tarafindan uretildi - elle duzenlemeyin ($id)
exec "$self" run "$id" "\$@"
SHIM
	chmod +x "$shim"
	printf '%s\n' "$shim"
}

aify_remove_shims() {
	local id="$1" f
	for f in "$AIFY_BIN_DIR"/*; do
		[ -f "$f" ] || continue
		grep -q "^exec .* run \"$id\"" "$f" 2>/dev/null && rm -f "$f"
	done
	return 0
}

# --- Kurulum tipleri ---------------------------------------------------------
_aify_install_npm_native() {
	local id="$1" tdir="$2"
	aify_have npm || aify_die "npm bulunamadi (pkg install nodejs-lts)"
	local flags; _aify_npm_flags flags
	aify_step "npm install -g --prefix $tdir $TOOL_PACKAGE"
	mkdir -p "$tdir"
	npm install -g --prefix "$tdir" "${flags[@]}" "$TOOL_PACKAGE" \
		|| aify_die "npm kurulumu basarisiz: $TOOL_PACKAGE"
}

_aify_install_npm_proot() {
	local id="$1"
	aify_step "kap icinde: npm install -g $TOOL_PACKAGE"
	aify_proot_exec "npm install -g --no-audit --no-fund $(printf '%q' "$TOOL_PACKAGE")" \
		|| aify_die "kap icinde npm kurulumu basarisiz"
}

_aify_install_pkg() {
	aify_is_termux || aify_die "$TOOL_ID icin Termux paketi gerekli (Termux disindasiniz)"
	aify_step "pkg install ${TOOL_PKG:-$TOOL_ID}"
	pkg install -y "${TOOL_PKG:-$TOOL_ID}" || aify_die "pkg kurulumu basarisiz"
}

_aify_install_installer_native() {
	local tdir="$1"
	mkdir -p "$tdir/bin"
	aify_step "resmi kurulum betigi indiriliyor: $TOOL_INSTALLER_URL"
	local script="$AIFY_CACHE_DIR/$TOOL_ID-install.sh"
	aify_download "$TOOL_INSTALLER_URL" "$script" || aify_die "kurulum betigi indirilemedi"
	# shellcheck disable=SC2086
	bash "$script" ${TOOL_INSTALLER_ARGS//@BINDIR@/$tdir/bin} || aify_die "kurulum betigi basarisiz"
}

_aify_install_installer_proot() {
	aify_step "kap icinde resmi kurulum betigi calistiriliyor"
	aify_proot_exec "curl -fsSL $(printf '%q' "$TOOL_INSTALLER_URL") | bash -s -- --dir /usr/local/bin" \
		|| aify_die "kap icinde kurulum basarisiz"
}

_aify_install_uv_proot() {
	aify_step "kap icinde: pipx install $TOOL_PACKAGE"
	aify_proot_exec "command -v pipx >/dev/null 2>&1 || (export DEBIAN_FRONTEND=noninteractive; apt-get install -y -qq pipx >/dev/null); pipx install $(printf '%q' "$TOOL_PACKAGE")" \
		|| aify_die "kap icinde pipx kurulumu basarisiz"
}

_aify_install_uv() {
	local tdir="$1"
	aify_have uv || aify_die "uv bulunamadi (pkg install uv)"
	aify_step "uv tool install $TOOL_PACKAGE"
	UV_TOOL_DIR="$tdir/uv" UV_TOOL_BIN_DIR="$tdir/bin" \
		uv tool install --force "$TOOL_PACKAGE" || aify_die "uv kurulumu basarisiz"
}

# --- GitHub release kurulumu -------------------------------------------------
_aify_arch_alias() { # regex parcasi
	case "$(uname -m)" in
		aarch64|arm64) echo 'arm64|aarch64' ;;
		x86_64|amd64)  echo 'x86_64|amd64|x64' ;;
		armv7l|armv8l) echo 'armv7|armv6|armhf' ;;
		*)             uname -m ;;
	esac
}

_aify_gh_asset_url() {
	local repo="$1" match="$2" urls u
	[ -n "${AIFY_TEST_ASSET_URL:-}" ] && { printf '%s\n' "$AIFY_TEST_ASSET_URL"; return 0; }
	urls="$(aify_fetch "https://api.github.com/repos/$repo/releases/latest" \
		| tr ',' '\n' \
		| sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
	[ -n "$urls" ] || return 1
	# Once .tar.gz, sonra .tgz/.zip; imza/checksum/paket dosyalarini ele
	local pass
	for pass in '\.tar\.gz$' '\.tgz$' '\.zip$' '.'; do
		while read -r u; do
			[ -n "$u" ] || continue
			printf '%s' "$u" | grep -qiE '\.(sha256|sha512|sig|asc|pem|deb|rpm|apk|txt)$' && continue
			printf '%s' "$u" | grep -qE "$match" || continue
			printf '%s' "$u" | grep -qiE "$(_aify_arch_alias)" || continue
			printf '%s' "$u" | grep -qE "$pass" || continue
			printf '%s\n' "$u"; return 0
		done <<< "$urls"
	done
	return 1
}

_aify_install_github() {
	local tdir="$1" url file work
	local match="${TOOL_GH_MATCH:-(Linux|linux)}"
	aify_step "GitHub surumu araniyor: $TOOL_GH_REPO"
	url="$(_aify_gh_asset_url "$TOOL_GH_REPO" "$match")" \
		|| aify_die "$TOOL_GH_REPO icin bu mimariye uygun dosya bulunamadi ($(uname -m))"
	aify_step "indiriliyor: $url"
	mkdir -p "$tdir/bin" "$AIFY_CACHE_DIR"
	file="$AIFY_CACHE_DIR/$(basename "${url%%\?*}")"
	aify_download "$url" "$file" || aify_die "indirme basarisiz: $url"

	work="$tdir/pkg"
	rm -rf "$work"; mkdir -p "$work"
	case "$file" in
		*.tar.gz|*.tgz) tar -xzf "$file" -C "$work" ;;
		*.tar.xz)       tar -xJf "$file" -C "$work" ;;
		*.zip)          aify_have unzip || aify_die "unzip gerekli (pkg install unzip)"; unzip -qo "$file" -d "$work" ;;
		*)              cp "$file" "$work/$TOOL_BIN"; chmod +x "$work/$TOOL_BIN" ;;
	esac

	local found
	found="$(find "$work" -maxdepth 4 -type f -name "$TOOL_BIN" 2>/dev/null | head -n1)"
	[ -n "$found" ] || found="$(find "$work" -maxdepth 2 -type f -perm -u+x 2>/dev/null | head -n1)"
	[ -n "$found" ] || aify_die "arsiv icinde $TOOL_BIN bulunamadi"
	install -m 0755 "$found" "$tdir/bin/$TOOL_BIN"
	rm -rf "$work"
}

_aify_install_github_proot() {
	aify_die "github kaynakli araclar icin proot arka ucu henuz desteklenmiyor; --backend native kullanin"
}

# --- install -----------------------------------------------------------------
aify_cmd_install() {
	local forced_backend='' ids=()
	while [ $# -gt 0 ]; do
		case "$1" in
			-b|--backend) forced_backend="$2"; shift 2 ;;
			-y|--yes) export AIFY_YES=1; shift ;;
			-*) aify_die "bilinmeyen secenek: $1" ;;
			*) ids+=("$1"); shift ;;
		esac
	done
	[ ${#ids[@]} -gt 0 ] || aify_die "kullanim: aify install [--backend native|glibc|proot] <id>..."
	aify_ensure_dirs
	local id
	for id in "${ids[@]}"; do _aify_install_one "$id" "$forced_backend"; done
}

_aify_install_one() {
	local id="$1" forced="$2"
	aify_tool_load "$id" || aify_die "bilinmeyen arac: $id  (aify list)"

	local backend
	if [ -n "$forced" ]; then backend="$forced"; else backend="$(aify_backend_pick "$id")"; fi

	aify_info "$TOOL_NAME kuruluyor  [arka uc: $backend]"

	# proot kurulumun kendisini degistirir (paket kabin icine kurulur), bu yuzden
	# onceden hazir olmali. glibc ise yalnizca calistirmayi etkiler: ikiliyi
	# cozene kadar gercekten gerekip gerekmedigini bilemeyiz, o yuzden burada
	# sart kosmuyoruz - gerekiyorsa kurulum sonrasi uyariyoruz.
	if [ "$backend" = proot ] && ! aify_backend_available proot; then
		aify_warn "proot arka ucu hazir degil"
		if aify_confirm "Simdi kurulsun mu? (aify backend setup proot)"; then
			aify_backend_setup proot
		else
			aify_die "proot arka ucu olmadan $id kurulamaz"
		fi
	fi

	local tdir="$AIFY_TOOLS_DIR/$id"
	local deps="$TOOL_DEPS"
	[ "$backend" = proot ] && deps="${deps//nodejs-lts/}"
	[ "$backend" = proot ] && deps="${deps//nodejs/}"
	aify_ensure_deps "$deps"

	case "$TOOL_KIND:$backend" in
		npm:proot)        _aify_install_npm_proot "$id" ;;
		npm:*)            _aify_install_npm_native "$id" "$tdir" ;;
		installer:proot)  _aify_install_installer_proot ;;
		installer:*)      _aify_install_installer_native "$tdir" ;;
		pkg:*)            _aify_install_pkg ;;
		github:proot)     _aify_install_github_proot ;;
		github:*)         _aify_install_github "$tdir" ;;
		uv:proot)         _aify_install_uv_proot ;;
		uv:*)             _aify_install_uv "$tdir" ;;
		*) aify_die "desteklenmeyen kurulum tipi: $TOOL_KIND ($backend)" ;;
	esac

	# Ikiliyi coz, sinifini belirle, gerekiyorsa arka ucu duzelt
	local binpath='' class='' version=''
	case "$backend" in
		proot)
			binpath="$TOOL_BIN"
			class=proot
			;;
		*)
			case "$TOOL_KIND" in
				pkg) binpath="$(command -v "$TOOL_BIN" 2>/dev/null || echo "$AIFY_PREFIX/bin/$TOOL_BIN")" ;;
				github|uv) binpath="$tdir/bin/$TOOL_BIN"
					[ -e "$binpath" ] || aify_die "kurulum sonrasi $binpath bulunamadi" ;;
				*)   binpath="$(_aify_resolve_binary "$tdir" "$TOOL_BIN" "${TOOL_NATIVE_BINARY:-}")" \
						|| aify_die "kurulum sonrasi $TOOL_BIN bulunamadi ($tdir)" ;;
			esac
			class="$(aify_binary_class "$binpath")"
			aify_step "ikili: $binpath  [$(aify_human_class "$class")]"
			# Arka uc ikilinin sinifini takip etmeli: glibc ELF -> glibc,
			# betik/statik -> native. Tek yonlu duzeltme, npm sarmalayicisini
			# grun'a verip "invalid ELF header" almaya yol aciyordu.
			local want pinned
			want="$(aify_class_backend "$class")"
			pinned="$(aify_config_get "tool.$id.backend" '')"
			if [ -n "$pinned" ]; then
				[ "$pinned" != "$want" ] && aify_warn "arka uc ayarla '$pinned' olarak sabitlenmis, ikili ise $want istiyor"
			elif [ "$want" != "$backend" ]; then
				if [ "$want" = native ]; then
					aify_warn "ikili yerli calisiyor, arka uc '$backend' yerine 'native'"
				elif aify_backend_available "$want"; then
					aify_warn "yerli calistirilamaz, arka uc '$want' olarak degistiriliyor"
				else
					aify_warn "bu ikili $want arka ucu gerektiriyor: aify backend setup $want"
				fi
				backend="$want"
			fi
			if [ "$backend" = glibc ]; then
				[ -x "$binpath" ] || chmod +x "$binpath" 2>/dev/null || true
				if aify_glibc_configure "$binpath"; then
					aify_step "glibc yukleyicisi yamalandi (patchelf)"
				elif [ "$(aify_elf_type "$binpath")" = exec ]; then
					# non-PIE bir ikili yamasiz calistirilamaz: ld.so onu
					# yukleyemez, dogrudan calistirmak da bionic yukleyicisine
					# duser. Tek secenek proot.
					aify_warn "yama basarisiz ve ikili non-PIE; bu arac icin proot gerekiyor:"
					aify_warn "  aify install $id --backend proot"
				fi
			fi
			;;
	esac

	if [ "$TOOL_KIND" = npm ] && [ "$backend" != proot ]; then
		version="$(_aify_npm_installed_version "$tdir" "$TOOL_PACKAGE" 2>/dev/null || true)"
	fi

	aify_state_put "$id" \
		"backend=$backend" \
		"path=$binpath" \
		"class=$class" \
		"kind=$TOOL_KIND" \
		"bin=$TOOL_BIN" \
		"version=${version:-bilinmiyor}" \
		"installed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

	if declare -f tool_post_install >/dev/null; then
		aify_step "kurulum sonrasi ayarlar"
		tool_post_install "$tdir" "$binpath" || aify_warn "tool_post_install uyari verdi"
	fi

	local shim; shim="$(aify_write_shim "$id" "$TOOL_BIN")"
	local a
	for a in ${TOOL_ALIASES:-}; do aify_write_shim "$id" "$a" >/dev/null; done

	aify_ok "$TOOL_NAME hazir -> $TOOL_BIN"
	case ":$PATH:" in
		*":$AIFY_BIN_DIR:"*) ;;
		*) aify_warn "PATH'e ekleyin:  export PATH=\"\$PATH:$AIFY_BIN_DIR\"  (yeni oturumda otomatik)" ;;
	esac
	[ -n "${TOOL_AUTH:-}" ] && aify_say "  ${C_DIM}giris:${C_RESET} $TOOL_AUTH"
	return 0
}

# --- remove ------------------------------------------------------------------
aify_cmd_remove() {
	[ $# -gt 0 ] || aify_die "kullanim: aify remove <id>..."
	local id
	for id in "$@"; do
		aify_tool_load "$id" || aify_die "bilinmeyen arac: $id"
		aify_is_installed "$id" || { aify_warn "$id zaten kurulu degil"; continue; }
		local backend; backend="$(aify_state_get "$id" backend || echo native)"
		aify_info "$TOOL_NAME kaldiriliyor"
		case "$TOOL_KIND:$backend" in
			npm:proot) aify_proot_exec "npm uninstall -g $(printf '%q' "$TOOL_PACKAGE")" || true ;;
			pkg:*)     aify_warn "Termux paketi elle kaldirilir: pkg uninstall ${TOOL_PKG:-$id}" ;;
			*)         rm -rf "${AIFY_TOOLS_DIR:?}/$id" ;;
		esac
		aify_remove_shims "$id"
		aify_state_del "$id"
		aify_ok "$id kaldirildi"
	done
}

# --- update ------------------------------------------------------------------
aify_cmd_update() {
	local ids=()
	if [ $# -eq 0 ] || [ "${1:-}" = "--all" ]; then
		local f
		for f in "$AIFY_STATE_DIR"/*; do [ -f "$f" ] && ids+=("$(basename "$f")"); done
	else
		ids=("$@")
	fi
	[ ${#ids[@]} -gt 0 ] || { aify_warn "guncellenecek kurulu arac yok"; return 0; }
	local id
	for id in "${ids[@]}"; do
		aify_tool_load "$id" || { aify_warn "bilinmeyen arac: $id"; continue; }
		aify_is_installed "$id" || { aify_warn "$id kurulu degil"; continue; }
		local backend; backend="$(aify_state_get "$id" backend || echo native)"
		aify_info "$TOOL_NAME guncelleniyor [$backend]"
		_aify_install_one "$id" "$backend"
	done
}
