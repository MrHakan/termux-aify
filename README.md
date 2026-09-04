# aify — an AI CLI manager for Termux

`aify` is a Termux package that installs, updates, and runs **Claude Code, OpenAI Codex,
GitHub Copilot CLI, Antigravity CLI (`agy`), opencode**, and similar terminal AI tools on your
phone's Termux — all with a single command, and each one **on the right backend**.

Projects like opencode or opencodex ship *a single agent*; `aify` is the **manager** that wraps
them all: an isolated directory per tool, a thin shim on your PATH, and — most importantly — an
automatic escape hatch for binaries that don't run on Termux (Android/bionic) at all.

```
pkg install aify          # or: curl -fsSL .../install.sh | bash
aify setup
aify install codex copilot qwen
aify install claude       # picks the glibc backend for you
aify codex "run the tests in this repo"
```

---

## Why this exists (Termux's real problem)

Android uses **bionic** libc; Linux distros' `glibc`/`musl` binaries don't run on Termux
directly. Since 2025, most of these tools have stopped being pure JavaScript and now ship
**platform-specific native binaries** — none of which have an Android build. On top of that,
Termux's Node reports `process.platform` as `android`, so `npm` **silently skips** platform
packages tagged `os: ["linux"]` — which is why `npm i -g @anthropic-ai/claude-code` leaves you
with a shell that doesn't work.

`aify` solves all three problems at once:

1. tells npm the target explicitly (`--os=linux --cpu=arm64 --libc=glibc`),
2. reads the installed binary's ELF class after install (static / glibc / musl / script),
3. picks the backend based on that class and writes the shim accordingly.

| Class | Example | Backend |
|---|---|---|
| interpreted script (node) | Qwen Code, OpenCodex, Claude Code Router | `native` |
| static ELF | Codex, Crush | `native` |
| glibc-linked ELF | Claude Code, `agy`, opencode, Copilot CLI | `glibc` (glibc-runner) or `proot` |
| musl-linked ELF | some bun/musl builds | `proot` |

### Backends

| Backend | How | Cost | Setup |
|---|---|---|---|
| `native` | directly inside Termux | none | ready |
| `glibc` | dynamic loader via [glibc-runner](https://github.com/termux-pacman/glibc-packages) (`grun`) | ~100 MB | `aify backend setup glibc` |
| `proot` | `proot-distro` Debian container | ~500 MB, a bit slower | `aify backend setup proot` |

The `glibc` backend also has to paper over Android's missing `/etc`: Termux's glibc is patched
to read `$PREFIX/glibc/etc/resolv.conf` instead of `/etc/resolv.conf`, but the glibc package
ships no such file — so `getaddrinfo` falls back to `127.0.0.1` and every DNS lookup fails.
`aify backend setup glibc` writes `resolv.conf`, `nsswitch.conf` and `hosts` there, and
`aify run` points `SSL_CERT_FILE` at Termux's CA bundle for Go binaries (whose `crypto/x509`
looks for `/etc/ssl`, which doesn't exist on Android either).

Under the `proot` backend, `$HOME` and your current directory are bind-mounted at the **same
paths**; so settings like `~/.claude`, `~/.codex` end up in the same place as a native install,
and your projects are visible at the same paths too.

---

## Supported tools

Run `aify list` for the up-to-date list.

| id | Tool | Source | On Termux | Note |
|---|---|---|---|---|
| `claude` | Claude Code | npm `@anthropic-ai/claude-code` | glibc / proot | 2.x ships a native binary, no Android build |
| `codex` | OpenAI Codex CLI | npm `@openai/codex` | **native** | `aarch64-*-musl` target is static; wrapper recognizes `android` |
| `qwen` | Qwen Code | npm `@qwen-code/qwen-code` | **native** | pure JS |
| `agy` | Antigravity CLI | official install script | glibc / proot | sha512-verified native binary (glibc) |
| `opencode` | opencode | npm `opencode-ai` | glibc / proot | binary compiled with bun |
| `copilot` | GitHub Copilot CLI | npm `@github/copilot` | glibc / proot | |
| `opencodex` | OpenCodex | npm `@bitkyc08/opencodex` | **native** | provider proxy for Codex/Claude Code |
| `ccr` | Claude Code Router | npm `@musistudio/claude-code-router` | **native** | routes the model |
| `crush` | Crush | GitHub releases | **native** | Go binary, statically linked |
| `aider` | Aider | `uv` / `pipx` | proot (native experimental) | no prebuilt wheels for Android |

For details, run `aify info <id>` — the login method, the reasoning behind the backend choice,
and Termux-specific notes are all written there per tool.

---

## Installation

### 1) From the apt repo (recommended)

```bash
mkdir -p $PREFIX/etc/apt/sources.list.d
echo "deb [trusted=yes] https://mrhakan.github.io/termux-aify aify main" \
  > $PREFIX/etc/apt/sources.list.d/aify.list
pkg update && pkg install aify
```

> `mkdir -p` is not optional: Termux does not ship `sources.list.d/`, so without it the
> redirect fails with *No such file or directory* and `pkg install aify` then reports
> *Unable to locate package aify* — the repo was never added.

> The repo is published to GitHub Pages when a `v*` tag is pushed (or when the `release`
> workflow is run manually — in that case the workflow creates the tag itself).
> (**Settings → Pages → Source: GitHub Actions** must be selected in the repo settings;
> otherwise the `pages` job fails, though the `.deb` still gets attached to the release.)

> If Pages hasn't been enabled yet, the repo returns 404 — use the `.deb` path below instead.

### 2) With a prebuilt `.deb`

```bash
curl -fsSL https://raw.githubusercontent.com/MrHakan/termux-aify/main/install.sh | bash
```

The script first tries the latest release's `.deb`, and falls back to building from source if
that's not available.

### 3) From source

```bash
git clone https://github.com/MrHakan/termux-aify
cd termux-aify
make install            # PREFIX is auto-detected on Termux
```

### 4) Building inside the termux-packages tree

Copy `packaging/termux-packages/aify/` to `termux-packages/packages/aify/`, then:

```bash
./build-package.sh -a all aify
```

---

## Interface

Just running `aify` in the terminal opens an interactive UI with an ASCII logo — install, run,
pick a backend, run diagnostics; all from here:

```
  ▄▀█ █ █▀▀ █▄█   aify v0.2.0
  █▀█ █ █▀░  █    An AI CLI manager for Termux

  Termux · aarch64 · node 24.18.0 · backend: native,glibc

╭─ Tools ───────────────────────────────────────────────╮
│ ❯ claude      Claude Code             ● glibc         │
│   codex       OpenAI Codex CLI        ● native        │
│   copilot     GitHub Copilot CLI      ○ glibc         │
│   agy         Antigravity CLI         ○ glibc         │
╰───────────────────────────────────────────────────────╯

  i install   r run   enter info   d remove   u update
  b backends   t doctor   / command   ? help   q quit
```

| Key | Action |
|---|---|
| `↑` `↓` (or `j` `k`) | move between tools |
| `enter` | action menu for the selected tool (info / install / run / update / remove / backend) |
| `i` `r` `d` `u` | install, run, remove, update directly |
| `b` | backends screen (set up glibc / proot) |
| `t` | `aify doctor` |
| `/` | free-form command line (`install codex`, `config list`, …) |
| `?` | help · `q` quit |

The UI opens on the alternate screen and leaves your terminal as it was on exit. When called
from a script or through a pipe (no TTY), it automatically falls back to the old behavior — the
help text; force it with `aify ui`, or print just the logo with `aify banner`.
On a non-Unicode terminal, `AIFY_ASCII=1` switches to ASCII mode.

---

## Usage

```
aify                       # interactive UI (screen above)
aify setup                 # directories, base packages, PATH
aify list                  # tools and install status
aify info claude           # details + Termux-specific notes
aify install codex copilot  # install
aify install claude --backend proot
aify update                # update everything installed
aify remove opencode
aify run codex --help      # or the shortcut:  aify codex --help
aify backend status
aify backend setup glibc
aify doctor                # environment diagnostics
aify config set tool.claude.backend proot
```

Every installed tool gets a thin shim under `~/.aify/bin/<command>`; this directory is added to
PATH automatically in new sessions via `$PREFIX/etc/profile.d/aify.sh`. So after install you can
type `claude`, `codex`, `copilot` directly — `aify run` isn't required.

### Directory layout

```
~/.aify/
├── bin/            # shims that land on PATH
├── tools/<id>/     # per-tool isolated install (npm --prefix)
├── state/<id>      # backend, binary path, version, ELF class
├── registry.d/     # tool definitions you've added
├── cache/  log/
└── config          # key=value
```

Removing the package leaves `~/.aify` untouched: `pkg uninstall aify && rm -rf ~/.aify`.

---

## Adding your own tool

Three built-in ways:

```bash
aify add-npm @my/agent --bin agent           # any npm CLI
aify add-gh  charmbracelet/crush --bin crush # GitHub release binary
aify add-pkg glab                            # a Termux package
```

…or write `~/.aify/registry.d/<id>.tool` by hand (same format as the built-in definitions;
using the same id overrides the built-in one):

```sh
TOOL_ID=agent
TOOL_NAME="My Agent"
TOOL_SUMMARY="short description"
TOOL_KIND=npm                 # npm | pkg | github | installer | uv
TOOL_PACKAGE="@my/agent"
TOOL_BIN=agent
TOOL_BACKENDS="native glibc proot"   # preference order
TOOL_DEPS="nodejs-lts"               # installed via pkg if missing
TOOL_NPM_LIBC=glibc                  # npm platform-package selection
TOOL_NATIVE_BINARY="lib/node_modules/@my/agent-linux-arm64/agent"
TOOL_ENV=( "AGENT_TELEMETRY=0" )
TOOL_AUTH="agent login"
TOOL_NOTES="Termux-specific notes"

tool_post_install() {   # optional: $1=install dir  $2=binary path
	return 0
}
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `command not found` | open a new session, or `eval "$(aify env)"` |
| `glibc backend not available` | `aify backend setup glibc` |
| Binary broke after install (self-update) | `aify install <id>` — re-prepares the backend |
| Codex sandbox error | Android has no landlock/seccomp: add `sandbox_mode = "danger-full-access"` to `~/.codex/config.toml` (make that security tradeoff knowingly) |
| Claude Code self-updates and breaks | `DISABLE_AUTOUPDATER=1` is already set; update via `aify update claude` instead |
| `Unable to locate package aify` | the repo line was never written — run the `mkdir -p` from the install step first |
| `invalid ELF header` when running a tool | the state has a stale backend; `aify install <id>` re-resolves it (`aify run` also self-corrects) |
| Network errors under the glibc backend (`token exchange failed`, DNS) | `aify backend setup glibc` — writes `$PREFIX/glibc/etc/resolv.conf`; set your own with `aify config set glibc.dns "1.1.1.1 8.8.8.8"` |
| See everything | `aify doctor` and `AIFY_DEBUG=1 aify ...` |

Environment variables: `AIFY_HOME` (default `~/.aify`), `AIFY_YES=1` (skip prompts),
`AIFY_DEBUG=1`, `NO_COLOR=1`.

---

## Development

```bash
make check     # 86 tests (also runs outside Termux)
make lint      # shellcheck
make deb       # dist/aify_<version>_all.deb
make apt-repo  # a publish-ready apt repo under site/
make install DESTDIR=/tmp/stage PREFIX=/usr
```

The tests cover: registry-file validity, ELF classification, binary resolution across npm
layouts (including nested and "stub"-wrapper cases), the backend auto-switching to glibc for
glibc-linked binaries, `.deb` contents, the apt repo's structure (including Release checksums),
and the `make install/uninstall` flow. The release workflow additionally verifies the repo with
a **real `apt-get update`** on the `aarch64` architecture.

## License

MIT — see [LICENSE](LICENSE). The tools listed here carry their own licenses and terms of use;
`aify` is only the install/run layer and has no official affiliation with any of them.
