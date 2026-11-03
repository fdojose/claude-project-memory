#!/usr/bin/env python3
"""How much of each active inbox entry is already written outside the memory?

For every active entry in memory/inbox.md, takes the distinctive terms of its
heading and What line (numbers with units, times, file names, snake_case and
dotted identifiers, backticked text) and looks for them in the project's files:
in a git repository the tracked and untracked files git does not ignore,
otherwise every file under the root; text files only, without memory/, .claude/,
CLAUDE.md, data/ and data-like files.

coverage = share of the terms found. Low coverage means the entry holds
measurements or names that exist only in the memory. High coverage does NOT mean
the entry is redundant: a decision's reason has no distinctive terms, so it is
invisible to this check (2026-11-03 test on one project: AUC 0.80 against LLM-graded
impact on the stable entries, with three "why" entries at coverage 0.90-1.00
missed).

Prints a tab-separated table: coverage, number of terms, type, heading, terms
not found (first six). Entries with no distinctive terms show "-".

Usage, from the project root: python3 ~/.claude/skills/memory-review/coverage.py
"""
import os
import re
import subprocess
import sys

TEXT_EXT = {".md", ".py", ".yaml", ".yml", ".sh", ".txt", ".js", ".ts", ".toml", ".conf", ".ini", ".html",
            ".css", ".service", ".sql", ".rb", ".go", ".rs", ".java", ".swift", ".kt", ".php"}
SKIP_TOP = {"memory", ".claude", "CLAUDE.md", "data", ".git", "node_modules", ".venv", "venv"}
UNIT = r"(?:%|°C|°|kWh|kWp|kW|Wh|W|V|A|Ah|h|min|s|ms|Ω|m³/s|mm|m|GB|MB|MiB|KB|Hz|CLP|USD|\$)"
TERM_RES = [
    re.compile(r"`([^`]{3,60})`"),
    re.compile(r"(?<![\w.])(\d+(?:[.,]\d+)?\s?" + UNIT + r")(?![\w])"),
    re.compile(r"(?<![\d:])(\d{1,2}:\d{2}(?::\d{2})?)(?![\d:])"),
    re.compile(r"(?<![\w.])([A-Za-z_][\w-]*(?:[._/][\w-]+)+)"),
    re.compile(r"(?<![\w.])([A-Za-z]+\d[\w-]*|\d+[A-Za-z][\w-]*)"),
]
DATE = re.compile(r"^\d{4}-\d{2}(-\d{2})?$")
COMMON = {"e.g", "i.e", "vs", "km/h", "w/m", "and/or"}


def files(root):
    r = subprocess.run(["git", "-C", root, "ls-files", "-co", "--exclude-standard", "-z"],
                       capture_output=True, text=True)
    if r.returncode == 0:
        return [f for f in r.stdout.split("\0") if f]
    out = []
    for d, dirs, fs in os.walk(root):
        rel = os.path.relpath(d, root)
        if rel != "." and rel.split(os.sep)[0] in SKIP_TOP:
            dirs[:] = []
            continue
        out += [os.path.normpath(os.path.join(rel, f)) for f in fs]
    return out


def corpus(root):
    parts = []
    for f in files(root):
        if f.split("/")[0] in SKIP_TOP or os.path.splitext(f)[1].lower() not in TEXT_EXT:
            continue
        p = os.path.join(root, f)
        if os.path.isfile(p) and os.path.getsize(p) < 3_000_000:
            parts.append(open(p, encoding="utf-8", errors="ignore").read())
    return "\n".join(parts).lower()


def entries(root):
    text = open(os.path.join(root, "memory", "inbox.md"), encoding="utf-8").read().split("\n## Misses", 1)[0]
    for block in re.split(r"\n(?=## \d{4}-\d{2}-\d{2} · )", text):
        m = re.match(r"## (\d{4}-\d{2}-\d{2}) · (\w+) · (.*)", block)
        status = re.search(r"^- Status: *(.*)$", block, re.M)
        if m and status and status.group(1).startswith("active"):
            what = re.search(r"^- What:(.*)$", block, re.M)
            yield m.group(2), block.split("\n", 1)[0], m.group(3) + " " + (what.group(1) if what else "")


def terms(src):
    out = []
    for rx in TERM_RES:
        for m in rx.findall(src):
            t = m.strip().strip(".,;:()").lower()
            if len(t) < 3 or DATE.match(t) or t in COMMON or t in out:
                continue
            out.append(t)
    return out


def found(t, text):
    pat = re.escape(t).replace(r"\ ", r"\s?").replace(",", "[.,]")
    return re.search(r"(?<![\w.])" + pat + r"(?![\w])", text) is not None


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    if not os.path.exists(os.path.join(root, "memory", "inbox.md")):
        raise SystemExit("no memory/inbox.md under " + root)
    text = corpus(root)
    rows = []
    for typ, heading, src in entries(root):
        ts = terms(src)
        miss = [t for t in ts if not found(t, text)]
        cov = (len(ts) - len(miss)) / len(ts) if ts else None
        rows.append((cov, len(ts), typ, heading, miss))
    rows.sort(key=lambda r: (r[0] if r[0] is not None else 2))
    print("coverage\tterms\ttype\theading\tnot found")
    for cov, n, typ, heading, miss in rows:
        print("%s\t%d\t%s\t%s\t%s" % ("-" if cov is None else "%.2f" % cov, n, typ, heading, ", ".join(miss[:6])))


if __name__ == "__main__":
    main()
