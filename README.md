# aify — Termux için yapay zekâ CLI yöneticisi

`aify`, telefonundaki Termux'ta **Claude Code, OpenAI Codex, Gemini CLI, Antigravity CLI (`agy`),
GitHub CLI, opencode** ve benzeri terminal yapay zekâ araçlarını tek komutla kuran, güncelleyen ve
**doğru arka uç ile** çalıştıran bir Termux paketidir.

opencode ya da opencodex gibi projeler *tek bir ajanı* sunar; `aify` ise onları da içine alan bir
**yönetici**dir: her araç için yalıtılmış bir dizin, PATH'e düşen ince bir shim ve — en önemlisi —
Termux'ta (Android/bionic) çalışmayan ikililer için otomatik bir kaçış yolu sağlar.

```
pkg install aify          # ya da: curl -fsSL .../install.sh | bash
aify setup
aify install gemini codex gh
aify install claude       # glibc arka ucunu kendisi önerir
aify codex "bu repoda testleri çalıştır"
```

---

## Neden gerekli? (Termux'un asıl sorunu)

Android **bionic** libc kullanır; Linux dağıtımlarının `glibc`/`musl` ikilileri Termux'ta doğrudan
çalışmaz. 2025'ten beri bu araçların çoğu saf JavaScript olmaktan çıkıp **platforma özel yerli
ikili** dağıtıyor ve hiçbirinin Android yapısı yok. Üstelik Termux'ta Node `process.platform`
değerini `android` verdiği için `npm`, `os: ["linux"]` işaretli platform paketlerini **sessizce
atlar** — `npm i -g @anthropic-ai/claude-code` bu yüzden çalışmayan bir kabuk bırakır.

`aify` bu üç sorunu birden çözer:

1. npm'e hedefi açıkça söyler (`--os=linux --cpu=arm64 --libc=glibc`),
2. kurulumdan sonra ikilinin ELF sınıfını okur (statik / glibc / musl / betik),
3. sınıfa göre arka ucu seçer ve shim'i ona göre yazar.

| Sınıf | Örnek | Arka uç |
|---|---|---|
| yorumlanan betik (node) | Gemini CLI, Qwen Code | `native` |
| statik ELF | Codex, Crush | `native` |
| glibc'e bağlı ELF | Claude Code, `agy`, opencode, Copilot CLI | `glibc` (glibc-runner) veya `proot` |
| musl'a bağlı ELF | bazı bun/musl yapıları | `proot` |

### Arka uçlar

| Arka uç | Nasıl | Maliyet | Hazırlık |
|---|---|---|---|
| `native` | Termux içinde doğrudan | yok | hazır |
| `glibc` | [glibc-runner](https://github.com/termux-pacman/glibc-packages) (`grun`) ile dinamik yükleyici | ~100 MB | `aify backend setup glibc` |
| `proot` | `proot-distro` Debian kabı | ~500 MB, biraz yavaş | `aify backend setup proot` |

`proot` arka ucunda `$HOME` ve içinde bulunduğun dizin kaba **aynı yollarla** bağlanır; yani
`~/.claude`, `~/.codex` gibi ayarlar yerli kurulumla aynı yerde durur, projelerin de aynı
yoldan görünür.

---

## Desteklenen araçlar

`aify list` ile güncel listeyi görebilirsin.

| id | Araç | Kaynak | Termux'ta | Not |
|---|---|---|---|---|
| `claude` | Claude Code | npm `@anthropic-ai/claude-code` | glibc / proot | 2.x yerli ikili dağıtıyor, Android yapısı yok |
| `codex` | OpenAI Codex CLI | npm `@openai/codex` | **yerli** | `aarch64-*-musl` hedefi statik; sarmalayıcı `android`'i tanıyor |
| `gemini` | Gemini CLI | npm `@google/gemini-cli` | **yerli** | saf JS |
| `qwen` | Qwen Code | npm `@qwen-code/qwen-code` | **yerli** | saf JS |
| `agy` | Antigravity CLI | resmi kurulum betiği | glibc / proot | sha512 doğrulamalı yerli ikili (glibc) |
| `gh` | GitHub CLI | Termux paketi | **yerli** | `pkg install gh` |
| `opencode` | opencode | npm `opencode-ai` | glibc / proot | bun ile derlenmiş ikili |
| `copilot` | GitHub Copilot CLI | npm `@github/copilot` | glibc / proot | |
| `opencodex` | OpenCodex | npm `@bitkyc08/opencodex` | **yerli** | Codex/Claude Code için sağlayıcı proxy'si |
| `ccr` | Claude Code Router | npm `@musistudio/claude-code-router` | **yerli** | modeli yönlendirir |
| `crush` | Crush | GitHub sürümleri | **yerli** | Go ikilisi statik |
| `aider` | Aider | `uv` / `pipx` | proot (yerli deneysel) | Android için hazır wheel yok |

Ayrıntı için: `aify info <id>` — her araç için giriş yöntemi, arka uç gerekçesi ve Termux'a
özgü notlar orada yazılıdır.

---

## Kurulum

### 1) apt deposundan (önerilen)

```bash
echo "deb [trusted=yes] https://mrhakan.github.io/termux-aify aify main" \
  > $PREFIX/etc/apt/sources.list.d/aify.list
pkg update && pkg install aify
```

> Depo, `v*` etiketi atıldığında (ya da `release` iş akışı elle çalıştırıldığında — bu durumda
> etiketi iş akışının kendisi oluşturur) GitHub Pages'e yayımlanır.
> (Repo ayarlarında **Settings → Pages → Source: GitHub Actions** seçili olmalı; aksi hâlde
> `pages` işi hata verir, `.deb` yine de sürüme eklenir.)

### 2) Hazır `.deb` ile

```bash
curl -fsSL https://raw.githubusercontent.com/MrHakan/termux-aify/main/install.sh | bash
```

Betik önce son sürümdeki `.deb`'i dener, bulamazsa kaynaktan kurar.

### 3) Kaynaktan

```bash
git clone https://github.com/MrHakan/termux-aify
cd termux-aify
make install            # PREFIX Termux'ta otomatik
```

### 4) termux-packages ağacında derlemek

`packaging/termux-packages/aify/` dizinini `termux-packages/packages/aify/` altına kopyalayıp:

```bash
./build-package.sh -a all aify
```

---

## Arayüz

Terminalde tek başına `aify` yazınca ASCII logolu etkileşimli arayüz açılır — kurulum,
çalıştırma, arka uç seçimi, teşhis; hepsi buradan:

```
  ▄▀█ █ █▀▀ █▄█   aify v0.1.0
  █▀█ █ █▀░  █    Termux için yapay zekâ CLI yöneticisi

  Termux · aarch64 · node 24.18.0 · arka uç: native,glibc

╭─ Araçlar ─────────────────────────────────────────────╮
│ ❯ claude      Claude Code             ● glibc         │
│   codex       OpenAI Codex CLI        ● native        │
│   gemini      Gemini CLI              ○ native        │
│   agy         Antigravity CLI         ○ glibc         │
╰───────────────────────────────────────────────────────╯

  i kur   r çalıştır   enter bilgi   d sil   u güncelle
  b arka uçlar   t teşhis   / komut   ? yardım   q çıkış
```

| Tuş | İş |
|---|---|
| `↑` `↓` (veya `j` `k`) | araçlar arasında gezin |
| `enter` | seçili araç için işlem menüsü (bilgi / kur / çalıştır / güncelle / kaldır / arka uç) |
| `i` `r` `d` `u` | doğrudan kur, çalıştır, kaldır, güncelle |
| `b` | arka uç ekranı (glibc / proot kurulumu) |
| `t` | `aify doctor` |
| `/` | serbest komut satırı (`install gemini`, `config list`, …) |
| `?` | yardım · `q` çıkış |

Arayüz alternatif ekranda açılır, çıkışta terminali olduğu gibi bırakır. Betik içinden ya da
boruyla çağrıldığında (TTY yoksa) otomatik olarak eski davranışa, yani yardım metnine düşer;
`aify ui` ile zorlayabilir, `aify banner` ile yalnızca logoyu yazdırabilirsin.
Unicode olmayan bir terminalde `AIFY_ASCII=1` ASCII moduna geçirir.


---

## Kullanım

```
aify                       # etkileşimli arayüz (yukarıdaki ekran)
aify setup                 # dizinler, temel paketler, PATH
aify list                  # araçlar ve kurulum durumu
aify info claude           # ayrıntı + Termux notları
aify install gemini codex  # kur
aify install claude --backend proot
aify update                # kurulu her şeyi güncelle
aify remove opencode
aify run codex --help      # ya da kısayol:  aify codex --help
aify backend status
aify backend setup glibc
aify doctor                # ortam teşhisi
aify config set tool.claude.backend proot
```

Kurulan her araç `~/.aify/bin/<komut>` altında ince bir shim alır; bu dizin
`$PREFIX/etc/profile.d/aify.sh` sayesinde yeni oturumlarda otomatik PATH'e girer. Yani kurulumdan
sonra `claude`, `codex`, `gemini` komutlarını doğrudan yazabilirsin — `aify run` şart değil.

### Dizin düzeni

```
~/.aify/
├── bin/            # PATH'e giren shim'ler
├── tools/<id>/     # araç başına yalıtılmış kurulum (npm --prefix)
├── state/<id>      # arka uç, ikili yolu, sürüm, ELF sınıfı
├── registry.d/     # senin eklediğin araç tanımları
├── cache/  log/
└── config          # anahtar=değer
```

Paketi kaldırmak `~/.aify` içindekilere dokunmaz: `pkg uninstall aify && rm -rf ~/.aify`.

---

## Kendi aracını ekleme

Üç hazır yol:

```bash
aify add-npm @benim/ajanim --bin ajan      # herhangi bir npm CLI
aify add-gh  charmbracelet/crush --bin crush   # GitHub sürüm ikilisi
aify add-pkg glab                          # Termux paketi
```

…ya da `~/.aify/registry.d/<id>.tool` dosyasını elle yaz (dahili tanımlarla aynı biçim,
aynı adı kullanırsan dahili tanımı ezer):

```sh
TOOL_ID=ajan
TOOL_NAME="Benim Ajanım"
TOOL_SUMMARY="kısa açıklama"
TOOL_KIND=npm                 # npm | pkg | github | installer | uv
TOOL_PACKAGE="@benim/ajanim"
TOOL_BIN=ajan
TOOL_BACKENDS="native glibc proot"   # tercih sırası
TOOL_DEPS="nodejs-lts"               # eksikse pkg ile kurulur
TOOL_NPM_LIBC=glibc                  # npm platform paketi seçimi
TOOL_NATIVE_BINARY="lib/node_modules/@benim/ajanim-linux-arm64/ajan"
TOOL_ENV=( "AJAN_TELEMETRY=0" )
TOOL_AUTH="ajan login"
TOOL_NOTES="Termux'a özgü notlar"

tool_post_install() {   # istege bagli: $1=kurulum dizini  $2=ikili yolu
	return 0
}
```

---

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| `komut bulunamadı` | Yeni oturum aç ya da `eval "$(aify env)"` |
| `glibc arka ucu yok` | `aify backend setup glibc` |
| Kurulum sonrası ikili bozuldu (otomatik güncelleme) | `aify install <id>` — arka uç yeniden hazırlanır |
| Codex sandbox hatası | Android'de landlock/seccomp yok: `~/.codex/config.toml` içine `sandbox_mode = "danger-full-access"` (güvenlik kararını bilerek ver) |
| Claude Code kendini güncelleyip bozuyor | `DISABLE_AUTOUPDATER=1` zaten ayarlı; güncellemeyi `aify update claude` ile yap |
| Her şeyi görmek | `aify doctor` ve `AIFY_DEBUG=1 aify ...` |

Ortam değişkenleri: `AIFY_HOME` (varsayılan `~/.aify`), `AIFY_YES=1` (soru sorma),
`AIFY_DEBUG=1`, `NO_COLOR=1`.

---

## Geliştirme

```bash
make check     # 82 test (Termux dışında da çalışır)
make lint      # shellcheck
make deb       # dist/aify_<sürüm>_all.deb
make apt-repo  # site/ altında yayına hazır apt deposu
make install DESTDIR=/tmp/stage PREFIX=/usr
```

Testler; kayıt dosyalarının geçerliliğini, ELF sınıflandırmasını, npm yerleşimlerinde ikili
çözümlemeyi (iç içe ve "stub" sarmalayıcı durumları dâhil), glibc ikilisinde arka ucun otomatik
değişmesini, `.deb` içeriğini, apt deposunun yapısını (Release karma değerleri dâhil) ve
`make install/uninstall` akışını doğrular. Sürüm iş akışı ayrıca depoyu **gerçek `apt-get update`
ile** `aarch64` mimarisinde doğrular.

## Lisans

MIT — bkz. [LICENSE](LICENSE). Buradaki araçların kendi lisansları ve kullanım koşulları geçerlidir;
`aify` yalnızca kurulum ve çalıştırma katmanıdır, hiçbiriyle resmî bir bağı yoktur.
