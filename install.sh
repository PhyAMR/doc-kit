#!/bin/bash
# Install doc-kit from this checkout: newdoc on PATH, the LaTeX packages where
# TeX finds them, and an author file to fill in. Re-running is safe.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
REPO=$(pwd)
BIN="$HOME/.local/bin"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/doc-kit/author.conf"
TEXMFHOME=$(kpsewhich -var-value TEXMFHOME 2>/dev/null || echo "$HOME/texmf")

mkdir -p "$BIN" "$TEXMFHOME/tex/latex" "$(dirname "$CONF")"
chmod +x bin/newdoc
ln -sfn "$REPO/bin/newdoc" "$BIN/newdoc"
ln -sfn "$REPO/latex" "$TEXMFHOME/tex/latex/phu"
echo "newdoc -> $BIN/newdoc; phunotes/phumacros -> $TEXMFHOME/tex/latex/phu"

if [[ ! -f $CONF ]]; then
  cp author.conf.example "$CONF"
  echo "Wrote $CONF: fill in your name and affiliation"
fi
