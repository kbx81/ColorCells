# /// script
# requires-python = ">=3.10"
# dependencies = ["z80"]
# ///
"""Draw every glyph of the patched firmware's font as an HTML page:

    uv run tools/cc784_font.py                  # writes cc784_font.html
    uv run tools/cc784_font.py -o /tmp/f.html --cc710

The font is read from the ROM the source assembles to (FONT_BLOCK, FONT_WIDTH),
so the page shows what the sign draws. Each glyph is labeled with its index and
the character codes that draw it: 20-7F as themselves, the Euro layer C0-CF,
E0-EF, 94-9F and DB-DF, the built-in graphics A0-AF (glyphs 0-15), and 17. The
glyphs of 90-93 (background colors) and D0-DA (store markers) are never drawn.
Bit 0 of a column is the top row."""
import sys, argparse, pathlib, html, tempfile
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

def glyphs(rom, syms):
    fb, fw = syms['FONT_BLOCK'], syms['FONT_WIDTH']
    out = []
    for i in range(191):
        a = rom[fb + 2 * (i // 8)] | rom[fb + 2 * (i // 8) + 1] << 8
        a += sum(rom[fw + j] for j in range(i // 8 * 8, i))
        out.append(bytes(rom[a:a + rom[fw + i]]))
    return out

def codes_for(i):
    """the character codes that draw glyph i, as char_to_glyph maps them"""
    c = []
    if i < 16: c.append(0xA0 + i)
    if i == 0x17 or 0x20 <= i <= 0x7F: c.append(i)
    for base, hi in ((128, 0xC0), (144, 0xE0), (160, 0x90), (175, 0xD0)):
        if base <= i < base + 16: c.append(hi + i - base)
    return [x for x in c if not (0x90 <= x <= 0x93 or 0xD0 <= x <= 0xDA)]   # backgrounds and markers

def svg(cols, dot=9):
    w = max(len(cols), 1)
    out = ['<svg viewBox="0 0 %d %d" width="%d" height="%d">' % (w * dot, 7 * dot, w * dot, 7 * dot)]
    for x, c in enumerate(cols):
        for y in range(7):
            out.append('<circle cx="%.1f" cy="%.1f" r="%.1f" class="%s"/>'
                       % (x * dot + dot / 2, y * dot + dot / 2, dot * 0.4, 'on' if c >> y & 1 else 'off'))
    return ''.join(out) + '</svg>'

SECTIONS = [
    ('Text, 20–7F', lambda i: 0x20 <= i <= 0x7F),
    ('Euro layer: C0–CF, E0–EF, 94–9F, DB–DF (90–93 are backgrounds and D0–DA store markers: faded)', lambda i: i >= 128),
    ('Built-in graphics: A0–AF (the sign draws them at double width)', lambda i: i < 16),
    ('Code 17, and the slots 10–1F no code reaches', lambda i: 16 <= i < 32),
]

def page(gl, title):
    parts = []
    for name, want in SECTIONS:
        cells = []
        for i, g in enumerate(gl):
            if not want(i): continue
            cs = codes_for(i)
            label = ' '.join('%02X' % c for c in cs) or '—'
            ch = next((chr(c) for c in cs if 0x21 <= c <= 0x7E), '')
            cells.append('<div class="cell%s"><div class="led">%s</div><div class="code">%s</div>'
                         '<div class="meta">%s<span>#%d · %d col</span></div></div>'
                         % ('' if cs else ' dead', svg(g), label, html.escape(ch) and '<b>%s</b> ' % html.escape(ch), i, len(g)))
        parts.append('<h2>%s</h2><div class="grid">%s</div>' % (name, ''.join(cells)))
    return """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>%s</title><style>
:root{--bg:#f4f4f2;--fg:#1d1d1f;--muted:#6e6e73;--card:#fff;--line:#e2e2e0;--panel:#111;--on:#ffc400;--off:#2a2a2a}
@media (prefers-color-scheme:dark){:root{--bg:#161617;--fg:#f2f2f2;--muted:#9a9a9f;--card:#202022;--line:#333336;--panel:#0b0b0b;--off:#232323}}
body{margin:0;padding:24px 16px;background:var(--bg);color:var(--fg);font:14px/1.4 -apple-system,system-ui,sans-serif}
h1{font-size:22px;margin:0 0 4px}p{color:var(--muted);margin:0 0 20px;max-width:70ch}
h2{font-size:15px;margin:28px 0 10px;color:var(--muted);font-weight:600}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(96px,1fr));gap:8px}
.cell{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px;text-align:center}
.cell.dead{opacity:.45}
.led{background:var(--panel);border-radius:4px;padding:8px 4px;display:flex;justify-content:center;min-height:63px;align-items:center}
.on{fill:var(--on)}.off{fill:var(--off)}
.code{font:600 13px ui-monospace,Menlo,monospace;margin-top:6px}
.meta{color:var(--muted);font-size:11px}.meta b{color:var(--fg);font-size:13px}
</style></head><body><h1>%s</h1>
<p>Every glyph in the font, read from the assembled ROM. The top line under each glyph is the character code (hex) that draws it, then the character for plain text, the glyph's index and its width in columns. Faded cells are glyphs no code reaches.</p>
%s</body></html>""" % (title, title, ''.join(parts))

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-o', '--out', default='cc784_font.html')
    ap.add_argument('--cc710', action='store_true', help='the CC710 build (the font is the same unless the source says otherwise)')
    a = ap.parse_args()
    import cc784_sim as S
    src = S.HERE.parent / 'src' / 'patched'
    with tempfile.TemporaryDirectory() as tmp:
        text = (src / 'cc784nir.asm').read_text()
        (pathlib.Path(tmp) / 'cc784nir.asm').write_text(('        DEFINE CC710\n' if a.cc710 else '') + text)
        rom, syms = S.assemble(tmp)
    pathlib.Path(a.out).write_text(page(glyphs(rom, syms), 'CC710 font' if a.cc710 else 'CC784 font'))
    print('wrote', a.out)

if __name__ == '__main__':
    main()
