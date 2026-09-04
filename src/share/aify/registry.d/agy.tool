TOOL_ID=agy
TOOL_NAME="Antigravity CLI"
TOOL_SUMMARY="Google Antigravity ajan harness'inin terminal surumu (agy)"
TOOL_HOMEPAGE="https://antigravity.google/docs/cli/install/"
TOOL_KIND=installer
TOOL_INSTALLER_URL="https://antigravity.google/cli/install.sh"
TOOL_INSTALLER_ARGS="--dir @BINDIR@"
TOOL_BIN=agy
TOOL_RUNTIME=native
TOOL_BACKENDS="glibc proot"
TOOL_DEPS="curl coreutils tar"
TOOL_TAGS="google agent"
TOOL_AUTH="agy ilk calistirmada Google girisi ister"
TOOL_NOTES="Resmi kurulum betigi (antigravity.google/cli/install.sh) sha512
dogrulamasi yaparak yerli ikiliyi indirir. Ikili Go (cgo) ile derlenmis ve
glibc'e baglidir; Termux'ta glibc-runner veya proot ile calisir.
Ag icin iki sey gerekir, ikisini de aify saglar:
  - DNS: Termux glibc'i /etc yerine \$PREFIX/glibc/etc/resolv.conf okur, ama
    glibc paketi bu dosyayi gondermez. Yoksa 'token exchange failed' gibi
    hatalar alirsiniz; 'aify backend setup glibc' dosyayi olusturur.
  - TLS: Go'nun x509'u Android'de olmayan /etc/ssl'i arar; aify calistirirken
    SSL_CERT_FILE'i Termux'un ca-certificates demetine yonlendirir.
agy arka planda kendini gunceller: guncelleme sonrasi yeni ikili yamasiz
kalirsa 'aify install agy' ile arka ucu tazeleyin."
