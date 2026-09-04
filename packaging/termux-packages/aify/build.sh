# termux-packages agacinda kullanilacak tarif.
# Kullanim: termux-packages/packages/aify/build.sh olarak kopyalayin, sonra:
#   ./build-package.sh -a all aify
TERMUX_PKG_HOMEPAGE=https://github.com/MrHakan/termux-aify
TERMUX_PKG_DESCRIPTION="Termux icin yapay zeka CLI yoneticisi (Claude Code, Codex, Copilot, Antigravity...)"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="@MrHakan"
TERMUX_PKG_VERSION="0.3.0"
TERMUX_PKG_SRCURL=https://github.com/MrHakan/termux-aify/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz
# Etiket atildiktan sonra guncelleyin:
#   ./scripts/bin/update-checksum aify   (ya da elle: sha256sum <tarball>)
TERMUX_PKG_SHA256=0000000000000000000000000000000000000000000000000000000000000000
TERMUX_PKG_PLATFORM_INDEPENDENT=true
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_DEPENDS="bash, coreutils, curl, tar, grep, sed, findutils"
TERMUX_PKG_RECOMMENDS="nodejs-lts, git, ripgrep"
TERMUX_PKG_SUGGESTS="proot-distro, gh, uv, unzip"

termux_step_make() {
	return 0
}

termux_step_make_install() {
	make install PREFIX="${TERMUX_PREFIX}" DESTDIR=""
}
