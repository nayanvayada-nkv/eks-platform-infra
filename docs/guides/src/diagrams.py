"""SVG diagrams for the guides. Three primitives:
  flow(steps)        numbered steps, left to right, wrapping into rows (a "pipeline")
  layers(bands)      stacked horizontal bands (e.g. security layers)
  boxes(items, arrows, w, h)  free layout for architecture pictures
Each diagram in DIAGRAMS returns (svg, caption)."""

from html import escape

C = {  # fill, stroke, text
    "navy": ("#e8eef8", "#1f3a68", "#1f3a68"), "green": ("#eef8f2", "#1f7a4d", "#1f5e3d"),
    "amber": ("#fff6e8", "#a35b00", "#7a4400"), "blue": ("#eef4fc", "#2457a6", "#1d4585"),
    "purple": ("#f5f0fc", "#6a3fb0", "#53308c"), "red": ("#fdeeee", "#b3261e", "#8c1d17"),
    "grey": ("#f4f6f9", "#5b6573", "#1b2430"),
}
FONT = 'font-family="Segoe UI, Arial, sans-serif"'
DEFS = ('<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#1b2430"/></marker></defs>')


def _wrap(text, max_chars):
    words, lines, cur = text.split(), [], ""
    for w in words:
        if len(cur) + len(w) + 1 > max_chars and cur:
            lines.append(cur)
            cur = w
        else:
            cur = f"{cur} {w}".strip()
    return lines + ([cur] if cur else [])


def _box(x, y, w, h, title, sub="", color="grey", num=None):
    fill, stroke, ink = C[color]
    out = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="{stroke}" stroke-width="1.4"/>']
    tl = _wrap(title, max(8, int(w / 7.2)))
    sl = _wrap(sub, max(10, int(w / 5.6))) if sub else []
    total = len(tl) * 14 + len(sl) * 12
    ty = y + (h - total) / 2 + 11
    for line in tl:
        out.append(f'<text x="{x + w / 2}" y="{ty}" font-size="11.5" font-weight="700" text-anchor="middle" fill="{ink}">{escape(line)}</text>')
        ty += 14
    for line in sl:
        out.append(f'<text x="{x + w / 2}" y="{ty}" font-size="9.6" text-anchor="middle" fill="#5b6573">{escape(line)}</text>')
        ty += 12
    if num is not None:
        out.append(f'<circle cx="{x + 2}" cy="{y + 2}" r="10" fill="{stroke}"/><text x="{x + 2}" y="{y + 6}" font-size="10" font-weight="700" text-anchor="middle" fill="#fff">{num}</text>')
    return "".join(out)


def _arrow(x1, y1, x2, y2, label=""):
    out = f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="#1b2430" stroke-width="1.4" marker-end="url(#a)"/>'
    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        out += f'<text x="{mx}" y="{my - 4}" font-size="9" text-anchor="middle" fill="#5b6573">{escape(label)}</text>'
    return out


def flow(steps, cols=4, box_h=70):
    W, gap, pad = 760, 26, 14
    bw = (W - 2 * pad - gap * (cols - 1)) / cols
    rows = (len(steps) + cols - 1) // cols
    H = pad * 2 + rows * box_h + (rows - 1) * 34
    parts = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" {FONT}>', DEFS]
    pos = []
    for i, step in enumerate(steps):
        r, c = divmod(i, cols)
        x, y = pad + c * (bw + gap), pad + r * (box_h + 34)
        pos.append((x, y))
        title, sub, color = (list(step) + ["", "grey"])[:3]
        parts.append(_box(x, y, bw, box_h, title, sub, color or "grey", num=i + 1))
    for i in range(len(steps) - 1):
        (x1, y1), (x2, y2) = pos[i], pos[i + 1]
        if y1 == y2:
            parts.append(_arrow(x1 + bw, y1 + box_h / 2, x2, y2 + box_h / 2))
        else:  # wrap: down from this box, then to the start of the next row
            parts.append(f'<path d="M{x1 + bw / 2},{y1 + box_h} V{y1 + box_h + 17} H{x2 + bw / 2} V{y2 - 2}" fill="none" stroke="#1b2430" stroke-width="1.4" marker-end="url(#a)"/>')
    parts.append("</svg>")
    return "".join(parts)


def layers(bands, label_w=190):
    W, bh, gap, pad = 760, 40, 6, 10
    H = pad * 2 + len(bands) * (bh + gap) - gap
    parts = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" {FONT}>']
    for i, (name, detail, color) in enumerate(bands):
        fill, stroke, ink = C[color]
        y = pad + i * (bh + gap)
        parts.append(f'<rect x="{pad}" y="{y}" width="{W - 2 * pad}" height="{bh}" rx="7" fill="{fill}" stroke="{stroke}" stroke-width="1.4"/>')
        parts.append(f'<rect x="{pad}" y="{y}" width="{label_w}" height="{bh}" rx="7" fill="{stroke}"/>')
        parts.append(f'<text x="{pad + label_w / 2}" y="{y + bh / 2 + 4}" font-size="11.5" font-weight="700" text-anchor="middle" fill="#fff">{escape(name)}</text>')
        dl = _wrap(detail, 92)
        ty = y + bh / 2 + 4 - (len(dl) - 1) * 6
        for line in dl:
            parts.append(f'<text x="{pad + label_w + 12}" y="{ty}" font-size="10" fill="{ink}">{escape(line)}</text>')
            ty += 12
    parts.append("</svg>")
    return "".join(parts)


def boxes(items, arrows, w=760, h=420, groups=()):
    """items: {id: (x, y, w, h, title, sub, color)}; arrows: [(from, to, label, side)];
    groups: [(x, y, w, h, label, color)] drawn behind the boxes."""
    parts = [f'<svg viewBox="0 0 {w} {h}" xmlns="http://www.w3.org/2000/svg" {FONT}>', DEFS]
    for gx, gy, gw, gh, label, color in groups:
        fill, stroke, ink = C[color]
        parts.append(f'<rect x="{gx}" y="{gy}" width="{gw}" height="{gh}" rx="12" fill="none" stroke="{stroke}" stroke-width="1.6" stroke-dasharray="6 4"/>')
        parts.append(f'<text x="{gx + 10}" y="{gy + 15}" font-size="10.5" font-weight="700" fill="{ink}">{escape(label)}</text>')
    for x, y, bw, bh, title, sub, color in items.values():
        parts.append(_box(x, y, bw, bh, title, sub, color))
    for a in arrows:
        src, dst, label = a[0], a[1], a[2] if len(a) > 2 else ""
        x1, y1, w1, h1 = items[src][:4]
        x2, y2, w2, h2 = items[dst][:4]
        cx1, cy1, cx2, cy2 = x1 + w1 / 2, y1 + h1 / 2, x2 + w2 / 2, y2 + h2 / 2
        if abs(cx2 - cx1) > abs(cy2 - cy1):  # mostly horizontal
            sx = x1 + w1 if cx2 > cx1 else x1
            ex = x2 if cx2 > cx1 else x2 + w2
            parts.append(_arrow(sx, cy1, ex, cy2, label))
        else:
            sy = y1 + h1 if cy2 > cy1 else y1
            ey = y2 if cy2 > cy1 else y2 + h2
            parts.append(_arrow(cx1, sy, cx2, ey, label))
    parts.append("</svg>")
    return "".join(parts)


DIAGRAMS = {}


def diagram(fn):
    DIAGRAMS[fn.__name__] = fn
    return fn


def render(name):
    svg, caption = DIAGRAMS[name]()
    return f'<div class="diagram">{svg}<div class="cap">{escape(caption)}</div></div>'


from diagram_specs import *  # noqa: E402,F401,F403  (registers all diagrams)
