TOOL_ID=codex
TOOL_NAME="OpenAI Codex CLI"
TOOL_SUMMARY="OpenAI'nin terminal kodlama ajani (Rust)"
TOOL_HOMEPAGE="https://github.com/openai/codex"
TOOL_KIND=npm
TOOL_PACKAGE="@openai/codex"
TOOL_BIN=codex
TOOL_RUNTIME=node
TOOL_BACKENDS="native proot"
TOOL_DEPS="nodejs-lts ripgrep"
TOOL_NPM_OS=linux
TOOL_TAGS="openai agent"
TOOL_AUTH="codex login  (ChatGPT hesabi) veya OPENAI_API_KEY"
TOOL_NOTES="Codex, aarch64-unknown-linux-musl hedefini STATIK derliyor ve npm
sarmalayicisi 'android' platformunu taniyor; bu yuzden Termux'ta proot'suz
calisir. Pakette gelen ripgrep glibc'e bagli oldugu icin kurulumdan sonra
Termux'un rg'si ile degistirilir.
Android'de landlock/seccomp sandbox yoktur; codex sandbox hatasi verirse
~/.codex/config.toml icine  sandbox_mode = \"danger-full-access\"  ekleyin
(guvenlik kararini bilerek verin) ya da --sandbox secenegini kullanin."

tool_post_install() {
	local tdir="$1" rgpath vendor
	command -v rg >/dev/null 2>&1 || return 0
	while read -r rgpath; do
		[ -n "$rgpath" ] && [ -f "$rgpath" ] || continue
		[ "$(aify_binary_class "$rgpath")" = glibc ] || continue
		mv -f "$rgpath" "$rgpath.orig" 2>/dev/null || true
		ln -sf "$(command -v rg)" "$rgpath"
		aify_step "vendor ripgrep -> Termux rg"
	done < <(find "$tdir" -type f -path '*/codex-path/rg' 2>/dev/null)
	return 0
}
