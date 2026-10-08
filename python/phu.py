"""phu: plots in the phunotes look, for Quarto books and reports.

Code stays ordinary: plt.plot(...), df.plot(), seaborn. In a Quarto kernel
whose document uses the look (a phu-* format or `phu-look: true`), the
IPython startup file that install.sh writes calls setup(), which points
matplotlib at phu.mplstyle through MATPLOTLIBRC before anything imports
it. Printed and displayed output is untouched here: the phu filter
(extensions/phu/phu-output.lua) typesets it. PHU_DISPLAY=0 turns it off.

The plate details are opt-in helpers: centerline, dimension, mark.
Outside Quarto: plt.style.use(phu.STYLE).
"""
import os
import re

STYLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "phu.mplstyle")
INK, ACCENT, FAINT, RULE = "#1f1d1a", "#b4442b", "#8a8374", "#c9c0ad"

LOOK = re.compile(r"phu-look:\s*true|\bphu-(pdf|html|epub)(?![.\w-])")


def _read(path, limit=200_000):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read(limit)
    except OSError:
        return ""


def wants_look(doc_dir=None, doc_file=None):
    """Does the document Quarto is rendering use the look?

    Looks at the document itself, then the project's _quarto*.yml and the
    files its metadata-files list.
    """
    doc_dir = doc_dir or os.environ.get("QUARTO_DOCUMENT_PATH", "")
    doc_file = doc_file or os.environ.get("QUARTO_DOCUMENT_FILE", "")
    if not doc_dir:
        return False
    texts = [_read(os.path.join(doc_dir, doc_file))] if doc_file else []
    d = os.path.abspath(doc_dir)
    while True:
        ymls = sorted(f for f in os.listdir(d) if re.fullmatch(r"_quarto(-[\w-]+)?\.ya?ml", f))
        for y in ymls:
            text = _read(os.path.join(d, y))
            texts.append(text)
            for ref in re.findall(r"^\s*-\s*(\S+\.ya?ml)\s*$", text, re.M):
                texts.append(_read(os.path.normpath(os.path.join(d, ref))))
        parent = os.path.dirname(d)
        if ymls or parent == d:
            break
        d = parent
    return any(LOOK.search(t) for t in texts)


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
    import sys

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
                except Exception:  # looks must never break an import
                    pass

            spec.loader.exec_module = exec_module
            return spec

    sys.meta_path.insert(0, Hook())


def setup():
    """Plot style for this kernel (before matplotlib is imported)."""
    os.environ.setdefault("MATPLOTLIBRC", STYLE)
    _after_import("seaborn", lambda sns: sns.set_palette(SEABORN_PALETTE))
