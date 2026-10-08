"""phu: code output in Quarto documents, in the phunotes look.

Loaded automatically in every Quarto Jupyter kernel by the IPython startup
file that install.sh writes (it checks QUARTO_DOCUMENT_PATH; PHU_DISPLAY=0
turns it off). It

- shows numpy arrays (1-D and 2-D) as a ::: {.phu-array} grid that the phu
  filter turns into a bracketed array in the PDF and a styled table in HTML;
  long vectors and big matrices keep only their head and tail;
- shows pandas DataFrames and Series as a booktabs table, truncated the
  same way, with a "1000 rows × 5 columns" line;
- points matplotlib at phu.mplstyle (MATPLOTLIBRC), and gives three
  drawing helpers for the plate look: centerline, dimension, mark.

Outside Quarto: `import phu; phu.setup()` in IPython, or
`plt.style.use(phu.STYLE)` for the plots alone.
"""
import math
import os

STYLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "phu.mplstyle")

MAX_VECTOR = 12  # longer vectors show HEAD … TAIL
MAX_ROWS = 10
MAX_COLS = 8
HEAD, TAIL = 5, 3
FRAME_ROWS, FRAME_HEAD, FRAME_TAIL = 14, 6, 4
FRAME_COLS = 8
MAX_TEXT = 40

VDOTS, CDOTS, DDOTS, MINUS = "⋮", "⋯", "⋱", "−"

INK, ACCENT, FAINT, RULE = "#1f1d1a", "#b4442b", "#8a8374", "#c9c0ad"


# --- number formatting --------------------------------------------------
def _decimals(x, cap=4):
    s = f"{abs(x):.{cap}f}".rstrip("0")
    return len(s.split(".")[1]) if "." in s else 0


def format_numbers(values):
    """One format for a whole array or column, so the digits line up."""
    vals = list(values)
    if not vals:
        return []
    if all(isinstance(v, bool) for v in vals):
        return [str(v) for v in vals]
    if all(isinstance(v, int) for v in vals):
        return [str(v).replace("-", MINUS) for v in vals]
    if any(isinstance(v, complex) for v in vals):
        return [f"{complex(v):.3g}".strip("()").replace("-", MINUS) for v in vals]
    finite = [abs(float(v)) for v in vals if math.isfinite(float(v)) and v != 0]
    big, small = (max(finite), min(finite)) if finite else (0.0, 0.0)
    if big >= 1e5 or (0 < small < 1e-3 and big < 1):
        fmt = "{:.3e}"
    else:
        d = max([_decimals(float(v)) for v in vals if math.isfinite(float(v))] or [1])
        fmt = "{:.%df}" % min(max(d, 1), 4)
    out = []
    for v in vals:
        v = float(v)
        out.append(str(v) if not math.isfinite(v) else fmt.format(v).replace("-", MINUS))
    return out


def _escape(text):
    text = str(text)
    if len(text) > MAX_TEXT:
        text = text[: MAX_TEXT - 1] + "…"
    for ch in "\\|*_`[]<>$#":
        text = text.replace(ch, "\\" + ch)
    return text.replace("\n", " ")


def _pick(n, limit, head, tail):
    """Indices to show, with None where the gap goes."""
    if n <= limit:
        return list(range(n))
    return list(range(head)) + [None] + list(range(n - tail, n))


def _pipe_table(header, rows, align):
    lines = ["| " + " | ".join(header) + " |",
             "|" + "|".join("--:" if a == "r" else ":--" for a in align) + "|"]
    lines += ["| " + " | ".join(r) + " |" for r in rows]
    return "\n".join(lines)


# --- numpy ----------------------------------------------------------------
def array_markdown(a):
    import numpy as np

    a = np.asarray(a)
    if a.ndim not in (1, 2) or a.size == 0 or a.dtype.kind not in "biufc":
        return None
    m = a.reshape(1, -1) if a.ndim == 1 else a
    rows = [None] if a.ndim == 1 else _pick(m.shape[0], MAX_ROWS, HEAD, TAIL)
    cols = _pick(m.shape[1], MAX_VECTOR if a.ndim == 1 else MAX_COLS, HEAD, TAIL)
    real_rows = [0] if a.ndim == 1 else [r for r in rows if r is not None]
    real_cols = [c for c in cols if c is not None]
    shown = m[np.ix_(real_rows, real_cols)]
    text = iter(format_numbers(shown.ravel().tolist()))

    header = [""] + [CDOTS if c is None else str(c) for c in cols]
    body = []
    for r in rows if a.ndim == 2 else ["vector"]:
        if r is None:
            body.append([VDOTS] + [DDOTS if c is None else VDOTS for c in cols])
            continue
        cells = [next(text) if c is not None else CDOTS for c in cols]
        body.append(["" if a.ndim == 1 else str(r)] + cells)
    shape = " × ".join(str(s) for s in a.shape)
    table = _pipe_table(header, body, ["r"] * len(header))
    return f"::: {{.phu-array}}\n{table}\n\n{a.dtype} · {shape}\n:::\n"


# --- pandas ---------------------------------------------------------------
def _column_text(col):
    import pandas as pd

    if pd.api.types.is_bool_dtype(col):
        return [str(v) for v in col], "l"
    if pd.api.types.is_numeric_dtype(col):
        vals = col.tolist()
        present = [v for v in vals if not pd.isna(v)]
        text = iter(format_numbers(present))
        return [("NA" if pd.isna(v) else next(text)) for v in vals], "r"
    return [_escape(v) for v in col], "l"


def frame_markdown(df):
    import pandas as pd

    if isinstance(df, pd.Series):
        df = df.to_frame(name=df.name if df.name is not None else "")
    n, m = df.shape
    rows = _pick(n, FRAME_ROWS, FRAME_HEAD, FRAME_TAIL)
    cols = _pick(m, FRAME_COLS, HEAD, TAIL)
    real_rows = [r for r in rows if r is not None]
    real_cols = [c for c in cols if c is not None]
    part = df.iloc[real_rows, real_cols]

    texts, align = [], ["l"]
    for j in range(part.shape[1]):
        t, al = _column_text(part.iloc[:, j])
        texts.append(t)
        align.append(al)
    names = [" · ".join(map(str, c)) if isinstance(c, tuple) else str(c)
             for c in part.columns]
    index_name = " · ".join(str(x) for x in df.index.names if x is not None)

    header, k = [_escape(index_name)], 0
    for c in cols:
        if c is None:
            header.append(CDOTS)
        else:
            header.append(_escape(names[k]))
            k += 1
    body, i = [], 0
    for r in rows:
        if r is None:
            body.append([VDOTS] * len(header))
            continue
        label = part.index[i]
        label = " · ".join(map(str, label)) if isinstance(label, tuple) else label
        row, k = [_escape(label)], 0
        for c in cols:
            if c is None:
                row.append(CDOTS)
            else:
                row.append(texts[k][i])
                k += 1
        body.append(row)
        i += 1
    full_align = [align[0]]
    k = 1
    for c in cols:
        full_align.append("r" if c is None else align[k])
        k += c is not None
    table = _pipe_table(header, body, full_align)
    return (f"::: {{.phu-frame}}\n{table}\n\n"
            f"{n} rows × {m} columns\n:::\n")


# --- matplotlib helpers (the plate look) -----------------------------------
def centerline(ax, y=0.0, **kw):
    """Dash-dot centre line across the axes, as on a drawing."""
    kw = {"color": FAINT, "linewidth": 0.7, "linestyle": (0, (10, 3, 2, 3)), "zorder": 1.5, **kw}
    return ax.axhline(y, **kw)


def mark(ax, x, y, size=7, **kw):
    """Small accent cross at (x, y)."""
    kw = {"color": ACCENT, "markersize": size, "markeredgewidth": 0.9, "zorder": 3, **kw}
    return ax.plot(x, y, marker="+", linestyle="none", **kw)


def dimension(ax, x0, x1, y, text, ext_from=None, **kw):
    """Dimension line between x0 and x1 at height y, labelled in its middle.

    ext_from=(y0, y1) draws extension lines from those heights up to y.
    """
    color = kw.pop("color", "#4b463e")
    ax.annotate("", xy=(x0, y), xytext=(x1, y),
                arrowprops={"arrowstyle": "<|-|>", "color": color, "linewidth": 0.7,
                            "shrinkA": 0, "shrinkB": 0, "mutation_scale": 7})
    if ext_from is not None:
        for x, y0 in zip((x0, x1), ext_from):
            ax.plot([x, x], [y0, y], color=color, linewidth=0.5, zorder=1.6)
    ax.text((x0 + x1) / 2, y, text, ha="center", va="center", fontsize="small",
            bbox={"facecolor": "white", "edgecolor": "none", "pad": 1.5}, **kw)


# --- setup ------------------------------------------------------------------
def setup(ip=None):
    """Register the display formatters (numpy, pandas) and the plot style."""
    os.environ.setdefault("MATPLOTLIBRC", STYLE)
    if ip is None:
        try:
            ip = get_ipython()  # noqa: F821
        except NameError:
            return
    md = ip.display_formatter.formatters["text/markdown"]
    html = ip.display_formatter.formatters["text/html"]
    latex = ip.display_formatter.formatters["text/latex"]
    md.for_type_by_name("numpy", "ndarray", array_markdown)
    # pandas 3 names its classes pandas.DataFrame, older ones pandas.core.frame.DataFrame
    for module, kind in (("pandas", "DataFrame"), ("pandas", "Series"),
                         ("pandas.core.frame", "DataFrame"), ("pandas.core.series", "Series")):
        md.for_type_by_name(module, kind, frame_markdown)
        # pandas' own HTML/LaTeX would win over markdown: switch them off
        html.for_type_by_name(module, kind, _nothing)
        latex.for_type_by_name(module, kind, _nothing)


def _nothing(_):
    return None
