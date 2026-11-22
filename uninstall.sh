#!/usr/bin/env bash
# Remove o comando ps5, a configuração dele, o perfil do frame gen e a regra de janela do KDE.
# Não remove o lsfg-vk (pode estar sendo usado por jogos); para isso veja o README.
set -euo pipefail
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
APP_ID="ps5-capture"

"$HOME/.local/bin/ps5" off >/dev/null 2>&1 || true
rm -f "$HOME/.local/bin/ps5"
rm -rf "$CFG/ps5-capture"
echo "✓ comando ps5 e ~/.config/ps5-capture removidos"

CONF="$CFG/lsfg-vk/conf.toml"
if [ -f "$CONF" ] && grep -q "name = \"$APP_ID\"" "$CONF"; then
  cp "$CONF" "$CONF.bak.$(date +%s)"
  # apaga o bloco [[profile]] cujo name é ps5-capture
  awk -v id="$APP_ID" '
    /^\[\[profile\]\]/ { if (blk != "" && !skip) printf "%s", blk; blk = $0 "\n"; skip = 0; inblk = 1; next }
    inblk { blk = blk $0 "\n"; if ($0 ~ "^name = \"" id "\"") skip = 1; next }
    { print }
    END { if (blk != "" && !skip) printf "%s", blk }' "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
  echo "✓ perfil '$APP_ID' removido de $CONF (backup ao lado)"
fi

if command -v kwriteconfig6 >/dev/null; then
  kwriteconfig6 --file kwinrulesrc --group "$APP_ID" --key Description --delete >/dev/null 2>&1 || true
  sed -i "/^\[$APP_ID\]/,/^\[/{/^\[$APP_ID\]/d;/^\[/!d}" "$CFG/kwinrulesrc" 2>/dev/null || true
  regras="$(kreadconfig6 --file kwinrulesrc --group General --key rules | tr ',' '\n' | { grep -vx "$APP_ID" || true; } | paste -sd, -)"
  kwriteconfig6 --file kwinrulesrc --group General --key rules "$regras"
  kwriteconfig6 --file kwinrulesrc --group General --key count "$(tr ',' '\n' <<<"$regras" | grep -c . || true)"
  qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  echo "✓ regra de janela do KDE removida"
fi
