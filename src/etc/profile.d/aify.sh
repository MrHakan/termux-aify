# aify - kullanici araclarinin shim dizinini PATH'e ekler
# Termux her yeni oturumda $PREFIX/etc/profile.d/*.sh dosyalarini yukler.
case ":${PATH}:" in
	*":${AIFY_HOME:-$HOME/.aify}/bin:"*) ;;
	*) PATH="${AIFY_HOME:-$HOME/.aify}/bin:$PATH"; export PATH ;;
esac
