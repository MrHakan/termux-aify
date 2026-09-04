TOOL_ID=copilot
TOOL_NAME="GitHub Copilot CLI"
TOOL_SUMMARY="GitHub Copilot'un terminal ajani"
TOOL_HOMEPAGE="https://github.com/github/copilot-cli"
TOOL_KIND=npm
TOOL_PACKAGE="@github/copilot"
TOOL_BIN=copilot
TOOL_RUNTIME=native
TOOL_BACKENDS="proot glibc"
TOOL_DEPS="nodejs-lts"
TOOL_NPM_OS=linux
TOOL_NPM_LIBC=glibc
TOOL_TAGS="github agent"
TOOL_AUTH="/login komutu veya GH_TOKEN / GITHUB_TOKEN"
TOOL_NATIVE_BINARY="lib/node_modules/@github/copilot-linux-arm64/copilot lib/node_modules/@github/copilot-linux-x64/copilot"
TOOL_NOTES="158MB'lik non-PIE (ET_EXEC) bir Node SEA dagitiyor. glibc-runner
ikilileri 'ld.so BINARY' ile baslatir; dinamik yukleyici non-PIE bir dosyayi
YUKLEYEMEZ ve segfault verir. Ikiliyi patchelf ile yamalamak yerine (baskasinin
100+MB'lik ikilisini yerinde degistirmek istemiyoruz) proot kabinda gercek bir
/lib/ld-linux ile calistiriyoruz; bu yuzden tercih sirasi proot.
npm, platform paketini @github/copilot'un kendi node_modules'una ic ice
kuruyor; aify ikiliyi orada da arar."
