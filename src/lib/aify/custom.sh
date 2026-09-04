#!/usr/bin/env bash
# aify - kullanicinin kendi araclarini kayda ekleme
# shellcheck shell=bash

_aify_slug() { printf '%s' "$1" | sed 's|^@||; s|.*/||; s/[^A-Za-z0-9._-]/-/g' | tr '[:upper:]' '[:lower:]'; }

_aify_write_tool_file() { # id  <<< icerik
	local id="$1" file
	mkdir -p "$AIFY_HOME/registry.d"
	file="$AIFY_HOME/registry.d/$id.tool"
	cat > "$file"
	aify_ok "kayit yazildi: $file"
	printf '%s\n' "$file"
}

aify_cmd_add_npm() {
	local pkg='' id='' bin='' name='' backends='native glibc proot' summary=''
	while [ $# -gt 0 ]; do
		case "$1" in
			--id)       id="$2"; shift 2 ;;
			--bin)      bin="$2"; shift 2 ;;
			--name)     name="$2"; shift 2 ;;
			--summary)  summary="$2"; shift 2 ;;
			--backends) backends="$2"; shift 2 ;;
			-*) aify_die "bilinmeyen secenek: $1" ;;
			*) pkg="$1"; shift ;;
		esac
	done
	[ -n "$pkg" ] || aify_die "kullanim: aify add-npm <npm-paketi> [--id x] [--bin x] [--backends 'native proot']"
	id="${id:-$(_aify_slug "$pkg")}"
	bin="${bin:-$id}"
	name="${name:-$pkg}"
	summary="${summary:-kullanici tanimli npm CLI ($pkg)}"

	_aify_write_tool_file "$id" >/dev/null <<TOOL
# aify add-npm ile uretildi
TOOL_ID=$id
TOOL_NAME="$name"
TOOL_SUMMARY="$summary"
TOOL_KIND=npm
TOOL_PACKAGE="$pkg"
TOOL_BIN=$bin
TOOL_RUNTIME=node
TOOL_BACKENDS="$backends"
TOOL_DEPS="nodejs-lts"
TOOL_NOTES="Kullanici tanimli kayit. Duzenlemek icin: \$AIFY_HOME/registry.d/$id.tool"
TOOL
	aify_ok "$id eklendi -> aify install $id"
}

aify_cmd_add_pkg() {
	local pkg='' id='' bin='' name=''
	while [ $# -gt 0 ]; do
		case "$1" in
			--id)   id="$2"; shift 2 ;;
			--bin)  bin="$2"; shift 2 ;;
			--name) name="$2"; shift 2 ;;
			-*) aify_die "bilinmeyen secenek: $1" ;;
			*) pkg="$1"; shift ;;
		esac
	done
	[ -n "$pkg" ] || aify_die "kullanim: aify add-pkg <termux-paketi> [--bin x]"
	id="${id:-$(_aify_slug "$pkg")}"
	bin="${bin:-$id}"
	name="${name:-$pkg}"

	_aify_write_tool_file "$id" >/dev/null <<TOOL
# aify add-pkg ile uretildi
TOOL_ID=$id
TOOL_NAME="$name"
TOOL_SUMMARY="kullanici tanimli Termux paketi ($pkg)"
TOOL_KIND=pkg
TOOL_PKG="$pkg"
TOOL_BIN=$bin
TOOL_BACKENDS="native"
TOOL
	aify_ok "$id eklendi -> aify install $id"
}

aify_cmd_add_gh() {
	local repo='' id='' bin='' name='' match=''
	while [ $# -gt 0 ]; do
		case "$1" in
			--id)    id="$2"; shift 2 ;;
			--bin)   bin="$2"; shift 2 ;;
			--name)  name="$2"; shift 2 ;;
			--match) match="$2"; shift 2 ;;
			-*) aify_die "bilinmeyen secenek: $1" ;;
			*) repo="$1"; shift ;;
		esac
	done
	case "$repo" in */*) ;; *) aify_die "kullanim: aify add-gh <kullanici/depo> [--bin x] [--match '(Linux|linux)']" ;; esac
	id="${id:-$(_aify_slug "${repo##*/}")}"
	bin="${bin:-$id}"
	name="${name:-$repo}"
	match="${match:-(Linux|linux)}"

	_aify_write_tool_file "$id" >/dev/null <<TOOL
# aify add-gh ile uretildi
TOOL_ID=$id
TOOL_NAME="$name"
TOOL_SUMMARY="kullanici tanimli GitHub surumu ($repo)"
TOOL_KIND=github
TOOL_GH_REPO="$repo"
TOOL_GH_MATCH="$match"
TOOL_BIN=$bin
TOOL_BACKENDS="native"
TOOL_DEPS="curl tar"
TOOL
	aify_ok "$id eklendi -> aify install $id"
}
