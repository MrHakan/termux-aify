TOOL_ID=opencode
TOOL_NAME="opencode"
TOOL_SUMMARY="Terminal icin acik kaynak AI kodlama ajani (TUI)"
TOOL_HOMEPAGE="https://github.com/sst/opencode"
TOOL_KIND=npm
TOOL_PACKAGE="opencode-ai"
TOOL_BIN=opencode
TOOL_RUNTIME=native
TOOL_BACKENDS="glibc proot"
TOOL_DEPS="nodejs-lts"
TOOL_NPM_OS=linux
TOOL_TAGS="agent tui"
TOOL_AUTH="opencode auth login"
TOOL_NATIVE_BINARY="lib/node_modules/opencode-linux-arm64/bin/opencode lib/node_modules/opencode-linux-x64/bin/opencode"
TOOL_NOTES="Bun ile derlenmis yerli ikili dagitir; glibc'e baglidir, bu yuzden
glibc-runner ya da proot gerekir. musl surumu de dinamik oldugu icin
Termux'ta dogrudan calismaz."
