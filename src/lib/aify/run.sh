#!/usr/bin/env bash
# aify - kurulu araci dogru arka uc ile calistirir
# shellcheck shell=bash

_aify_export_tool_env() {
	local kv
	for kv in "${TOOL_ENV[@]:-}"; do
		[ -n "$kv" ] || continue
		# Kullanici zaten tanimladiysa ezme
		local k="${kv%%=*}"
		[ -n "${!k:-}" ] && continue
		export "${kv?}"
	done
	return 0
}

aify_cmd_run() {
	local id="${1:-}"
	[ -n "$id" ] || aify_die "kullanim: aify run <id> [arg...]"
	shift
	aify_tool_load "$id" || aify_die "bilinmeyen arac: $id"

	if ! aify_is_installed "$id"; then
		aify_warn "$TOOL_NAME kurulu degil"
		if aify_confirm "Simdi kurulsun mu?"; then
			_aify_install_one "$id" ''
		else
			exit 1
		fi
	fi

	local backend path tdir
	backend="$(aify_state_get "$id" backend || echo native)"
	path="$(aify_state_get "$id" path || echo "$TOOL_BIN")"
	tdir="$AIFY_TOOLS_DIR/$id"

	_aify_export_tool_env
	export PATH="$tdir/bin:$PATH"
	[ -d "$AIFY_BIN_DIR" ] && export PATH="$AIFY_BIN_DIR:$PATH"

	case "$backend" in
		native)
			[ -x "$path" ] || aify_die "$path calistirilabilir degil - 'aify install $id' ile yenileyin"
			exec "$path" "$@"
			;;
		glibc)
			aify_backend_available glibc || aify_die "glibc arka ucu yok: aify backend setup glibc"
			[ -f "$path" ] || aify_die "$path bulunamadi - 'aify install $id' ile yenileyin"
			local runner=grun
			aify_have grun || runner=glibc-runner
			exec "$runner" "$path" "$@"
			;;
		proot)
			aify_backend_available proot || aify_die "proot arka ucu yok: aify backend setup proot"
			local cmd; cmd="$(printf '%q' "$path")"
			local a
			for a in "$@"; do cmd="$cmd $(printf '%q' "$a")"; done
			aify_proot_exec "exec $cmd"
			;;
		*) aify_die "bilinmeyen arka uc: $backend" ;;
	esac
}

# Kurulu araclarin ortam degiskenlerini yazdirir (kabuk icin: eval "$(aify env)")
aify_cmd_env() {
	# shellcheck disable=SC2016  # $PATH cikti icinde birebir kalmali
	printf 'export PATH="%s:$PATH"\n' "$AIFY_BIN_DIR"
	printf 'export AIFY_HOME="%s"\n' "$AIFY_HOME"
}
