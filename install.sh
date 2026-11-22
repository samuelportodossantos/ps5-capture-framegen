#!/usr/bin/env bash
# Instala o comando ps5: captura de console com frame gen (lsfg-vk) e áudio, no Linux.
#
#   ./install.sh                    janela na metade esquerda do primeiro monitor
#   ./install.sh --janela 2560x1440+0+0    tamanho e posição da janela (LxA+X+Y)
#   ./install.sh --sem-janela       não cria a regra de janela do KDE
#
# Tudo vai para o seu usuário (~/.local e ~/.config). Não usa sudo.
set -euo pipefail

LSFG_VERSION="2.0.0"
LSFG_SHA256="08bdbdf373a111022df87dac7aa87e3b564bb841f961552e3ca85fea12b5aa74"
LSFG_URL="https://builds.lsfg-vk.dev/lsfg-vk-${LSFG_VERSION}.tar.xz"

REPO="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
APP_ID="ps5-capture"
JANELA=""
SEM_JANELA=0

while [ $# -gt 0 ]; do
  case "$1" in
    --janela) JANELA="$2"; shift 2 ;;
    --sem-janela) SEM_JANELA=1; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "opção desconhecida: $1" >&2; exit 1 ;;
  esac
done

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
aviso(){ printf '  \033[33m!\033[0m %s\n' "$*"; }
erro() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

echo "== Dependências"
falta=()
for c in mpv pw-loopback pactl curl tar sha256sum; do command -v "$c" >/dev/null || falta+=("$c"); done
if [ ${#falta[@]} -gt 0 ]; then
  echo "  Faltam: ${falta[*]}"
  echo "  Ubuntu/Debian: sudo apt install mpv pipewire-bin pulseaudio-utils curl xz-utils"
  exit 1
fi
ok "mpv, PipeWire, curl"

echo "== lsfg-vk ${LSFG_VERSION}"
hc="$("$HOME/.local/bin/lsfg-vk-cli" healthcheck 2>&1 || true)"  # ele escreve no stderr
if [[ "$hc" == *"layer version:"*" 2."* ]]; then
  ok "já instalado em ~/.local (camada $(awk '/layer version/ {print $NF}' <<<"$hc"))"
else
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/lsfg.tar.xz" "$LSFG_URL" || erro "não consegui baixar $LSFG_URL"
  echo "$LSFG_SHA256  $tmp/lsfg.tar.xz" | sha256sum -c --quiet - || erro "checksum do lsfg-vk não confere"
  mkdir -p "$HOME/.local"
  tar -xJf "$tmp/lsfg.tar.xz" -C "$HOME/.local"
  "$HOME/.local/bin/lsfg-vk-cli" healthcheck | head -1
  ok "instalado em ~/.local (camada Vulkan + lsfg-vk-cli + lsfg-vk-ui)"
fi

echo "== Lossless Scaling (Steam, branch lsfg-vk)"
DLL=""
for steam in "$HOME/.local/share/Steam" "$HOME/.steam/steam" \
             "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" "$HOME/snap/steam/common/.local/share/Steam"; do
  [ -d "$steam" ] || continue
  libs=("$steam")
  if [ -f "$steam/steamapps/libraryfolders.vdf" ]; then
    while IFS= read -r l; do libs+=("$l"); done < <(sed -n 's/.*"path"[[:space:]]*"\(.*\)".*/\1/p' "$steam/steamapps/libraryfolders.vdf")
  fi
  for lib in "${libs[@]}"; do
    f="$lib/steamapps/common/Lossless Scaling/lsfg-vk.dll"
    [ -f "$f" ] && { DLL="$f"; break 2; }
    [ -f "$lib/steamapps/common/Lossless Scaling/Lossless.dll" ] && SEM_BRANCH=1
  done
done
if [ -z "$DLL" ]; then
  if [ "${SEM_BRANCH:-0}" = 1 ]; then
    erro "Lossless Scaling está instalado, mas não no branch certo. Na Steam: Lossless Scaling > Propriedades > Betas > escolha 'lsfg-vk', espere atualizar e rode o install.sh de novo."
  fi
  erro "não achei o Lossless Scaling. Compre e instale na Steam, troque para o branch 'lsfg-vk' (Propriedades > Betas) e rode de novo."
fi
ok "$DLL"

echo "== Perfil do frame gen (~/.config/lsfg-vk/conf.toml)"
mkdir -p "$CFG/lsfg-vk"
CONF="$CFG/lsfg-vk/conf.toml"
if [ ! -f "$CONF" ]; then
  sed "s|@DLL@|$DLL|" "$REPO/config/lsfg-vk.conf.toml.template" > "$CONF"
  ok "criado"
elif grep -q "name = \"$APP_ID\"" "$CONF"; then
  ok "perfil '$APP_ID' já existe, mantido"
else
  cp "$CONF" "$CONF.bak.$(date +%s)"
  { echo; sed -n '/^\[\[profile\]\]/,$p' "$REPO/config/lsfg-vk.conf.toml.template"; } >> "$CONF"
  grep -q '^dll' "$CONF" || aviso "o seu conf.toml não tem 'dll =' em [global]; aponte para: $DLL"
  ok "perfil '$APP_ID' adicionado (backup do original ao lado)"
fi
"$HOME/.local/bin/lsfg-vk-cli" validate >/dev/null 2>&1 && ok "configuração válida" \
  || { "$HOME/.local/bin/lsfg-vk-cli" validate; erro "configuração do lsfg-vk inválida"; }

echo "== Comando ps5"
mkdir -p "$BIN" "$CFG/ps5-capture"
install -m 755 "$REPO/bin/ps5" "$BIN/ps5"
install -m 644 "$REPO/config/input.conf" "$CFG/ps5-capture/input.conf"
install -m 644 "$REPO/config/drain.lua" "$CFG/ps5-capture/drain.lua"
[ -f "$CFG/ps5-capture/config" ] || install -m 644 "$REPO/config/config.example" "$CFG/ps5-capture/config"
ok "$BIN/ps5"
case ":$PATH:" in *":$BIN:"*) ;; *) aviso "$BIN não está no PATH; abra um terminal novo ou adicione ao seu shell";; esac

echo "== Janela (regra do KDE)"
if [ "$SEM_JANELA" = 1 ]; then
  ok "pulado (--sem-janela)"
elif ! command -v kwriteconfig6 >/dev/null || ! command -v qdbus6 >/dev/null; then
  aviso "kwriteconfig6/qdbus6 não encontrados (não é KDE Plasma 6?). A janela abre onde o compositor quiser."
else
  if [ -z "$JANELA" ]; then
    geo="$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/Geometry:/ {print $2, $3; exit}')"  # "X,Y WxH"
    [ -n "$geo" ] || erro "não consegui ler a geometria do monitor; use --janela LxA+X+Y"
    gx="${geo%%,*}"; rest="${geo#*,}"; gy="${rest%% *}"; wh="${geo##* }"; gw="${wh%x*}"; gh="${wh#*x}"
    JANELA="$((gw / 2))x${gh}+${gx}+${gy}"
  fi
  [[ "$JANELA" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]] || erro "formato de --janela inválido: $JANELA (ex.: 2560x1440+0+0)"
  W="${BASH_REMATCH[1]}"; H="${BASH_REMATCH[2]}"; X="${BASH_REMATCH[3]}"; Y="${BASH_REMATCH[4]}"
  k() { kwriteconfig6 --file kwinrulesrc --group "$APP_ID" --key "$1" "$2"; }
  k Description "Captura de console (ps5)"
  k wmclass "$APP_ID"; k wmclassmatch 1; k wmclasscomplete false
  k position "$X,$Y"; k positionrule 2
  k size "$W,$H"; k sizerule 2
  k noborder true; k noborderrule 2
  k above true; k aboverule 2
  regras="$(kreadconfig6 --file kwinrulesrc --group General --key rules)"
  case ",$regras," in *",$APP_ID,"*) ;; *) regras="${regras:+$regras,}$APP_ID" ;; esac
  kwriteconfig6 --file kwinrulesrc --group General --key rules "$regras"
  kwriteconfig6 --file kwinrulesrc --group General --key count "$(tr ',' '\n' <<<"$regras" | grep -c .)"
  qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  ok "janela ${W}x${H} em ${X},${Y}, sem borda, acima dos painéis"
fi

echo
echo "Pronto. Ligue o console com a placa numa porta USB 3 e rode:  ps5"
echo "Ajuda: ps5 help   |   Configuração da placa/áudio: $CFG/ps5-capture/config"
