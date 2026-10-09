"""phu: code output and plots in the phunotes look, for Quarto books and reports.

Code stays ordinary. In a kernel that Quarto starts for a document using
the look (`phu-look: true`, set by the phu-* formats), the IPython startup
file that install.sh links calls setup(). What a value looks like then
depends on its type only, through IPython's display formatters; nothing
reads printed text, so print() output is always console text.

  pandas DataFrame  pandas' own HTML table; Quarto turns it into a native
                    table in every format. Long and wide frames are cut by
                    pandas' display options (PANDAS_OPTIONS).
  pandas Series     the same table, with one column.
  numpy ndarray     2-D of numbers or booleans: a bracketed matrix (bmatrix,
                    in Markdown, so LaTeX, MathJax and MathML all draw it),
                    with its dtype and shape underneath.
  anything else     its own representation (text, HTML, LaTeX, images).

Plots: matplotlib reads phu.mplstyle (through MATPLOTLIBRC, before it is
imported) and seaborn gets the look's palette. The plate details are opt-in
helpers: centerline, dimension, mark. Outside Quarto: plt.style.use(phu.STYLE).

PHU_DISPLAY=0 turns everything off.
"""
import json
import os
import sys

STYLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "phu.mplstyle")
INK, ACCENT, FAINT, RULE = "#1f1d1a", "#b4442b", "#8a8374", "#c9c0ad"

# pandas' own truncation, sized for a printed page
PANDAS_OPTIONS = {
    "display.max_rows": 14,     # longer frames show min_rows: head and tail
    "display.min_rows": 10,
    "display.max_columns": 8,
    "display.max_colwidth": 40,
}

# matrices: larger ones keep their first and last rows/columns
ARRAY_ROWS, ARRAY_COLS = 10, 8
ARRAY_HEAD, ARRAY_TAIL = 5, 3


def wants_look(info_path=None):
    """Does the document Quarto is rendering use the look?

    Quarto describes the render in the JSON file named by
    QUARTO_EXECUTE_INFO; the look is on when its format metadata has
    `phu-look: true`.
    """
    path = info_path or os.environ.get("QUARTO_EXECUTE_INFO")
    if not path:
        return False
    try:
        with open(path, encoding="utf-8") as fh:
            info = json.load(fh)
    except (OSError, ValueError):
        return False
    return (info.get("format") or {}).get("metadata", {}).get("phu-look") is True


# --- display by type ---------------------------------------------------------
def series_html(series):
    """A Series as pandas shows a one-column DataFrame."""
    name = series.name if series.name is not None else ""
    return series.to_frame(name=name)._repr_html_()


def _keep(n, limit):
    """Positions to show along an axis of length n; None marks the gap."""
    if n <= limit:
        return list(range(n))
    return list(range(ARRAY_HEAD)) + [None] + list(range(n - ARRAY_TAIL, n))


def array_markdown(a):
    """A 2-D numeric or boolean array as a matrix; None for anything else."""
    np = sys.modules["numpy"]
    if a.ndim != 2 or a.size == 0 or a.dtype.kind not in "biuf":
        return None
    rows, cols = _keep(a.shape[0], ARRAY_ROWS), _keep(a.shape[1], ARRAY_COLS)
    ri = [r for r in rows if r is not None]
    ci = [c for c in cols if c is not None]
    sub = a[np.ix_(ri, ci)]
    # numpy formats the numbers (precision, suppress, ...); the tab only
    # separates them, it can't occur in a formatted number
    text = np.array2string(sub, separator="\t", threshold=sys.maxsize, max_line_width=sys.maxsize)
    cells = [[v.strip(" []") for v in line.split("\t")] for line in text.split("\n")]
    negative = sub < 0 if a.dtype.kind in "iuf" else np.zeros(sub.shape, dtype=bool)

    lines = []
    for i, r in enumerate(rows):
        if r is None:
            lines.append(" & ".join(r"\ddots" if c is None else r"\vdots" for c in cols))
            continue
        k = ri.index(r)
        out = []
        for c in cols:
            if c is None:
                out.append(r"\cdots")
                continue
            j = ci.index(c)
            v = r"\texttt{" + cells[k][j] + "}"
            out.append(r"\phuneg{" + v + "}" if negative[k, j] else v)
        lines.append(" & ".join(out))
    shape = f"{a.dtype} · {a.shape[0]} × {a.shape[1]}"
    return ("::: {.phu-array}\n$$\n\\begin{bmatrix}\n" + " \\\\\n".join(lines)
            + "\n\\end{bmatrix}\n$$\n\n[" + shape + "]{.phu-shape}\n:::\n")


def _guard(fn):
    """A formatter that can't break a cell: on any error, None (the default display)."""
    def run(obj):
        try:
            return fn(obj)
        except Exception:  # noqa: BLE001
            return None
    return run


def register_display(ip=None):
    """Hook the formatters above into IPython (types by name: nothing imported)."""
    if ip is None:
        from IPython import get_ipython
        ip = get_ipython()
    if ip is None:
        return
    fmt = ip.display_formatter.formatters
    fmt["text/html"].for_type_by_name("pandas", "Series", _guard(series_html))
    fmt["text/markdown"].for_type_by_name("numpy", "ndarray", _guard(array_markdown))


def _pandas_options(pd):
    for key, value in PANDAS_OPTIONS.items():
        pd.set_option(key, value)


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
# seaborn fills boxes and bars with its first colour: a warm grey keeps
# medians and edges readable; lines follow with rust and ink
SEABORN_PALETTE = ["#9a9384", ACCENT, "#4b463e", RULE, INK]


def _after_import(name, fn):
    """Run fn(module) once `name` is imported (now, if it already is)."""
    import importlib.abc
    import importlib.util

    if name in sys.modules:
        fn(sys.modules[name])
        return

    class Hook(importlib.abc.MetaPathFinder):
        def find_spec(self, fullname, path, target=None):
            if fullname != name:
                return None
            sys.meta_path.remove(self)
            spec = importlib.util.find_spec(fullname)
            if spec is None or spec.loader is None:
                return spec
            run = spec.loader.exec_module

            def exec_module(module):
                run(module)
                try:
                    fn(module)
                except Exception:  # noqa: BLE001  looks must never break an import
                    pass

            spec.loader.exec_module = exec_module
            return spec

    sys.meta_path.insert(0, Hook())


def setup(ip=None):
    """The look for this kernel: plot style, pandas options, display by type."""
    os.environ.setdefault("MATPLOTLIBRC", STYLE)
    _after_import("seaborn", lambda sns: sns.set_palette(SEABORN_PALETTE))
    _after_import("pandas", _pandas_options)
    register_display(ip)
