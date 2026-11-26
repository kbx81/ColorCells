# /// script
# requires-python = ">=3.10"
# dependencies = ["z80"]
# ///
"""A/B of two source trees in the emulator, for changes that must not alter behavior:

    uv run tools/cc784_ab.py DIR_A DIR_B [editor] [render] [serial] [repair]

DIR_A and DIR_B each hold a cc784nir.asm (git show REV:src/patched/cc784nir.asm > old/cc784nir.asm).
editor: remote keys, comparing the key processed and the steady frame after each, then the store,
sequence, address and clock. render: three messages by frame, timing differences filtered as the
compare gate does. serial: replies and the store after a set of commands. repair: the store after a
boot on damaged and on fresh RAM, each build on its own RAM image; stores are compared up to their DA,
so the two may differ in RAM map and store size (B4 '1' then reports different sizes). Random effects (RAINBOW's start, MAGIC, TWINKLE, GLIMMER) and the
scrolls' torn frames differ between any two builds of different speed and are left to their gates.
For the CC710 put "        DEFINE CC710" on the first line of both copies; for LITE set CC784_LITE=1
(serial, repair and render only: it has no remote)."""
import sys, difflib, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import cc784_sim as S

_orig_out = S.Sign._on_output
def _out(self, port, value):
    n = self.sym['FRAME_COLS'] + 1
    if n == 87: return _orig_out(self, port, value)
    if port & 0xff == 0x4e:               # the same capture at the CC710's row length
        self.burst.append(value)
        if len(self.burst) == n:
            f = bytes(self.burst); self.burst = []
            if not self.frames or self.frames[-1] != f: self.frames.append(f)
S.Sign._on_output = _out

def frames_diff(fa, fb):
    sm = difflib.SequenceMatcher(a=fa, b=fb, autojunk=False)
    phase = real = 0; first = None
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal': continue
        if tag == 'replace' and i2 - i1 == j2 - j1:
            for k in range(i2 - i1):
                if S._phase_artefact(fa[i1 + k], fb[j1 + k]): phase += 1
                else:
                    real += 1; first = first or (i1 + k, j1 + k)
        else:
            for k in range(i1, i2):
                if S._extra_is_phase(fa[k], fa, k): phase += 1
                else: real += 1; first = first or (k, j1)
            for k in range(j1, j2):
                if S._extra_is_phase(fb[k], fb, k): phase += 1
                else: real += 1; first = first or (i1, k)
    return phase, real, first

def store(s):
    a = s.sym['MSG_STORE']; e = int.from_bytes(s.ram('STORE_END', 2), 'little')
    return bytes(s.m.memory[a:e + 1])

EDITOR_KEYS = """STOP H I SPACE BOLD W O W FLASH COLOR 3 RIGHT LEFT DEL LARGE X Y Z SPACE NORMAL Q SPACE
 SHIFT COLOR 2 GRAPH 5 SHIFT PROG 3 A
 SHIFT STOP GRAPH F F 7 F 0 0 SPACE
 SHIFT STOP COLOR R SHIFT STOP SHIFT COLOR B SHIFT STOP Q SHIFT STOP C
 UPPER/LOWER A B UPPER/LOWER C SHIFT UPPER/LOWER A SHIFT . SHIFT (
 LEFT LEFT LEFT SHIFT LEFT RIGHT RIGHT SHIFT RIGHT LEFT DEL
 JUMP P WIPE-UP U SHIFT WIPE-UP D SHIFT BEEP R SHIFT SEQ H BEEP SHIFT GRAPH
 SHIFT STOP SHIFT WIPE-UP S SHIFT STOP SHIFT JUMP T SHIFT STOP LARGE T
 SHIFT NORMAL 1 2 3 4 @2000 Y @500
 SHIFT STOP MAGIC @500 2 5 STOP @500
 PROG 0 5 STOP @500 X Y SHIFT LARGE Z
 SEQ 0 0 STOP 0 5 STOP STOP @2500 ~STOP @900
 SHIFT CLEAR N @500
 PROG 0 7 STOP @500 K CLEAR @500 L
 PROG 0 0 STOP @500 SHIFT LEFT RIGHT RIGHT
 SHIFT STOP SHIFT STOP @1800
 ~STOP @3000""".split()

def editor(rom, syms):
    s = S.Sign(rom, syms, fresh_ram=False); s.run_ms(3000)
    s.send_frame(b'\x09\x30\x30\x0ePLAIN\x04\x30\x30'); s.rx_wait(); s.run_ms(1500)
    ek = syms['EDIT_KEY']; s.watch = {ek}; s.m.mark_addrs(ek, 1, s.m.WRITE_MARK)
    out = []
    for k in EDITOR_KEYS:
        if k.startswith('@'):
            s.run_ms(int(k[1:])); out[-1] = (out[-1][0], out[-1][1], s.frames[-1] if s.frames else None); continue
        s.watch_log.clear(); s.ir_key(k.lstrip('~'), stretch_us=100); s.ir_wait(); s.run_ms(350)
        out.append((k, ''.join('%02X' % v for t, pc, a, v in s.watch_log if v), s.frames[-1] if s.frames else None))
    clk = s.ram('CLK_H10', 4).hex() + ' pm ' + s.ram('CLK_PM').hex()
    return out, store(s), s.ram('SEQ_LIST', syms['SEQ_LIST_LEN']), s.ram('MY_ADDRESS')[0], clk, len(s.faults)

R1 = (b'\x09\x30\x30\x0e\x12BOLD \x14FLASH \x11  \x8cRED \x92\x83ON BG  \x13ITALIC \x10BIG \x11\xa3\xa7 '
      b'\xb8FF7F3E1C08 \xb8417F41\xb822 \xb8ZZ \x5f \xf3SLOW \xf0FAST \xc5\xe9\x95 \x12\x10BB\x13 MIX \x11END'
      b'\x04\x30\x30')
R2 = (b'\x09\x30\x30\x0e\x12\x14HELLO \x8c\x19PAUSE \x1aUP \x1bDOWN \x0fRIGHT \xbbHOLD \x06\x18LEFT '
      b'\xb9\x19THIN \xb0REMARK\xb0\x19\xb8FF7F3E1C08 \x13IT \x10BG\x11 \x5f '
      b'\xbeTINY TEXT LINE\x11 \x07\x04\x30\x30')
R3 = (b'\x09\x30\x30\x0e\x12\x19THIS PAGE IS FAR TOO LONG TO FIT \x1aAND THIS ONE HAS MORE WORDS THAN FIT '
      b'\xbbHOLD OVERFLOWS AS WELL HERE \x0fRIGHT TOO WIDE FOR IT \x18TAIL \x04\x30\x30')
R3_LITE = (b'\x09\x30\x0e\x12\x19THIS PAGE IS FAR TOO LONG TO FIT \x1aAND THIS ONE HAS MORE WORDS '   # R3 is over the 2 K
           b'\xbbHOLD OVERFLOWS TOO \x0fRIGHT TOO WIDE HERE \x18TAIL \x04\x30')                      # frame limit: it never loads
def render(rom, syms):
    res = []
    for name, msg, secs in (('crawl', R1, 40), ('effects', R2, 60), ('overflow', R3_LITE if S.LITE else R3, 60)):
        s = S.Sign(rom, syms, fresh_ram=False); s.run_ms(3000)
        s.send_frame(msg); s.rx_wait(); s.run_ms(1500); s.frames.clear()
        s.run_ms(secs * 1000)
        res.append((name, list(s.frames), len(s.faults)))
    return res

CMDS = [b'\x09\x30\x30\x0eONE\x15\x00A\x16\x04B\x1e\x07C\x02\x05D', b'\x09\x35TWO', b'\x09\x31\x32TWELVE',
        b'\x09\x39\x39\x0eLAST\xb3X', b'\x09\x31\x32\xb3 MORE', b'\x04\x30\x30\x31\x32\x44\x30\x35\x0d',
        b'\x17\x30\x39\x34\x35\x59', b'\xb6\x03\xff\x30', b'\xb6\x02\xff\x02', b'\x09\x31\x32\x0e', b'\x04\x39\x39\x64\x0d',
        b'\x09\x37\x78\xb8AB\x06\x07']
QUERIES = [b'\xb4\x30', b'\xb4\x31', b'\xb4\x35', b'\xb4\x36', b'\xb4\x33']
if S.LITE:      # text straight after 09 lands on the marker; with no channel 99 it is channel 9's, and the reset is the emulator's dead end
    CMDS = [c for c in CMDS if not c.startswith(b'\x09\x39\x39')]
def used(store):
    """the store up to its DA: what a build with a different store size has in common"""
    return store[:store.index(0xDA) + 1] if 0xDA in store else store
def serial(rom, syms):
    s = S.Sign(rom, syms, fresh_ram=False); s.run_ms(3000)
    out = []
    for c in CMDS:
        s.tx_edges.clear(); s.send_frame(c, flag=0x81); s.rx_wait(); s.run_ms(4000 if S.LITE else 1500)
        out.append((c.hex(), s.tx_bytes().hex()))
    for q in QUERIES:
        s.tx_edges.clear(); s.send_frame(q, flag=0x81); s.rx_wait(); s.run_ms(6000)
        out.append((q.hex(), s.tx_bytes().hex()))
    s.tx_edges.clear(); s.send_frame(b'\xb4\x34', flag=0x81); s.rx_wait(); s.run_ms(4000 if S.LITE else 1500)
    st = s.tx_bytes()
    out.append(('b434 len/head', '%d %s' % (len(st), st[:11].hex())))
    return out, store(s), bytes(s.m.memory[0x4000:0x8000]), len(s.faults)

def repair(rom, syms, ram):
    res = []
    base = syms['MSG_STORE']
    for name, pokes in (('bad bytes + stray 03', {5: 0xff, 9: 0x03, 20: 0xdc, 31: 0x03}),
                        ('marker damaged', {0: 0x41, 40: 0xd3, 41: 0x41}),
                        ('DA lost', None)):
        r = bytearray(ram)
        if pokes is None:
            e = int.from_bytes(r[syms['STORE_END'] - 0x4000:syms['STORE_END'] - 0x4000 + 2], 'little')
            r[e - 0x4000] = 0x20
        else:
            for off, v in pokes.items(): r[base - 0x4000 + off] = v
        s = S.Sign(rom, syms, fresh_ram=True); s.m.set_memory_block(0x4000, bytes(r)); s.run_ms(4000)
        res.append((name, store(s), s.ram('SEQ_LIST', syms['SEQ_LIST_LEN'])))
    s = S.Sign(rom, syms, fresh_ram=True, seed=7); s.run_ms(4000)
    res.append(('fresh RAM', store(s), s.ram('SEQ_LIST', syms['SEQ_LIST_LEN'])))
    return res

if __name__ == '__main__':
    A, B = S.assemble(sys.argv[1]), S.assemble(sys.argv[2])
    what = sys.argv[3:] or ['editor', 'render', 'serial', 'repair']
    ok = True
    if 'editor' in what:
        (ka, sa, qa, aa, ca, fa), (kb, sb, qb, ab_, cb, fb) = editor(*A), editor(*B)
        dk = [(i, x[0], x[1], y[1]) for i, (x, y) in enumerate(zip(ka, kb)) if x[1] != y[1]]
        df = [(i, x[0]) for i, (x, y) in enumerate(zip(ka, kb)) if x[2] != y[2] and not x[0].startswith('~')]   # ~: the display is running
        print('editor: %d keys; keys processed differ at %s; steady frames differ at %s' % (len(ka), dk[:8] or 'none', df[:8] or 'none'))
        print('  typed nothing (A): %s' % [x[0] for x in ka if not x[1] and x[0] not in ('SHIFT',)][:12])
        print('  store same %s (%d bytes), seq same %s, address %d/%d, clock %s / %s, faults %d %d' % (sa == sb, len(sa), qa == qb, aa, ab_, ca, cb, fa, fb))
        ok &= not dk and not df and sa == sb and qa == qb and aa == ab_ and ca == cb
    if 'render' in what:
        for (n, fa, xa), (_, fb, xb) in zip(render(*A), render(*B)):
            ph, real, first = frames_diff(fa, fb)
            print('render %-8s frames %5d vs %5d  phase %4d  real %d %s  faults %d %d' % (n, len(fa), len(fb), ph, real, first or '', xa, xb))
            ok &= real == 0
    ram = None
    if 'serial' in what or 'repair' in what:
        (oa, sa, ram, fa), (ob, sb, ramb, fb) = serial(*A), serial(*B)
        d = [(x[0], x[1][:60], y[1][:60]) for x, y in zip(oa, ob) if x[1] != y[1]]
        print('serial: %d exchanges, replies differ: %s; store same %s (%d bytes); faults %d %d' % (len(oa), d or 'none', used(sa) == used(sb), len(used(sa)), fa, fb))
        ok &= not d and used(sa) == used(sb)
    if 'repair' in what:
        for (n, sa, qa), (_, sb, qb) in zip(repair(A[0], A[1], ram), repair(B[0], B[1], ramb)):
            print('repair %-22s store same %s (%d bytes), seq same %s' % (n, used(sa) == used(sb), len(used(sa)), qa == qb))
            ok &= used(sa) == used(sb) and qa == qb
    print('A/B:', 'SAME' if ok else 'DIFFERENT')
