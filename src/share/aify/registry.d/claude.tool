TOOL_ID=claude
TOOL_NAME="Claude Code"
TOOL_SUMMARY="Anthropic'in resmi terminal kodlama ajani"
TOOL_HOMEPAGE="https://github.com/anthropics/claude-code"
TOOL_KIND=npm
TOOL_PACKAGE="@anthropic-ai/claude-code"
TOOL_BIN=claude
TOOL_RUNTIME=native
TOOL_BACKENDS="glibc proot"
TOOL_DEPS="nodejs-lts ripgrep"
TOOL_NPM_OS=linux
TOOL_NPM_LIBC=glibc
TOOL_TAGS="anthropic agent"
TOOL_AUTH="ilk calistirmada tarayici ile giris; ya da ANTHROPIC_API_KEY"
# npm sarmalayicisi Termux'ta (process.platform=android) yerli ikiliyi
# yerlestiremedigi icin platform paketindeki ikiliyi dogrudan kullaniyoruz.
TOOL_NATIVE_BINARY="lib/node_modules/@anthropic-ai/claude-code-linux-arm64/claude lib/node_modules/@anthropic-ai/claude-code-linux-x64/claude"
TOOL_ENV=(
	"DISABLE_AUTOUPDATER=1"
	"USE_BUILTIN_RIPGREP=0"
)
TOOL_NOTES="Claude Code 2.x artik saf JS degil, platforma ozel yerli ikili dagitiyor
ve Android (bionic) icin bir yapisi yok. Bu yuzden glibc ikilisi kurulup
glibc-runner ile calistiriliyor; alternatifi proot arka ucudur.
Otomatik guncelleme kapatildi (DISABLE_AUTOUPDATER=1): yamali ikiliyi
bozmamasi icin guncellemeyi 'aify update claude' ile yapin.
Arama icin Termux'un ripgrep'i kullanilir (USE_BUILTIN_RIPGREP=0)."
