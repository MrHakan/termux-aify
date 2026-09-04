TOOL_ID=aider
TOOL_NAME="Aider"
TOOL_SUMMARY="Git farkindali Python kodlama ajani"
TOOL_HOMEPAGE="https://aider.chat"
TOOL_KIND=uv
TOOL_PACKAGE="aider-chat"
TOOL_BIN=aider
TOOL_RUNTIME=python
TOOL_BACKENDS="proot native"
TOOL_DEPS="python uv git"
TOOL_TAGS="python agent"
TOOL_AUTH="OPENAI_API_KEY / ANTHROPIC_API_KEY gibi saglayici anahtarlari"
TOOL_NOTES="Android icin hazir wheel bulunmayan bagimliliklar (tiktoken vb.)
kaynaktan derlenmek zorunda kaldigi icin yerli kurulum sik sik rust/clang
ister. Bu yuzden varsayilan arka uc proot'tur.
Yerli denemek icin: pkg install rust clang && aify install aider --backend native"
