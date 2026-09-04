# aify - Termux paketi kurulum/derleme
PREFIX     ?= /data/data/com.termux/files/usr
DESTDIR    ?=
VERSION    := $(shell sed -n 's/^AIFY_VERSION="\(.*\)"/\1/p' src/lib/aify/core.sh | head -n1)

BINDIR     := $(DESTDIR)$(PREFIX)/bin
LIBDIR     := $(DESTDIR)$(PREFIX)/lib/aify
SHAREDIR   := $(DESTDIR)$(PREFIX)/share/aify
DOCDIR     := $(DESTDIR)$(PREFIX)/share/doc/aify
PROFILEDIR := $(DESTDIR)$(PREFIX)/etc/profile.d
COMPDIR    := $(DESTDIR)$(PREFIX)/share/bash-completion/completions

.PHONY: all install uninstall deb apt-repo check lint version clean

all:
	@echo "aify $(VERSION)"
	@echo "hedefler: install, uninstall, deb, apt-repo, check, lint"

version:
	@echo $(VERSION)

install:
	install -d $(BINDIR) $(LIBDIR) $(SHAREDIR)/registry.d $(DOCDIR) $(PROFILEDIR) $(COMPDIR)
	install -m 0755 src/bin/aify $(BINDIR)/aify
	install -m 0644 src/lib/aify/*.sh $(LIBDIR)/
	install -m 0644 src/share/aify/registry.d/*.tool $(SHAREDIR)/registry.d/
	install -m 0644 src/etc/profile.d/aify.sh $(PROFILEDIR)/aify.sh
	install -m 0644 src/share/bash-completion/completions/aify $(COMPDIR)/aify
	install -m 0644 README.md $(DOCDIR)/README.md
	install -m 0644 LICENSE $(DOCDIR)/LICENSE

uninstall:
	rm -f $(BINDIR)/aify $(PROFILEDIR)/aify.sh $(COMPDIR)/aify
	rm -rf $(LIBDIR) $(SHAREDIR) $(DOCDIR)

deb:
	packaging/build-deb.sh

apt-repo: deb
	packaging/build-apt-repo.sh

check:
	tests/run-tests.sh

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck yok, atlaniyor"; exit 0; }
	shellcheck -s bash -e SC1090,SC1091,SC1094 src/bin/aify src/lib/aify/*.sh packaging/*.sh install.sh tests/run-tests.sh

clean:
	rm -rf build dist site
