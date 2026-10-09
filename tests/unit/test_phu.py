"""python/phu.py: what each type becomes, and what never changes kind."""
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from IPython.core.interactiveshell import InteractiveShell

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
import phu  # noqa: E402


@pytest.fixture(scope="module")
def shell():
    ip = InteractiveShell.instance()
    phu.register_display(ip)
    return ip


def mimes(shell, obj):
    data, _ = shell.display_formatter.format(obj)
    return data


# --- which documents use the look -------------------------------------------
def info(tmp_path, metadata):
    path = tmp_path / "info.json"
    path.write_text(json.dumps({"document-path": "x.qmd", "format": {"metadata": metadata}}))
    return str(path)


def test_look_on(tmp_path):
    assert phu.wants_look(info(tmp_path, {"phu-look": True}))


@pytest.mark.parametrize("metadata", [{}, {"phu-look": False}, {"phu-look": "true"}])
def test_look_off(tmp_path, metadata):
    assert not phu.wants_look(info(tmp_path, metadata))


def test_look_without_quarto(tmp_path, monkeypatch):
    monkeypatch.delenv("QUARTO_EXECUTE_INFO", raising=False)
    assert not phu.wants_look()
    bad = tmp_path / "bad.json"
    bad.write_text("{not json")
    assert not phu.wants_look(str(bad))


# --- display by type ------------------------------------------------------------
def test_matrix(shell):
    md = mimes(shell, np.array([[1, 2, 3], [4, 5, 6]]))["text/markdown"]
    assert md == ("::: {.phu-array}\n$$\n\\begin{bmatrix}\n"
                  "\\texttt{1} & \\texttt{2} & \\texttt{3} \\\\\n"
                  "\\texttt{4} & \\texttt{5} & \\texttt{6}\n"
                  "\\end{bmatrix}\n$$\n\n[int64 \u00b7 2 \u00d7 3]{.phu-shape}\n:::\n")


def test_matrix_negatives_by_value():
    md = phu.array_markdown(np.array([[-1.5, 0.0], [np.nan, -0.0]]))
    assert md.count("\\phuneg") == 1          # -0.0 and nan are not negative
    assert "\\phuneg{\\texttt{-1.5}}" in md


def test_matrix_bool():
    assert "\\texttt{True}" in phu.array_markdown(np.eye(2, dtype=bool))


def test_matrix_large_keeps_head_and_tail():
    md = phu.array_markdown(np.arange(10_000).reshape(100, 100))
    rows = md.split("\\begin{bmatrix}\n")[1].split("\n\\end{bmatrix}")[0].split(" \\\\\n")
    assert len(rows) == phu.ARRAY_HEAD + 1 + phu.ARRAY_TAIL
    assert rows[phu.ARRAY_HEAD].split(" & ")[phu.ARRAY_HEAD] == "\\ddots"
    assert "\\texttt{9999}" in rows[-1]
    assert "int64 \u00b7 100 \u00d7 100" in md


@pytest.mark.parametrize("a", [
    np.arange(4),                          # 1-D: numpy's own text
    np.arange(8).reshape(2, 2, 2),         # 3-D
    np.array([[1 + 2j]]),                  # complex
    np.array([["a", "b"]]),                # strings
    np.zeros((0, 3)),                      # empty
])
def test_other_arrays_keep_numpy_text(shell, a):
    data = mimes(shell, a)
    assert "text/markdown" not in data and "text/plain" in data


def test_dataframe_is_pandas_own_html(shell):
    df = pd.DataFrame({"a": [1, 2]})
    assert mimes(shell, df)["text/html"] == df._repr_html_()


def test_series_table_escapes():
    html = phu.series_html(pd.Series([1.5, -2.0], index=["$a$", "<d>"], name="weird & name"))
    assert "<th>weird &amp; name</th>" in html
    assert "&lt;d&gt;" in html and "<th>$a$</th>" in html


def test_series_long_uses_pandas_options(shell):
    with pd.option_context("display.max_rows", 14, "display.min_rows", 10):
        html = mimes(shell, pd.Series(range(50), name="n"))["text/html"]
    assert "50 rows \u00d7 1 columns" in html


@pytest.mark.parametrize("text", [
    "[[1 2]\n [3 4]]", "   a  b\n0  1  2\n1  3  4", "[1] 1 2 3", "$x$ <b>x</b>",
])
def test_strings_stay_strings(shell, text):
    assert set(mimes(shell, text)) == {"text/plain"}


def test_containers_stay_text(shell):
    assert set(mimes(shell, (np.eye(2), pd.Series([1])))) == {"text/plain"}
    assert set(mimes(shell, [np.eye(2)])) == {"text/plain"}


def test_formatter_error_falls_back(monkeypatch):
    def boom(_):
        raise RuntimeError("no")
    assert phu._guard(boom)(1) is None


def test_pandas_options():
    phu._pandas_options(pd)
    for key, value in phu.PANDAS_OPTIONS.items():
        assert pd.get_option(key) == value
