#!/usr/bin/env bash
# aify icin statik bir apt deposu uretir (GitHub Pages'te yayinlanmak uzere).
#
#   packaging/build-apt-repo.sh [--out site] [--deb dist/aify_x.y.z_all.deb]
#
# Termux tarafinda kullanimi:
#   deb [trusted=yes] https://<kullanici>.github.io/<depo> aify main
#
# Not: Release dosyasi imzalanmaz (sources.list satirinda [trusted=yes]), ancak
# apt'nin indeks dosyalarini bulabilmesi icin MD5Sum/SHA256 boleumleri elle
# uretilir - bu sayede apt-utils/apt-ftparchive bagimliligi yoktur.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/site"
DEB=""
SUITE="aify"
COMPONENT="main"
ARCHS="all aarch64 arm i686 x86_64"
BASE_URL="${AIFY_PAGES_URL:-https://mrhakan.github.io/termux-aify}"

while [ $# -gt 0 ]; do
	case "$1" in
		--out)  OUT="$2"; shift 2 ;;
		--deb)  DEB="$2"; shift 2 ;;
		--url)  BASE_URL="$2"; shift 2 ;;
		-h|--help) sed -n '2,8p' "$0"; exit 0 ;;
		*) echo "bilinmeyen secenek: $1" >&2; exit 1 ;;
	esac
done

if [ -z "$DEB" ]; then
	DEB="$(find "$ROOT/dist" -maxdepth 1 -name 'aify_*_all.deb' 2>/dev/null | sort | tail -n1)"
fi
if [ -z "$DEB" ] || [ ! -f "$DEB" ]; then
	echo "hata: .deb bulunamadi (once: make deb)" >&2
	exit 1
fi
command -v dpkg-scanpackages >/dev/null 2>&1 || { echo "hata: dpkg-scanpackages gerekli (dpkg-dev)" >&2; exit 1; }

DEB="$(cd "$(dirname "$DEB")" && pwd)/$(basename "$DEB")"
rm -rf "$OUT"
mkdir -p "$OUT/pool/$COMPONENT/a/aify"
# Betik icinde 'cd' yapiliyor; goreli yol verilse de mutlak yola cevir.
OUT="$(cd "$OUT" && pwd)"
echo "==> apt deposu: $OUT  (paket: $(basename "$DEB"))"
cp "$DEB" "$OUT/pool/$COMPONENT/a/aify/"

cd "$OUT"
# Termux'un apt'si mimariye ozel indeks arar; 'all' paketini hepsine koyuyoruz.
for arch in $ARCHS; do
	mkdir -p "dists/$SUITE/$COMPONENT/binary-$arch"
	dpkg-scanpackages --multiversion pool /dev/null 2>/dev/null \
		> "dists/$SUITE/$COMPONENT/binary-$arch/Packages"
	gzip -9nc "dists/$SUITE/$COMPONENT/binary-$arch/Packages" \
		> "dists/$SUITE/$COMPONENT/binary-$arch/Packages.gz"
done

{
	printf 'Origin: termux-aify\n'
	printf 'Label: aify\n'
	printf 'Suite: %s\n' "$SUITE"
	printf 'Codename: %s\n' "$SUITE"
	printf 'Architectures: %s\n' "$ARCHS"
	printf 'Components: %s\n' "$COMPONENT"
	printf 'Description: aify - Termux yapay zeka CLI yoneticisi\n'
	printf 'Date: %s\n' "$(date -Ru)"
} > "dists/$SUITE/Release"

# apt, indeks dosyalarini Release icindeki karma listesinden bulur.
(
	cd "dists/$SUITE"
	tmp="$(mktemp)"
	{
		printf 'MD5Sum:\n'
		find . -type f ! -name Release | sort | while read -r f; do
			f="${f#./}"
			printf ' %s %16s %s\n' "$(md5sum "$f" | cut -d' ' -f1)" "$(wc -c < "$f")" "$f"
		done
		printf 'SHA256:\n'
		find . -type f ! -name Release | sort | while read -r f; do
			f="${f#./}"
			printf ' %s %16s %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(wc -c < "$f")" "$f"
		done
	} > "$tmp"
	cat "$tmp" >> Release
	rm -f "$tmp"
)

cat > index.html <<HTML
<!doctype html>
<meta charset="utf-8">
<title>aify apt deposu</title>
<body style="font-family:system-ui,sans-serif;max-width:44rem;margin:3rem auto;padding:0 1rem;line-height:1.6">
<h1>aify &mdash; Termux apt deposu</h1>
<p>Termux'ta kurulum:</p>
<pre style="background:#f4f4f5;padding:1rem;border-radius:.5rem;overflow-x:auto">mkdir -p \$PREFIX/etc/apt/sources.list.d
echo "deb [trusted=yes] $BASE_URL $SUITE $COMPONENT" \\
  &gt; \$PREFIX/etc/apt/sources.list.d/aify.list
pkg update &amp;&amp; pkg install aify</pre>
<p style="color:#666">Termux does not ship <code>sources.list.d/</code>, so the <code>mkdir -p</code> is required.</p>
<p>Kaynak kod: <a href="https://github.com/MrHakan/termux-aify">github.com/MrHakan/termux-aify</a></p>
</body>
HTML
touch .nojekyll

echo "==> hazir: $OUT"
find "$OUT" -type f | sort | sed 's|^|    |'
