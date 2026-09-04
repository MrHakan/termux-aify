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
dogrulamasi yaparak yerli ikiliyi indirir. Ikili glibc'e baglidir; Termux'ta
glibc-runner veya proot ile calisir.
agy arka planda kendini gunceller: guncelleme sonrasi yeni ikili yamasiz
kalirsa 'aify install agy' ile arka ucu tazeleyin."
