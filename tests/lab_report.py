"""Dashboards for the doc-kit lab (written by tests/run; standard library only).

work/index.html          runs over time (sparklines + table) and the latest run's grid
work/runs/<id>/index.html one run: document x format grid, then per-document details
                           with page thumbnails next to the previous run's
"""

from __future__ import annotations

import html
import json
from pathlib import Path

FORMAT_ORDER = ["pdf", "phu-pdf", "html", "phu-html", "phu-epub", "chapter-phu-pdf", "book", "python", "r"]
GLYPH = {"ok": "●", "kit": "▲", "content": "■", "fail": "✕", "timeout": "⧗"}
CLASS_TEXT = {"ok": "ok", "kit": "kit problem", "content": "content problem (also without the kit)",
              "fail": "failed", "timeout": "timed out"}

CSS = """
:root{--paper:#fdfcf9;--ink:#1f1d1a;--faint:#6f6a61;--rule:#e2dccf;--card:#f6f3ec;
--accent:#b4442b;--ok:#4f7a52;--content:#a07d2c;--fail:#5a5550;--changed:#2f5f8a;
--mono:"IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,monospace;
--serif:"EB Garamond",Georgia,serif;--sans:system-ui,-apple-system,"Segoe UI",sans-serif}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--paper:#171614;--ink:#ece6da;
--faint:#a39c90;--rule:#36322d;--card:#211f1c;--accent:#e0775c;--ok:#86b48a;--content:#d4b062;
--fail:#9a948b;--changed:#79a7d3}}
:root[data-theme="dark"]{--paper:#171614;--ink:#ece6da;--faint:#a39c90;--rule:#36322d;--card:#211f1c;
--accent:#e0775c;--ok:#86b48a;--content:#d4b062;--fail:#9a948b;--changed:#79a7d3}
*{box-sizing:border-box}
body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.45 var(--sans)}
main{max-width:1180px;margin:0 auto;padding:28px 16px 80px}
h1{font:600 30px/1.1 var(--serif);margin:0 0 4px}
h2{font:600 21px/1.2 var(--serif);margin:36px 0 10px;padding-top:8px;border-top:1px solid var(--rule)}
h3{font:600 16px/1.3 var(--sans);margin:18px 0 6px}
.sub{color:var(--faint);margin:0 0 18px}
a{color:var(--accent)}
code,.mono{font-family:var(--mono);font-size:12.5px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin:16px 0}
.card{background:var(--card);border-radius:8px;padding:10px 12px}
.card b{display:block;font:600 26px/1.1 var(--serif)}
.card span{color:var(--faint);font-size:12.5px}
.card.kit b{color:var(--accent)}
.scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
table{border-collapse:collapse;width:100%;font-size:13.5px}
th,td{padding:5px 8px;border-bottom:1px solid var(--rule);text-align:left;vertical-align:top}
th{font-weight:600;color:var(--faint);font-size:12px;text-transform:uppercase;letter-spacing:.04em}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
tr.group td{background:var(--card);font-weight:600;border-bottom:none;padding-top:9px}
.cell{white-space:nowrap;font-variant-numeric:tabular-nums}
.cell a{text-decoration:none;color:inherit}
.g{font-size:13px;margin-right:4px}
.c-ok .g{color:var(--ok)}.c-kit .g{color:var(--accent)}.c-content .g{color:var(--content)}
.c-fail .g,.c-timeout .g{color:var(--fail)}
.c-kit{background:color-mix(in srgb,var(--accent) 10%,transparent)}
.badge{display:inline-block;font-size:11px;padding:0 5px;border-radius:9px;margin-left:3px;
background:var(--card);color:var(--faint)}
.badge.err{color:var(--content)}.badge.chg{color:var(--changed)}.badge.of{color:var(--faint)}
.legend{display:flex;flex-wrap:wrap;gap:14px;color:var(--faint);font-size:12.5px;margin:6px 0 10px}
details.doc{border-bottom:1px solid var(--rule);padding:6px 0}
details.doc>summary{cursor:pointer;font-weight:600;padding:4px 0}
details.doc>summary .cell{font-weight:400;margin-left:8px}
.fmt{margin:10px 0 16px 0;padding-left:12px;border-left:3px solid var(--rule)}
.fmt.c-kit{border-left-color:var(--accent);background:none}
.why{color:var(--faint)}
.kv{display:flex;flex-wrap:wrap;gap:4px 14px;font-size:12.5px;color:var(--faint);margin:4px 0}
.kv b{color:var(--ink);font-weight:600}
.thumbs{display:flex;gap:6px;overflow-x:auto;padding:4px 0 8px}
.thumbs figure{margin:0;flex:none;text-align:center}
.thumbs img{height:150px;border:1px solid var(--rule);background:#fff;display:block}
.thumbs figure.changed img{outline:2px solid var(--changed);outline-offset:1px}
.thumbs figcaption{font-size:11px;color:var(--faint)}
.rowlabel{font-size:11.5px;color:var(--faint);margin-top:6px}
ul.lines{margin:4px 0;padding-left:18px;font-family:var(--mono);font-size:12px;color:var(--faint)}
ul.lines li{word-break:break-word}
svg.spark{display:block}
.spark-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;margin:10px 0 4px}
.spark-grid .card{padding:8px 10px}
.toggle{float:right;font-size:12px;background:none;border:1px solid var(--rule);color:var(--faint);
border-radius:6px;padding:3px 8px;cursor:pointer}
@media (max-width:600px){h1{font-size:25px}.thumbs img{height:110px}}
"""

THEME_JS = """<script>
(function(){try{var t=localStorage.getItem('lab-theme');if(t)document.documentElement.dataset.theme=t}catch(e){}})();
function flipTheme(){var d=document.documentElement,dark=d.dataset.theme?d.dataset.theme==='dark':
matchMedia('(prefers-color-scheme: dark)').matches;d.dataset.theme=dark?'light':'dark';
try{localStorage.setItem('lab-theme',d.dataset.theme)}catch(e){}}
</script>"""


def esc(s) -> str:
    return html.escape(str(s if s is not None else ""))


def page(title: str, body: str) -> str:
    return (f"<!doctype html><html lang=en><head><meta charset=utf-8>"
            f"<meta name=viewport content='width=device-width,initial-scale=1'><title>{esc(title)}</title>"
            f"<style>{CSS}</style>{THEME_JS}</head><body><main>"
            f"<button class=toggle onclick='flipTheme()'>light / dark</button>{body}</main></body></html>")


def fmt_sort(f: str) -> int:
    return FORMAT_ORDER.index(f) if f in FORMAT_ORDER else len(FORMAT_ORDER)


def doc_anchor(project: str, doc: str) -> str:
    return "d-" + "".join(c if c.isalnum() else "-" for c in f"{project}-{doc}")


def badges(r: dict) -> str:
    m = r.get("metrics", {})
    out = []
    if m.get("cell_errors"):
        out.append(f"<span class='badge err' title='cell errors'>{m['cell_errors']} err</span>")
    if m.get("overfull"):
        out.append(f"<span class='badge of' title='overfull hboxes'>{m['overfull']} of</span>")
    if r.get("changed_pages"):
        out.append(f"<span class='badge chg' title='pages changed since the previous run'>"
                   f"{len(r['changed_pages'])} chg</span>")
    if r.get("page_delta"):
        out.append(f"<span class='badge chg' title='page count change'>{r['page_delta']:+d} pp</span>")
    return "".join(out)


def cell(r: dict | None, href: str = "") -> str:
    if not r:
        return "<td></td>"
    c = r.get("class", "fail")
    tip = esc(f"{CLASS_TEXT.get(c, c)}. {r.get('why', '')}")
    inner = f"<span class=g>{GLYPH.get(c, '?')}</span>{r.get('seconds', '')}s{badges(r)}"
    if href:
        inner = f"<a href='{href}'>{inner}</a>"
    return f"<td class='cell c-{c}' title='{tip}'>{inner}</td>"


def grid(results: list[dict], prefix: str = "") -> str:
    projects = {}
    for r in results:
        projects.setdefault(r["project"], {}).setdefault(r["doc"], {})[r["fmt"]] = r
    out = []
    for project in sorted(projects, key=lambda p: (p.startswith("master"), p)):
        docs = projects[project]
        fmts = sorted({f for d in docs.values() for f in d}, key=fmt_sort)
        out.append(f"<h3>{esc(project)}</h3><div class=scroll><table><tr><th>document</th>"
                   + "".join(f"<th>{esc(f)}</th>" for f in fmts) + "</tr>")
        for doc in sorted(docs):
            href = f"{prefix}#{doc_anchor(project, doc)}"
            out.append(f"<tr><td class=mono><a href='{href}'>{esc(doc)}</a></td>"
                       + "".join(cell(docs[doc].get(f), href) for f in fmts) + "</tr>")
        out.append("</table></div>")
    legend = ("<div class=legend><span><span class='g' style='color:var(--ok)'>●</span>ok</span>"
              "<span><span class='g' style='color:var(--accent)'>▲</span>kit problem</span>"
              "<span><span class='g' style='color:var(--content)'>■</span>content problem (fails without the kit too)</span>"
              "<span>✕ failed · ⧗ timeout</span><span>err = cell errors · of = overfull boxes · "
              "chg = pages changed since the previous run</span></div>")
    return legend + "".join(out)


def links(r: dict) -> str:
    base = r.get("out", "")
    items = [("log", f"{base}/render.log")] if r.get("project") != "unit" else [("log", f"{base}/test.log")]
    for k in ("pdf", "html", "epub"):
        if r.get("outputs", {}).get(k):
            items.append((k, f"{base}/{r['outputs'][k]}"))
    for f in r.get("files", []):
        if f.endswith(".tex") or f.endswith(".md"):
            items.append((f.rsplit(".", 1)[-1] if f.endswith(".tex") else "md", f"{base}/files/{f}"))
    seen, out = set(), []
    for k, h in items:
        if k not in seen:
            seen.add(k)
            out.append(f"<a href='{esc(h)}'>{k}</a>")
    return " · ".join(out)


def thumbs_row(paths: list[str], prefix: str, changed=()) -> str:
    figs = []
    for i, p in enumerate(paths, 1):
        cls = " class=changed" if i in changed else ""
        figs.append(f"<figure{cls}><a href='{esc(prefix + p)}'><img loading=lazy src='{esc(prefix + p)}' "
                    f"alt='page {i}'></a><figcaption>{i}</figcaption></figure>")
    return "<div class=thumbs>" + "".join(figs) + "</div>"


def details(results: list[dict], prev: dict, prev_id: str | None) -> str:
    projects = {}
    for r in results:
        projects.setdefault(r["project"], {}).setdefault(r["doc"], {})[r["fmt"]] = r
    out = []
    for project in sorted(projects, key=lambda p: (p.startswith("master"), p)):
        out.append(f"<h2>{esc(project)}</h2>")
        for doc, fmts in sorted(projects[project].items()):
            worst = min(fmts.values(), key=lambda r: ["kit", "fail", "timeout", "content", "ok"].index(r.get("class", "fail")))
            summary_cells = "".join(
                f"<span class='cell c-{r.get('class')}'><span class=g>{GLYPH.get(r.get('class'), '?')}</span>"
                f"{esc(f)}</span>" for f, r in sorted(fmts.items(), key=lambda kv: fmt_sort(kv[0])))
            open_ = " open" if worst.get("class") in ("kit", "fail", "timeout") else ""
            out.append(f"<details class=doc id='{doc_anchor(project, doc)}'{open_}><summary>"
                       f"<span class=mono>{esc(doc)}</span>{summary_cells}</summary>")
            for f, r in sorted(fmts.items(), key=lambda kv: fmt_sort(kv[0])):
                m = r.get("metrics", {})
                kv = [("status", r.get("status")), ("time", f"{r.get('seconds')}s"), ("pages", m.get("pages")),
                      ("cell errors", m.get("cell_errors")), ("stderr blocks", m.get("cell_stderr")),
                      ("quarto warnings", m.get("quarto_warnings")), ("overfull", m.get("overfull")),
                      ("missing chars", m.get("missing_chars")), ("undefined refs", m.get("undefined_refs"))]
                kv += [(k, v) for k, v in (m.get("census") or {}).items()]
                kvs = "".join(f"<span>{esc(k)} <b>{esc(v)}</b></span>" for k, v in kv if v not in (None, ""))
                out.append(f"<div class='fmt c-{r.get('class')}'><h3>{esc(f)} "
                           f"<span class=g>{GLYPH.get(r.get('class'), '?')}</span></h3>"
                           f"<div class=why>{esc(CLASS_TEXT.get(r.get('class'), ''))}"
                           f"{(' — ' + esc(r['why'])) if r.get('why') else ''}</div>"
                           f"<div class=kv>{kvs}</div><div>{links(r)}</div>")
                if r.get("errors"):
                    out.append("<ul class=lines>" + "".join(f"<li>{esc(e)}</li>" for e in r["errors"][:12]) + "</ul>")
                if r.get("warnings"):
                    out.append("<ul class=lines>" + "".join(f"<li>{esc(w)}</li>" for w in r["warnings"][:12]) + "</ul>")
                if r.get("thumbs"):
                    out.append("<div class=rowlabel>this run" + (
                        f" — changed pages outlined: {', '.join(map(str, r['changed_pages']))}"
                        if r.get("changed_pages") else "") + "</div>")
                    out.append(thumbs_row(r["thumbs"], "", r.get("changed_pages") or ()))
                    old = prev.get((r["project"], r["fmt"], r["doc"]))
                    if old and old.get("thumbs") and prev_id:
                        out.append(f"<div class=rowlabel>previous run {esc(prev_id)}</div>")
                        out.append(thumbs_row(old["thumbs"], f"../{prev_id}/", r.get("changed_pages") or ()))
                out.append("</div>")
            out.append("</details>")
    return "".join(out)


def cards(s: dict) -> str:
    items = [("renders", s.get("renders"), ""), ("ok", s.get("ok"), ""), ("kit problems", s.get("kit"), "kit"),
             ("content problems", s.get("content"), ""), ("other failures", s.get("fail", 0) + s.get("timeout", 0), ""),
             ("with changed pages", s.get("changed"), ""), ("overfull boxes", s.get("overfull"), ""),
             ("cell errors", s.get("cell_errors"), "")]
    return "<div class=cards>" + "".join(
        f"<div class='card {c}'><b>{esc(v)}</b><span>{esc(k)}</span></div>" for k, v, c in items) + "</div>"


def run_page(work: Path, data: dict) -> str:
    prev_id = data.get("previous")
    prev = {}
    if prev_id and (work / "runs" / prev_id / "results.json").exists():
        old = json.loads((work / "runs" / prev_id / "results.json").read_text())["results"]
        prev = {(r["project"], r["fmt"], r["doc"]): r for r in old}
    kit = data["kit"]
    head = (f"<h1>Run {esc(data['id'])}</h1><p class=sub>set <b>{esc(data['set'])}</b>"
            f"{' · only ' + esc(data['only']) if data.get('only') else ''} · kit <code>{esc(kit['sha'])}</code>"
            f"{' + uncommitted changes (' + esc(kit.get('diffstat')) + ')' if kit.get('dirty') else ''}"
            f" — {esc(kit['subject'])} · {esc(data['time'])} · {data['seconds']}s"
            f"{' · compared with ' + esc(prev_id) if prev_id else ''} · <a href='../../index.html'>all runs</a></p>")
    notes = "".join(f"<p class=why>! {esc(n)}</p>" for n in data.get("notes", []))
    return page(f"Lab run {data['id']}", head + notes + cards(data["summary"]) + grid(data["results"])
                + details(data["results"], prev, prev_id))


def spark(values: list, label: str, color: str = "var(--ink)") -> str:
    vals = [v if isinstance(v, (int, float)) else 0 for v in values]
    w, h, pad = 200, 34, 3
    last = vals[-1] if vals else 0
    if len(vals) < 2:
        pts, dots = "", ""
    else:
        lo, hi = min(vals), max(vals)
        span = (hi - lo) or 1
        xs = [pad + i * (w - 2 * pad) / (len(vals) - 1) for i in range(len(vals))]
        ys = [h - pad - (v - lo) * (h - 2 * pad) / span for v in vals]
        pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in zip(xs, ys))
        dots = f"<circle cx='{xs[-1]:.1f}' cy='{ys[-1]:.1f}' r='2.6' fill='{color}'/>"
    line = f"<polyline points='{pts}' fill='none' stroke='{color}' stroke-width='1.5'/>" if pts else ""
    return (f"<div class=card><span>{esc(label)}</span><b style='font-size:20px'>{esc(last)}</b>"
            f"<svg class=spark viewBox='0 0 {w} {h}' width='100%' height='{h}' role=img "
            f"aria-label='{esc(label)} over runs'>{line}{dots}</svg></div>")


def index_page(work: Path, history: list[dict]) -> str:
    if not history:
        return page("doc-kit lab", "<h1>doc-kit lab</h1><p class=sub>No runs yet: <code>tests/run</code></p>")
    latest = history[-1]
    chron = history[-30:]
    sparks = "<div class=spark-grid>" + "".join([
        spark([h["summary"].get("ok") for h in chron], "ok renders", "var(--ok)"),
        spark([h["summary"].get("kit") for h in chron], "kit problems", "var(--accent)"),
        spark([h["summary"].get("content") for h in chron], "content problems", "var(--content)"),
        spark([h["summary"].get("overfull") for h in chron], "overfull boxes"),
        spark([h["summary"].get("cell_errors") for h in chron], "cell errors"),
        spark([h.get("seconds") for h in chron], "wall time (s)"),
    ]) + "</div><p class=sub>last 30 runs, oldest to newest (all sets mixed; the table says which)</p>"
    rows = []
    for h in reversed(history):
        s, k = h["summary"], h["kit"]
        rows.append(f"<tr><td class=mono><a href='runs/{esc(h['id'])}/index.html'>{esc(h['id'])}</a></td>"
                    f"<td>{esc(h['set'])}{(' · ' + esc(h['only'])) if h.get('only') else ''}</td>"
                    f"<td><code>{esc(k['sha'])}</code>{'+' if k.get('dirty') else ''} {esc(k['subject'][:60])}</td>"
                    + "".join(f"<td class=num>{esc(s.get(x, 0))}</td>" for x in
                              ("renders", "ok", "kit", "content", "changed", "overfull", "cell_errors"))
                    + f"<td class=num>{esc(h.get('seconds'))}s</td></tr>")
    table = ("<div class=scroll><table><tr><th>run</th><th>set</th><th>kit</th><th class=num>renders</th>"
             "<th class=num>ok</th><th class=num>kit</th><th class=num>content</th><th class=num>changed</th>"
             "<th class=num>overfull</th><th class=num>cell err</th><th class=num>time</th></tr>"
             + "".join(rows) + "</table></div>")
    latest_data = json.loads((work / "runs" / latest["id"] / "results.json").read_text())
    body = (f"<h1>doc-kit lab</h1><p class=sub>{len(history)} runs · latest "
            f"<a href='runs/{esc(latest['id'])}/index.html'>{esc(latest['id'])}</a> "
            f"({esc(latest['set'])}) · <code>tests/run --set quick|corpus|master|all</code></p>"
            + cards(latest["summary"]) + "<h2>Over time</h2>" + sparks + table
            + f"<h2>Latest run</h2>" + grid(latest_data["results"], prefix=f"runs/{latest['id']}/index.html"))
    return page("doc-kit lab", body)


def write_all(work: Path) -> None:
    hist_file = work / "history.jsonl"
    history = [json.loads(x) for x in hist_file.read_text().splitlines() if x.strip()] if hist_file.exists() else []
    history = [h for h in history if (work / "runs" / h["id"] / "results.json").exists()]
    for h in history:
        data = json.loads((work / "runs" / h["id"] / "results.json").read_text())
        (work / "runs" / h["id"] / "index.html").write_text(run_page(work, data))
    (work / "index.html").write_text(index_page(work, history))
