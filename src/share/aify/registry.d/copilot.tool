TOOL_ID=copilot
TOOL_NAME="GitHub Copilot CLI"
TOOL_SUMMARY="GitHub Copilot'un terminal ajani"
TOOL_HOMEPAGE="https://github.com/github/copilot-cli"
TOOL_KIND=npm
TOOL_PACKAGE="@github/copilot"
TOOL_BIN=copilot
TOOL_RUNTIME=native
TOOL_BACKENDS="glibc proot"
TOOL_DEPS="nodejs-lts"
TOOL_NPM_OS=linux
TOOL_NPM_LIBC=glibc
TOOL_TAGS="github agent"
TOOL_AUTH="/login komutu veya GH_TOKEN / GITHUB_TOKEN"
TOOL_NATIVE_BINARY="lib/node_modules/@github/copilot-linux-arm64/copilot lib/node_modules/@github/copilot-linux-x64/copilot"
TOOL_NOTES="Platforma ozel yerli ikili; Android yapisi yok, glibc surumu
glibc-runner ile calistirilir. npm platform paketini @github/copilot'un
kendi node_modules'una ic ice kuruyor; aify ikiliyi orada da arar (npm
sarmalayicisi calisir gorunse de yerli ikili tercih edilir)."
