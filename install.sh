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

# Fonts of the look (EB Garamond, IBM Plex Mono) from TeX Live, for
# matplotlib and the browser; matplotlib rescans after its cache is gone.
FONTS="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/doc-kit"
mkdir -p "$FONTS"
for f in $(kpsewhich -all EBGaramond-{Regular,Italic,Medium,SemiBold,SemiBoldItalic,Bold,BoldItalic}.otf \
             IBMPlexMono-{Regular,Italic,SemiBold,Bold}.otf 2>/dev/null); do
  ln -sfn "$f" "$FONTS/"
done
fc-cache -f "$FONTS" >/dev/null 2>&1 || true
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}"/matplotlib/fontlist-*.json
echo "fonts -> $FONTS"

# Code output in the look, only inside Quarto renders (QUARTO_DOCUMENT_PATH):
# an IPython startup file for Python kernels, a line in ~/.Rprofile for R.
STARTUP="$HOME/.ipython/profile_default/startup"
mkdir -p "$STARTUP"
ln -sfn "$REPO/python/ipython_startup.py" "$STARTUP/50-doc-kit.py"
RLINE="if (nzchar(Sys.getenv(\"QUARTO_DOCUMENT_PATH\")) && Sys.getenv(\"PHU_DISPLAY\") != \"0\" && file.exists(\"$REPO/r/phu.R\")) source(\"$REPO/r/phu.R\")"
if ! grep -qF "$REPO/r/phu.R" "$HOME/.Rprofile" 2>/dev/null; then
  printf '\n# doc-kit: phunotes-style output when Quarto renders\n%s\n' "$RLINE" >> "$HOME/.Rprofile"
fi
echo "display helpers -> $STARTUP/50-doc-kit.py, ~/.Rprofile"
