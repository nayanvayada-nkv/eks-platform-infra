"""Builds the in-depth guides: docs/guides/src/*.md -> docs/guides/html/*.html (then
scripts/render-guides.sh prints them to PDF with Chrome).

Markdown extras:
  [[diagram:NAME]]       inserts an SVG from diagrams.py
  <div class="story" markdown>..</div>   QuickCart real-life example (also simple, deep,
                          why, warn, bug, evidence, glossary boxes; see CSS below)
  <div class="pagebreak"></div>          forces a new page
Usage: python3 docs/guides/build.py   (needs: pip install markdown)
"""

import pathlib
import re
import sys

import markdown

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE / "src"))
import diagrams  # noqa: E402

CSS = """
@page { size: A4; margin: 11mm 12mm 12mm; }
:root { --ink:#1b2430; --muted:#5b6573; --line:#d5dbe3; --navy:#1f3a68; --green:#1f7a4d; --greenbg:#eef8f2;
  --amber:#a35b00; --amberbg:#fff6e8; --blue:#2457a6; --bluebg:#eef4fc; --purple:#6a3fb0; --purplebg:#f5f0fc;
  --red:#b3261e; --redbg:#fdeeee; --grey:#f4f6f9; }
* { box-sizing: border-box; }
body { margin:0; color:var(--ink); font:10pt/1.45 "Segoe UI", system-ui, Arial, sans-serif; }
h1 { font-size:21pt; margin:0 0 2px; color:var(--navy); letter-spacing:-0.01em; }
h2 { font-size:13.5pt; margin:16px 0 6px; color:var(--navy); border-bottom:2px solid var(--navy); padding-bottom:3px; break-after:avoid; }
h3 { font-size:11pt; margin:11px 0 4px; break-after:avoid; }
p { margin:4px 0 8px; } ul,ol { margin:4px 0 9px; padding-left:20px; } li { margin:2px 0; }
code { font-family:Consolas,"Cascadia Mono",monospace; font-size:9pt; background:var(--grey); padding:0 3px; border-radius:3px; }
pre { font-family:Consolas,"Cascadia Mono",monospace; font-size:8.8pt; background:var(--grey); border:1px solid var(--line);
  border-radius:6px; padding:8px 10px; margin:6px 0 10px; white-space:pre-wrap; break-inside:avoid; }
pre code { background:none; padding:0; }
table { width:100%; border-collapse:collapse; margin:6px 0 10px; font-size:9pt; break-inside:auto; }
th,td { border:1px solid var(--line); padding:4px 6px; text-align:left; vertical-align:top; }
th { background:var(--grey); } tr { break-inside:avoid; }
.sub { color:var(--muted); margin:0 0 10px; }
.status { display:inline-block; font-size:8.5pt; font-weight:700; padding:2px 8px; border-radius:4px; background:var(--amberbg); color:var(--amber); border:1px solid var(--amber); }
.story,.simple,.why,.warn,.bug,.evidence,.glossary,.deep { padding:7px 11px; margin:8px 0 10px; border-radius:0 7px 7px 0; break-inside:avoid; }
.story { border-left:4px solid var(--purple); background:var(--purplebg); }
.story::before { content:"Real-life example (QuickCart)"; display:block; font-weight:700; color:var(--purple); font-size:9pt; margin-bottom:2px; }
.simple { border-left:4px solid var(--blue); background:var(--bluebg); }
.simple::before { content:"In simple words"; display:block; font-weight:700; color:var(--blue); font-size:9pt; margin-bottom:2px; }
.deep { border-left:4px solid var(--navy); background:#f2f5fa; }
.deep::before { content:"Going deeper"; display:block; font-weight:700; color:var(--navy); font-size:9pt; margin-bottom:2px; }
.why { border-left:4px solid var(--green); background:var(--greenbg); }
.why::before { content:"Security reason"; display:block; font-weight:700; color:var(--green); font-size:9pt; margin-bottom:2px; }
.warn { border-left:4px solid var(--amber); background:var(--amberbg); }
.warn::before { content:"Watch out"; display:block; font-weight:700; color:var(--amber); font-size:9pt; margin-bottom:2px; }
.bug { border-left:4px solid var(--red); background:var(--redbg); }
.bug::before { content:"Real bug we caught"; display:block; font-weight:700; color:var(--red); font-size:9pt; margin-bottom:2px; }
.evidence { border:2px dashed #9aa5b4; border-radius:7px; background:#fafbfc; }
.evidence::before { content:"Evidence: fill after the AWS run"; display:block; font-weight:700; color:var(--muted); font-size:9pt; margin-bottom:2px; }
.glossary { border-left:4px solid var(--muted); background:var(--grey); }
.story p:last-child,.simple p:last-child,.why p:last-child,.warn p:last-child,.bug p:last-child,.deep p:last-child { margin-bottom:2px; }
.diagram { border:1px solid var(--line); border-radius:10px; padding:6px; margin:8px 0 10px; break-inside:avoid; }
.diagram svg { width:100%; height:auto; display:block; }
.diagram .cap { font-size:8.6pt; color:var(--muted); margin:3px 4px 0; }
.pagebreak { break-after:page; }
.cover { border-bottom:3px solid var(--navy); padding-bottom:6px; margin-bottom:8px; }
.foot { margin-top:14px; font-size:8.5pt; color:var(--muted); border-top:1px solid var(--line); padding-top:4px; }
"""

PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8"><title>{title}</title><style>{css}</style></head>
<body>{body}<div class="foot">eks-platform-infra &middot; {title} &middot; QuickCart is a fictional example app used
to explain concepts; it is not a real company or customer.</div></body></html>"""


def render(md_path: pathlib.Path) -> str:
    text = md_path.read_text()
    title = re.search(r"^# (.+)$", text, re.M).group(1)
    text = re.sub(r"\[\[diagram:([a-z0-9_]+)\]\]", lambda m: diagrams.render(m.group(1)), text)
    body = markdown.markdown(text, extensions=["tables", "fenced_code", "md_in_html", "attr_list", "sane_lists"])
    return PAGE.format(title=title, css=CSS, body=body)


def main():
    out = HERE / "html"
    out.mkdir(exist_ok=True)
    names = sys.argv[1:] or [p.stem for p in sorted((HERE / "src").glob("*.md"))]
    for name in names:
        html = render(HERE / "src" / f"{name}.md")
        (out / f"{name}.html").write_text(html)
        print(f"built html/{name}.html")


if __name__ == "__main__":
    main()
