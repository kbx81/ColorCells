# /// script
# requires-python = ">=3.10"
# dependencies = ["z80"]
# ///
"""Check a message for the sign before loading it:

    uv run tools/cc784_lint.py "@{up}HELLO@{left}"          # cc784.py's escape syntax
    uv run tools/cc784_lint.py -f tools/messages/tour.txt
    uv run tools/cc784_lint.py --hex 1a48454c4c4f18         # raw bytes
    uv run tools/cc784_lint.py --static "..."               # the rules only, no emulator
    uv run tools/cc784_lint.py --field 3=72F "IT IS @{field 3}"  # a field's value for the widths

The rules read the bytes; the page widths come from the patched firmware itself, run
in the emulator at both panel widths (86 columns, and the CC710's 60). Each finding is
'error', 'warn' or 'info'; the exit status is 1 if any error was found. Rules are the
functions in RULES: each takes the parsed message and yields findings."""
import sys, argparse, pathlib, tempfile
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import cc784

ATTR_LEFT, ATTR_THIN, ATTR_ALT, ATTR_NORM = 0x18, 0xB9, 0xB2, 0x11
WIPES = {0x1A: 'W-UP', 0x1B: 'W-DOWN', 0x0F: 'W-RIGHT', 0xBB: 'HOLD'}
SCROLLS = {0x1A: 'S-UP', 0x1B: 'S-DOWN', 0x0F: 'S-RIGHT'}          # after B2
MODIFIERS = {0x19: 'TWINKLE', 0xBB: 'GLIMMER'}                     # after B2, following an effect
SIDEWAYS = {'S-RIGHT'}                                             # pages that move horizontally: colors allowed
STATIONARY_OTHER = {0x19: 'PAUSE'}                                 # staged pages that are neither wipe nor scroll

def is_color(b): return 0x80 <= b <= 0x93
def is_bg(b): return 0x90 <= b <= 0x93
def is_text(b): return 0x20 <= b <= 0x7E or 0x94 <= b <= 0x9F or 0xC0 <= b <= 0xCF or 0xDB <= b <= 0xEF   # ASCII and the Euro glyphs

class Tok:
    def __init__(self, pos, data, kind, name):
        self.pos, self.data, self.kind, self.name = pos, data, kind, name
    def __repr__(self): return self.name

NAMES = {}
for n, v in cc784.NAMED.items():
    NAMES.setdefault(v if isinstance(v, tuple) else (v,), n.upper())

def tokenize(data):
    toks, i = [], 0
    while i < len(data):
        b = data[i]
        if b == ATTR_ALT and i + 1 < len(data):
            n = data[i + 1]
            if n in SCROLLS: toks.append(Tok(i, data[i:i + 2], 'effect', SCROLLS[n]))
            elif n in MODIFIERS: toks.append(Tok(i, data[i:i + 2], 'modifier', MODIFIERS[n]))
            elif 0x30 <= n <= 0x39: toks.append(Tok(i, data[i:i + 2], 'field', '{field %c}' % n))
            else: toks.append(Tok(i, data[i:i + 2], 'attr', NAMES.get((b, n), 'B2 %02X' % n)))
            i += 2; continue
        if b in WIPES: toks.append(Tok(i, data[i:i + 1], 'effect', WIPES[b]))
        elif b in STATIONARY_OTHER: toks.append(Tok(i, data[i:i + 1], 'effect', STATIONARY_OTHER[b]))
        elif b == ATTR_LEFT: toks.append(Tok(i, data[i:i + 1], 'left', 'LEFT'))
        elif is_color(b): toks.append(Tok(i, data[i:i + 1], 'color', NAMES.get((b,), '%02X' % b)))
        elif is_text(b): toks.append(Tok(i, data[i:i + 1], 'text', '°' if b == 0x9F else chr(b) if b < 0x7F else '<%02X>' % b))
        else: toks.append(Tok(i, data[i:i + 1], 'attr', NAMES.get((b,), '%02X' % b)))
        i += 1
    return toks

class Page:
    """an effect, its modifier and THIN if any, the tokens it stages, and what ends it"""
    def __init__(self, effect):
        self.effect, self.head, self.body, self.end = effect, [effect], [], None
    @property
    def text(self): return ''.join(t.name for t in self.body if t.kind in ('text', 'field'))

def pages(toks):
    out, cur = [], None
    for t in toks:
        if t.kind == 'effect':
            if cur: cur.end = t
            cur = Page(t); out.append(cur)
        elif cur and t.kind == 'left':
            cur.end = t; cur = None
        elif cur and not any(u.kind in ('text', 'field') for u in cur.body) and (t.kind == 'modifier' or t.name == 'THIN'):
            cur.head.append(t)                   # a color may come first: the firmware still takes it
        elif cur:
            cur.body.append(t)
    return out

def context(data, pos, width=24):
    lo = max(0, pos - width // 2)
    return cc784.printable(data[lo:pos]) + ' >>' + cc784.printable(data[pos:pos + width // 2])

# ---- the rules: each yields (severity, position, text)
def rule_trailing_space(m):
    """the firmware scrolls every channel off before the next: trailing spaces only use RAM"""
    if m.data.endswith(b' '):
        n = len(m.data) - len(m.data.rstrip(b' '))
        yield 'error', len(m.data) - n, '%d trailing space%s at the end of the message' % (n, '' if n == 1 else 's')

def rule_bg_space(m):
    """a background color is followed by a space before its text, or the background starts at the text's edge"""
    for i, t in enumerate(m.toks):
        if t.kind == 'color' and is_bg(t.data[0]):
            nxt = next((u for u in m.toks[i + 1:] if u.kind not in ('color',)), None)
            if nxt and nxt.kind == 'text' and nxt.name != ' ':
                yield 'warn', t.pos, '%s is followed by text without a space: write "<%s> <color>TEXT"' % (t.name, t.name)

def rule_stationary_color(m):
    """only horizontal motion shows color: none on wipes, S-UP, S-DOWN or PAUSE pages"""
    for p in m.pages:
        if p.effect.name in SIDEWAYS: continue
        for t in p.body:
            if t.kind == 'color':
                yield 'warn', t.pos, '%s on a %s page does nothing: stationary text is red/green striped, color needs sideways motion' % (t.name, p.effect.name)

def rule_left_terminator(m):
    """wipes and scrolls end with LEFT, which marks the right edge of the stationary text"""
    for p in m.pages:
        if p.effect.name in STATIONARY_OTHER.values(): continue
        if p.end is None:
            yield 'error', p.effect.pos, '%s page "%s" is not terminated by LEFT' % (p.effect.name, p.text)

def rule_page_trailing_space(m):
    """spaces at the end of a wipe or scroll page push it past the panel and force a left scroll"""
    for p in m.pages:
        txt = [t for t in p.body if t.kind in ('text', 'field')]
        if txt and txt[-1].name == ' ':
            n = len(txt) - len(''.join(t.name for t in txt).rstrip(' '))
            yield 'error', txt[-1].pos, '%s page "%s" ends with %d space%s' % (p.effect.name, p.text.rstrip(), n, '' if n == 1 else 's')

def rule_thin(m):
    """THIN only means something right after a wipe or scroll (NORM with spaced characters)"""
    heads = {id(t) for p in m.pages for t in p.head}
    for t in m.toks:
        if t.name == 'THIN' and id(t) not in heads:
            yield 'warn', t.pos, 'THIN away from the start of a wipe or scroll does nothing (a wasted byte)'

def rule_field(m):
    """a field (B2 '0'-'9', channel 90-99) holds text and colors only; a page holding one
    is measured with the value given by --field, or with the field empty"""
    for n, v in sorted(m.fields.items()):
        for t in tokenize(v):
            if t.kind not in ('text', 'color'):
                yield 'error', 0, 'field %d holds %s: a field is text and colors only' % (n, t.name)
    for p in m.pages:
        for t in p.body:
            if t.kind == 'field' and t.data[1] - 0x30 not in m.fields:
                yield 'warn', t.pos, '%s page "%s" holds field %d with no --field value: measured empty' % (p.effect.name, p.text, t.data[1] - 0x30)

def rule_flush(m):
    """FLUSH (B2 20) pushes the crawl's text off: spaces do the same at a byte each"""
    staged = {id(u) for p in m.pages for u in p.body}
    for i, t in enumerate(m.toks):
        if t.name != 'FLUSH': continue
        if id(t) in staged:
            yield 'warn', t.pos, 'FLUSH on a %s page does nothing: staged pages are shown whole' % next(p.effect.name for p in m.pages if t in p.body)
        if i and m.toks[i - 1].name == ' ':
            yield 'warn', m.toks[i - 1].pos, 'spaces before FLUSH are wasted'
        if i == len(m.toks) - 1:
            yield 'warn', t.pos, 'FLUSH at the end of the message: the end flushes anyway'
    run = []
    for t in m.toks + [None]:
        if t is not None and t.name == ' ' and id(t) not in staged:
            run.append(t); continue
        if len(run) >= 6:
            yield 'info', run[0].pos, '%d spaces in a row: @{flush} (2 bytes) pushes the text off' % len(run)
        run = []

def rule_redundant_default(m):
    """unattributed text is already NORM and yellow"""
    for t in m.toks:
        if t.kind == 'text': break
        if t.data[0] in (ATTR_NORM, 0x8F) and len(t.data) == 1:
            yield 'info', t.pos, '%s before the first text is the default (a wasted byte)' % t.name

RULES = [rule_trailing_space, rule_bg_space, rule_stationary_color, rule_left_terminator,
         rule_page_trailing_space, rule_thin, rule_field, rule_flush, rule_redundant_default]

# ---- page widths, measured by the firmware in the emulator
def measure(data, cc710, fields={}):
    """[(columns used, overflowed, char it stopped at)] per staged page, in order, one pass of the channel"""
    import cc784_sim as S
    src = S.HERE.parent / 'src' / 'patched'
    with tempfile.TemporaryDirectory() as tmp:
        text = (src / 'cc784nir.asm').read_text()
        (pathlib.Path(tmp) / 'cc784nir.asm').write_text(('        DEFINE CC710\n' if cc710 else '') + text)
        rom, syms = S.assemble(tmp)
    s = S.Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
    s.send_frame(bytes([0xB6, 3, 0xFF, 1]), addr=1); s.rx_wait(); s.run_ms(300)    # holds of one frame: a quick pass
    for n, v in fields.items():
        s.send_frame(b'\x09\x39%c\x0e' % (0x30 + n) + v, addr=1); s.rx_wait(); s.run_ms(300)
    col, ptr, txbuf = syms['COL_COUNT'], syms['STAGE_PTR'], syms['TXBUF']
    flush = (syms['fx_flush_stage'], syms['fx_dispatch'])
    res = []
    ow = s._on_write
    def wr(addr, value):
        if addr == col and flush[0] <= s.m.pc < flush[1]:
            used = int.from_bytes(s.ram('STAGE_PTR', 2), 'little') - txbuf
            c = s.ram('CUR_CHAR')[0]
            res.append((used, is_text(c), c))
        return ow(addr, value)
    s.m.set_write_callback(wr); s.m.mark_addrs(col, 1, s.m.WRITE_MARK)
    for i in range(0, max(len(data), 1), 250):                  # long messages as cc784.py msg splits them
        s.send_frame(b'\x09\x30\x30' + (b'\x0e' if i == 0 else b'\xb3') + data[i:i + 250], addr=1, flag=0x81)
        s.rx_wait(); s.run_ms(1500)
    want = sum(1 for t in tokenize(data) if t.kind == 'effect')
    for _ in range(1200):                      # up to 120 s of sign time
        s.run_ms(100)
        if len(res) >= want: break
    return res[:want], syms['FRAME_COLS']

class Msg:
    def __init__(self, data, fields={}):
        self.data, self.toks, self.fields = data, tokenize(data), fields
        self.pages = pages(self.toks)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('message', nargs='?')
    ap.add_argument('-f', '--file')
    ap.add_argument('--hex')
    ap.add_argument('--static', action='store_true', help='the rules only, no emulator')
    ap.add_argument('--field', action='append', default=[], metavar='N=TEXT', help="a field's value (channel 90+N), for the page widths")
    a = ap.parse_args()
    if a.hex: data = bytes.fromhex(a.hex)
    elif a.file: data = cc784.encode_text(pathlib.Path(a.file).read_text().rstrip('\n'))
    elif a.message is not None: data = cc784.encode_text(a.message)
    else: ap.error('a message, -f FILE or --hex')
    fields = {int(f.split('=', 1)[0]): cc784.encode_text(f.split('=', 1)[1]) for f in a.field}
    m = Msg(data, fields)
    found = []
    for rule in RULES:
        for sev, pos, text in rule(m):
            found.append((sev, pos, rule.__name__[5:], text))
    widths = {}
    if not a.static:
        for cc710 in (False, True):
            res, cols = measure(data, cc710, fields)
            widths[cols] = res
            for p, (used, over, c) in zip([p for p in m.pages], res):
                if over:
                    found.append(('error', p.effect.pos, 'page_width',
                                  '%s page "%s" does not fit %d columns: stopped at "%s" after %d' % (p.effect.name, p.text, cols, chr(c), used)))
    order = {'error': 0, 'warn': 1, 'info': 2}
    for sev, pos, rule, text in sorted(found, key=lambda f: (f[1], order[f[0]])):
        print('%-5s %-20s @%-4d %s\n      %s' % (sev, rule, pos, text, context(data, pos)))
    if widths:
        print('pages (columns used of 86 / 60):')
        for i, p in enumerate(m.pages):
            w = ['%3d%s' % (widths[c][i][0], '!' if widths[c][i][1] else ' ') if i < len(widths[c]) else '  ?' for c in (86, 60)]
            print('  %-8s %-13s %s  %s' % (p.effect.name, '+'.join(t.name for t in p.head[1:]), ' / '.join(w), p.text))
    errors = sum(1 for f in found if f[0] == 'error')
    print('%d error%s, %d warning%s, %d note%s' % (errors, '' if errors == 1 else 's',
          sum(1 for f in found if f[0] == 'warn'), '' if sum(1 for f in found if f[0] == 'warn') == 1 else 's',
          sum(1 for f in found if f[0] == 'info'), '' if sum(1 for f in found if f[0] == 'info') == 1 else 's'))
    sys.exit(1 if errors else 0)

if __name__ == '__main__':
    main()
