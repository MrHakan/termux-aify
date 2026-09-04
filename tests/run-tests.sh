#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2034,SC2012
# aify - bagimsiz test kosucusu (Termux disinda da calisir)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIFY="$ROOT/src/bin/aify"
PASS=0; FAIL=0

ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

check() { # aciklama komut...
	local desc="$1"; shift
	if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc  ($*)"; fi
}

contains() { # aciklama beklenen komut...
	local desc="$1" want="$2"; shift 2
	local out; out="$("$@" 2>&1)"
	if printf '%s' "$out" | grep -q -- "$want"; then ok "$desc"
	else bad "$desc  ('$want' ciktida yok)"; fi
}

export AIFY_HOME; AIFY_HOME="$(mktemp -d)"
export AIFY_YES=1 NO_COLOR=1
trap 'rm -rf "$AIFY_HOME"' EXIT

head_ "1. Sozdizimi"
for f in "$ROOT"/src/bin/aify "$ROOT"/src/lib/aify/*.sh "$ROOT"/packaging/build-deb.sh "$ROOT"/install.sh "$ROOT"/tests/run-tests.sh "$ROOT"/src/etc/profile.d/aify.sh; do
	check "bash -n $(basename "$f")" bash -n "$f"
done

head_ "2. Temel komutlar"
contains "aify version" "aify 0." "$AIFY" version
contains "aify help" "KOMUTLAR" "$AIFY" help
contains "aify list claude iceriyor" "claude" "$AIFY" list
contains "aify list codex iceriyor" "codex" "$AIFY" list
contains "aify list gh iceriyor" "gh" "$AIFY" list
contains "aify info codex paketi gosteriyor" "@openai/codex" "$AIFY" info codex
contains "aify info bilinmeyen hata veriyor" "bilinmeyen arac" "$AIFY" info yok-boyle-bir-sey
contains "aify backend status" "native" "$AIFY" backend status
check    "aify doctor 0 ile cikiyor" "$AIFY" doctor

head_ "3. Kayit dosyalari"
n=0
for f in "$ROOT"/src/share/aify/registry.d/*.tool; do
	id="$(basename "$f" .tool)"; n=$((n+1))
	( set -e
	  TOOL_ENV=(); . "$f"
	  [ "${TOOL_ID:-}" = "$id" ] || { echo "TOOL_ID != dosya adi"; exit 1; }
	  [ -n "${TOOL_NAME:-}" ] && [ -n "${TOOL_KIND:-}" ] && [ -n "${TOOL_BIN:-}" ] && [ -n "${TOOL_BACKENDS:-}" ]
	  case "${TOOL_KIND}" in
		npm)       [ -n "${TOOL_PACKAGE:-}" ] ;;
		pkg)       [ -n "${TOOL_PKG:-}" ] ;;
		installer) [ -n "${TOOL_INSTALLER_URL:-}" ] ;;
		github)    [ -n "${TOOL_GH_REPO:-}" ] ;;
		uv)        [ -n "${TOOL_PACKAGE:-}" ] ;;
		*) echo "bilinmeyen TOOL_KIND: $TOOL_KIND"; exit 1 ;;
	  esac
	  for b in $TOOL_BACKENDS; do
		case "$b" in native|glibc|proot) ;; *) echo "gecersiz backend: $b"; exit 1 ;; esac
	  done
	) >/dev/null 2>&1 && ok "kayit gecerli: $id" || bad "kayit hatali: $id"
done
[ "$n" -ge 10 ] && ok "$n arac tanimi bulundu" || bad "beklenenden az arac tanimi ($n)"

head_ "4. Config"
"$AIFY" config set test.anahtar deger >/dev/null 2>&1
contains "config set/get" "deger" "$AIFY" config get test.anahtar
"$AIFY" config unset test.anahtar >/dev/null 2>&1
out="$("$AIFY" config get test.anahtar 2>/dev/null)"
[ -z "$out" ] && ok "config unset" || bad "config unset (deger hala var: $out)"

head_ "5. Kullanici tanimli araclar"
"$AIFY" add-npm "@scope/harika-cli" --id harika --bin harika >/dev/null 2>&1
check    "add-npm dosya yazdi" test -f "$AIFY_HOME/registry.d/harika.tool"
contains "add-npm listede gorunuyor" "harika" "$AIFY" list
"$AIFY" add-gh "kullanici/depo" --id depo >/dev/null 2>&1
check    "add-gh dosya yazdi" test -f "$AIFY_HOME/registry.d/depo.tool"

head_ "6. ELF sinifi tespiti"
. "$ROOT/src/lib/aify/core.sh"
tmpscript="$AIFY_HOME/betik"; printf '#!/bin/sh\necho hi\n' > "$tmpscript"; chmod +x "$tmpscript"
[ "$(aify_binary_class "$tmpscript")" = script ] && ok "betik tespiti" || bad "betik tespiti"
[ "$(aify_binary_class "$AIFY_HOME/yok-boyle")" = missing ] && ok "eksik dosya tespiti" || bad "eksik dosya tespiti"
if [ -x /bin/ls ]; then
	cls="$(aify_binary_class /bin/ls)"
	case "$cls" in glibc|musl|static) ok "/bin/ls sinifi: $cls" ;; *) bad "/bin/ls sinifi beklenmedik: $cls" ;; esac
fi

head_ "7. GitHub kaynakli kurulum (yerel arsiv ile)"
fake="$AIFY_HOME/fake"; mkdir -p "$fake"
printf '#!/bin/sh\necho "crush 9.9.9"\n' > "$fake/crush"; chmod +x "$fake/crush"
tar -czf "$AIFY_HOME/crush.tar.gz" -C "$fake" crush
AIFY_TEST_ASSET_URL="file://$AIFY_HOME/crush.tar.gz" "$AIFY" install crush >/dev/null 2>&1
check    "crush kuruldu (state)" test -f "$AIFY_HOME/state/crush"
check    "crush ikilisi yerinde" test -x "$AIFY_HOME/tools/crush/bin/crush"
check    "crush shim'i olustu" test -x "$AIFY_HOME/bin/crush"
contains "crush calisiyor" "9.9.9" "$AIFY" run crush
contains "kisayol: aify crush" "9.9.9" "$AIFY" crush
contains "doctor kurulu araci goruyor" "crush" "$AIFY" doctor
"$AIFY" remove crush >/dev/null 2>&1
[ ! -f "$AIFY_HOME/state/crush" ] && ok "crush kaldirildi" || bad "crush kaldirilmadi"
[ ! -e "$AIFY_HOME/bin/crush" ] && ok "shim temizlendi" || bad "shim temizlenmedi"

head_ "8. Ikili cozumleme (npm yerlesimleri)"
. "$ROOT/src/lib/aify/install.sh" 2>/dev/null || true
fakenpm="$AIFY_HOME/fakenpm"
mkdir -p "$fakenpm/bin" "$fakenpm/lib/node_modules/@anthropic-ai/claude-code-linux-$(aify_npm_cpu)"
# claude-code 2.x tarzi "stub" sarmalayici
cat > "$fakenpm/bin/claude" <<'STUB'
echo "Error: claude native binary not installed." >&2
exit 1
STUB
chmod +x "$fakenpm/bin/claude"
printf '#!/bin/sh\necho "gercek claude"\n' > "$fakenpm/lib/node_modules/@anthropic-ai/claude-code-linux-$(aify_npm_cpu)/claude"
chmod +x "$fakenpm/lib/node_modules/@anthropic-ai/claude-code-linux-$(aify_npm_cpu)/claude"
res="$(_aify_resolve_binary "$fakenpm" claude "" || true)"
case "$res" in
	*node_modules/@anthropic-ai/*) ok "stub sarmalayici atlandi, platform ikilisi secildi" ;;
	*) bad "stub atlanmadi: $res" ;;
esac
# Ic ice (nested) yerlesim de bulunmali
nested="$AIFY_HOME/nested"
mkdir -p "$nested/bin" "$nested/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-$(aify_npm_cpu)/vendor/triple/bin"
printf '#!/bin/sh\necho x\n' > "$nested/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-$(aify_npm_cpu)/vendor/triple/bin/codex"
chmod +x "$nested/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-$(aify_npm_cpu)/vendor/triple/bin/codex"
res="$(_aify_resolve_binary "$nested" codex "" || true)"
case "$res" in
	*/vendor/triple/bin/codex) ok "ic ice platform paketi bulundu" ;;
	*) bad "ic ice paket bulunamadi: $res" ;;
esac

head_ "9. glibc ikilisinde arka uc otomatik degisiyor"
if [ "$(aify_binary_class /bin/ls)" = glibc ]; then
	glibcdir="$AIFY_HOME/glibctest"; mkdir -p "$glibcdir"
	cp /bin/ls "$glibcdir/sahte"
	tar -czf "$AIFY_HOME/sahte.tar.gz" -C "$glibcdir" sahte
	"$AIFY" add-gh "test/sahte" --id sahte --bin sahte >/dev/null 2>&1
	AIFY_TEST_ASSET_URL="file://$AIFY_HOME/sahte.tar.gz" "$AIFY" install sahte >/dev/null 2>&1 || true
	if grep -q '^backend=glibc' "$AIFY_HOME/state/sahte" 2>/dev/null; then
		ok "glibc ikilisi icin arka uc 'glibc' olarak kaydedildi"
	else
		bad "arka uc degismedi: $(grep '^backend=' "$AIFY_HOME/state/sahte" 2>/dev/null)"
	fi
	grep -q '^class=glibc' "$AIFY_HOME/state/sahte" 2>/dev/null && ok "sinif glibc olarak kaydedildi" || bad "sinif yanlis"
else
	printf '  atlandi (bu makinede /bin/ls glibc degil)\n'
fi

head_ "10. Paketleme"
if command -v dpkg-deb >/dev/null 2>&1 || command -v ar >/dev/null 2>&1; then
	OUT_DIR="$AIFY_HOME/dist" BUILD_DIR="$AIFY_HOME/build" "$ROOT/packaging/build-deb.sh" >/dev/null 2>&1
	deb="$(ls "$AIFY_HOME"/dist/aify_*_all.deb 2>/dev/null | head -n1)"
	if [ -n "$deb" ]; then
		ok "deb uretildi: $(basename "$deb")"
		if command -v dpkg-deb >/dev/null 2>&1; then
			contains "deb icinde bin/aify var" "files/usr/bin/aify" dpkg-deb -c "$deb"
			contains "deb icinde registry var" "share/aify/registry.d/claude.tool" dpkg-deb -c "$deb"
			contains "deb icinde profile.d var" "etc/profile.d/aify.sh" dpkg-deb -c "$deb"
			contains "deb Architecture: all" "all" dpkg-deb -f "$deb" Architecture
			contains "deb Package: aify" "aify" dpkg-deb -f "$deb" Package
		fi
	else
		bad "deb uretilemedi"
	fi
else
	printf '  atlandi (dpkg-deb/ar yok)\n'
fi

head_ "11. apt deposu"
if command -v dpkg-scanpackages >/dev/null 2>&1; then
	site="$AIFY_HOME/site"
	deb2="$(ls "$AIFY_HOME"/dist/aify_*_all.deb 2>/dev/null | head -n1)"
	if [ -n "$deb2" ] && "$ROOT/packaging/build-apt-repo.sh" --out "$site" --deb "$deb2" >/dev/null 2>&1; then
		ok "apt deposu uretildi"
		check    "Release dosyasi var" test -f "$site/dists/aify/Release"
		contains "Release SHA256 iceriyor" "SHA256:" cat "$site/dists/aify/Release"
		contains "Release aarch64 indeksini listeliyor" "main/binary-aarch64/Packages" cat "$site/dists/aify/Release"
		contains "Packages paketi listeliyor" "Package: aify" cat "$site/dists/aify/main/binary-aarch64/Packages"
		contains "Filename havuzu gosteriyor" "pool/main/a/aify/aify_" cat "$site/dists/aify/main/binary-all/Packages"
		check    ".deb havuzda" test -f "$site/pool/main/a/aify/$(basename "$deb2")"
		# Release icindeki karma degerleri gercekten dosyalarla eslesiyor mu?
		( cd "$site/dists/aify" && awk '/^SHA256:/{f=1;next} /^[A-Za-z]/{f=0} f{print $1"  "$3}' Release | sha256sum -c --quiet ) \
			&& ok "Release karma degerleri dogru" || bad "Release karma degerleri tutmuyor"
	else
		bad "apt deposu uretilemedi"
	fi
else
	printf '  atlandi (dpkg-scanpackages yok)\n'
fi

head_ "12. Etkilesimli arayuz"
contains "aify banner logoyu yaziyor" "aify" "$AIFY" banner
contains "TTY yokken bare aify yardim veriyor" "KOMUTLAR" "$AIFY"
if command -v python3 >/dev/null 2>&1; then
	uihome="$(mktemp -d)"
	drive() { python3 "$ROOT/tests/ui-drive.py" "$AIFY" "$uihome" "$@" 2>/dev/null; }
	out="$(drive 'q')"
	printf '%s' "$out" | grep -q 'Araclar'   && ok "arayuz arac listesini ciziyor"   || bad "arac listesi cizilmedi"
	printf '%s' "$out" | grep -q 'codex'     && ok "listede araclar goruluyor"       || bad "araclar goruntulenmedi"
	printf '%s' "$out" | grep -q 'gorusuruz' && ok "q ile temiz cikis"               || bad "q ile cikilamadi"
	drive '\x1b[B' '\x1b[B' 'SLEEP0.5' 'q' | grep -q '❯' \
		&& ok "yon tuslariyla secim imleci hareket ediyor" || bad "imlec hareket etmedi"
	drive '\r' 'SLEEP1' 'q' 'q' | grep -q 'Kur / yeniden kur' \
		&& ok "enter islem menusunu aciyor" || bad "islem menusu acilmadi"
	drive 'b' 'SLEEP1' 'q' 'q' | grep -q 'glibc arka ucunu kur' \
		&& ok "b arka uc ekranini aciyor" || bad "arka uc ekrani acilmadi"

	# Arayuzden gercek kurulum (yerel arsivle): crush listede 7. sirada
	mkdir -p "$uihome/fake"
	printf '#!/bin/sh\necho "crush 9.9.9"\n' > "$uihome/fake/crush"
	chmod +x "$uihome/fake/crush"
	tar -czf "$uihome/crush.tar.gz" -C "$uihome/fake" crush
	AIFY_TEST_ASSET_URL="file://$uihome/crush.tar.gz" \
		drive '\x1b[B' '\x1b[B' '\x1b[B' '\x1b[B' '\x1b[B' '\x1b[B' 'i' 'SLEEP3' '\r' 'SLEEP1' 'q' >/dev/null
	[ -f "$uihome/state/crush" ] && ok "arayuzden kurulum calisiyor" || bad "arayuzden kurulum basarisiz"
	rm -rf "$uihome"
else
	printf '  atlandi (python3 yok)\n'
fi

head_ "13. make install / uninstall"
stage="$AIFY_HOME/stage"
check "make install" make -s -C "$ROOT" install DESTDIR="$stage" PREFIX=/usr
check "kurulan aify calisiyor" test -x "$stage/usr/bin/aify"
if [ -x "$stage/usr/bin/aify" ]; then
	contains "kurulu aify list calisiyor" "claude" "$stage/usr/bin/aify" list
fi
check "make uninstall" make -s -C "$ROOT" uninstall DESTDIR="$stage" PREFIX=/usr

printf '\n\033[1mSonuc:\033[0m %s basarili, %s basarisiz\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
