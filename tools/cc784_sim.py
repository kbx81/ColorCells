#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["z80"]
# ///
"""
cc784_sim.py - run the CC784NIR ROM under emulation (kosarev's z80 core) with a fake
300-baud serial line, IR receiver and 60 Hz mains NMI.

    uv run tools/cc784_sim.py stack [stock|patched]
        Boot with random RAM, play the demo, load a message that uses every effect,
        run the B4 queries, drive the editor over IR. Prints the stack high-water mark
        per phase and the bytes the sign transmitted.

    uv run tools/cc784_sim.py compare SRC_DIR_A SRC_DIR_B
        Assemble both, run the same scripted session with zeroed RAM, and compare the
        sequence of distinct frames the panel was sent plus every serial reply. A few
        frames caught one scroll step apart are timing, not behaviour.

Facts the model rests on (all traced in the firmware notes): INT every 1024 T
(8 MHz / 1024; 4 MHz cannot keep up with the tick work, so the CPU is 8 MHz),
NMI at 60 Hz, PORT_IN bit 3 = serial RX (1 = space), bit 1 = IR burst,
CTRL_LATCH bit 4 = serial TX (1 = space). The stack watch counts only writes at
SP, so store shuffles next to the stack do not register.
"""
import hashlib, os, pathlib, random, subprocess, sys, tempfile

import z80

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import cc784_ir  # noqa: E402

CPU_HZ = 8_000_000
TICK_T = CPU_HZ // 7812      # INT period in T-states
NMI_T = CPU_HZ // 60
BIT_T = round(CPU_HZ / 300)  # serial bit at 300 baud
US = CPU_HZ / 1_000_000
SLICE = 128                  # run granularity


def assemble(src_dir):
    """assemble cc784nir.asm from src_dir into a temp dir; return (rom bytes, symbols)"""
    src_dir = pathlib.Path(src_dir).resolve()
    asm = src_dir / 'cc784nir.asm'
    if not asm.exists():
        sys.exit('no cc784nir.asm in %s' % src_dir)
    with tempfile.TemporaryDirectory() as tmp:
        sym = pathlib.Path(tmp) / 'out.sym'
        text = asm.read_text()
        import re
        m = re.search(r'OUTPUT\s+"([^"]+)"', text)
        out_name = m.group(1) if m else 'cc784nir.bin'
        # assemble a copy so the source tree is untouched
        (pathlib.Path(tmp) / 'cc784nir.asm').write_text(text)
        r = subprocess.run(['sjasmplus', '--sym=%s' % sym, 'cc784nir.asm'], cwd=tmp,
                           capture_output=True, text=True)
        if r.returncode:
            sys.exit(r.stdout + r.stderr)
        rom = (pathlib.Path(tmp) / out_name).read_bytes()[:0x4000]
        syms = {}
        for line in sym.read_text().splitlines():
            name, _, val = line.partition(': EQU ')
            if val:
                syms[name.strip()] = int(val, 16)
    return rom, syms


class Sign:
    def __init__(self, rom, syms, fresh_ram=True, seed=1):
        self.rom, self.sym = rom, syms
        self.m = m = z80.Z80Machine()
        m.set_memory_block(0, rom)
        rng = random.Random(seed)
        ram = bytes(rng.randrange(256) for _ in range(0x2000)) if fresh_ram else bytes(0x2000)
        m.set_memory_block(0x4000, ram)
        self.stack_top = syms.get('STACK_TOP', 0x4040)
        self.stack_lo = 0x3E00 if self.stack_top == 0x4040 else self.stack_top - 0x300
        m.mark_addrs(self.stack_lo, self.stack_top - self.stack_lo, m.WRITE_MARK)
        m.mark_addrs(0x8000, 1, m.WRITE_MARK)
        m.mark_addrs(0x0000, 0x4000, m.WRITE_MARK)
        m.set_write_callback(self._on_write)
        m.set_input_callback(self._on_input)
        m.set_output_callback(self._on_output)
        self.t = 0
        self.next_int, self.next_nmi = TICK_T, NMI_T
        self.min_stack, self.min_stack_pc = self.stack_top, None
        self.rom_writes = 0
        self.latch = 0
        self.tx_edges = []
        self.rx_events, self.ir_events = [], []
        self.rx_i = self.ir_i = 0
        self.rx_level = self.ir_level = 0
        self.rx_busy_until = self.ir_busy_until = 0
        self.burst, self.frames = [], []

    # ---- memory and port hooks
    def _on_write(self, addr, value):
        # a write-marked address is replaced by this callback, so store it ourselves
        if addr == 0x8000:
            old, self.latch = self.latch, value
            if (old ^ value) & 0x10:
                self.tx_edges.append((self.t, (value >> 4) & 1))
            return
        if addr < 0x4000:
            self.rom_writes += 1          # swallowed, like the real EPROM
        else:
            self.m.memory[addr] = value
        sp = self.m.sp
        if sp - 2 <= addr <= sp + 1 and addr < self.min_stack:
            self.min_stack, self.min_stack_pc = addr, self.m.pc

    def _level(self, events, idx_attr, level_attr):
        i, lvl = getattr(self, idx_attr), getattr(self, level_attr)
        while i < len(events) and events[i][0] <= self.t:
            lvl = events[i][1]; i += 1
        setattr(self, idx_attr, i); setattr(self, level_attr, lvl)
        return lvl

    def _on_input(self, port):
        if port & 0xff == 0xc0:
            rx = self._level(self.rx_events, 'rx_i', 'rx_level')
            ir = self._level(self.ir_events, 'ir_i', 'ir_level')
            return (rx << 3) | (ir << 1)
        return 0xff

    def _on_output(self, port, value):
        if port & 0xff == 0x4e:           # ROW_INDEX 0, second pass: colour byte + 86 columns
            self.burst.append(value)
            if len(self.burst) == 87:
                f = bytes(self.burst); self.burst = []
                if not self.frames or self.frames[-1] != f:
                    self.frames.append(f)

    # ---- interrupts, raised by hand
    def _push_pc(self):
        m = self.m
        sp = (m.sp - 2) & 0xffff
        m.memory[sp] = m.pc & 0xff
        m.memory[(sp + 1) & 0xffff] = m.pc >> 8
        m.sp = sp
        if self.stack_lo <= sp < self.min_stack:
            self.min_stack, self.min_stack_pc = sp, m.pc

    def _irq(self):
        m = self.m
        if m.iff1 and not m.int_disabled:
            self._push_pc(); m.iff1 = 0; m.iff2 = 0; m.pc = 0x38
            return True
        return False

    def _nmi(self):
        self._push_pc(); self.m.iff1 = 0; self.m.pc = 0x66

    def run(self, t_states):
        end = self.t + t_states
        pending = False
        m = self.m
        while self.t < end:
            if self.t >= self.next_int:
                pending = True
                self.next_int += TICK_T
            # the core can stop between a DD/FD prefix and its opcode, where a real
            # Z80 takes no interrupt: hold both kinds until the next slice
            if m.index_rp_kind is z80.HL:
                if pending and self._irq():
                    pending = False
                if self.t >= self.next_nmi:
                    self._nmi()
                    self.next_nmi += NMI_T
            m.ticks_to_stop = SLICE
            m.run()
            self.t += SLICE

    def run_ms(self, ms):
        self.run(int(ms * 1000 * US))

    # ---- stimulus
    def send_bytes(self, data, gap_bits=1):
        t = max(self.t, self.rx_busy_until)
        for b in data:
            for bit in [1] + [0 if (b >> i) & 1 else 1 for i in range(8)] + [0]:
                self.rx_events.append((t, bit)); t += BIT_T
            t += gap_bits * BIT_T
        self.rx_busy_until = t

    def send_frame(self, payload, addr=1, flag=0x80):
        self.send_bytes(bytes([0xB1, addr, flag, len(payload)]) + bytes(payload) + bytes([sum(payload) & 0xff]))

    def ir_key(self, key, stretch_us=250):
        """one keystroke as cc784_ir encodes it, with the receiver's burst stretch"""
        idx = cc784_ir.key_index(key) if isinstance(key, str) else key
        t = max(self.t, self.ir_busy_until)
        for seg in cc784_ir.keystroke(idx):
            if seg > 0:
                self.ir_events.append((t, 1)); t += int((seg + stretch_us) * US)
                self.ir_events.append((t, 0))
            else:
                t += int((-seg - stretch_us) * US)
        self.ir_busy_until = t + int(100_000 * US)

    def ir_wait(self):
        if self.ir_busy_until > self.t: self.run(self.ir_busy_until - self.t)

    def rx_wait(self):
        if self.rx_busy_until > self.t: self.run(self.rx_busy_until - self.t)

    # ---- observation
    def tx_bytes(self):
        """decode latch bit-4 edges as 300 baud, 1 = space"""
        out, edges, i = [], self.tx_edges, 0
        def level_at(t):
            l = 0
            for te, le in edges:
                if te <= t: l = le
                else: break
            return l
        while i < len(edges):
            t0, lvl = edges[i]
            if lvl != 1:
                i += 1; continue
            val = 0
            for n in range(8):
                if not level_at(t0 + int((n + 1.5) * BIT_T)):
                    val |= 1 << n
            out.append(val)
            tend = t0 + int(9.5 * BIT_T)
            while i < len(edges) and edges[i][0] < tend:
                i += 1
        return bytes(out)

    def ram(self, name, n=1):
        a = self.sym[name]
        return bytes(self.m.memory[a:a + n])

    def depth(self):
        return self.stack_top - self.min_stack

    def where(self):
        pc = self.min_stack_pc or 0
        base = max((v, k) for k, v in self.sym.items() if v <= pc and v < 0x4000)
        return '%s+%d' % (base[1], pc - base[0])


# a message that touches every renderer path; no 0E (that is "delete text" to the parser)
FX_MAGIC = (b'\x09\x30\x30\x0e'
            b'\x12\x14HELLO \x8c\x19PAUSE \x1aUP \x1bDOWN \x0fRIGHT \xbbHOLD \x06\x18LEFT '
            b'\x1fMAGIC WORDS $9.99 HERE! \xbd\xbcRAINBOW \x10BIG \x13ITALIC \x11'
            b'\xb8FF7F3E1C08 \xb9THIN\x19 \x5f \xbeTINY TEXT LINE\x11 \x07'
            b'\x04\x30\x30')
FX_PLAIN = FX_MAGIC.replace(b'\x1fMAGIC WORDS $9.99 HERE! \xbd', b'')   # MAGIC is seeded from the clock


def cmd_stack(build):
    rom, syms = assemble(HERE.parent / 'src' / build)
    addr = 0 if build == 'stock' else 1          # stock boots with address 0 (B5)
    s = Sign(rom, syms, fresh_ram=True)

    def report(name):
        print('%-34s depth %3d at %-26s tx=%s' % (name, s.depth(), s.where(), s.tx_bytes().hex()[:60]))
        s.min_stack = s.stack_top; s.tx_edges.clear()

    s.run_ms(3000); report('boot + demo 3 s')
    s.run_ms(20000); report('demo 20 s more')
    s.send_frame(FX_MAGIC, addr=addr); s.rx_wait(); s.run_ms(500); report('load effects msg (ACK expected)')
    s.run_ms(40000); report('effects msg playing 40 s')
    for q, wait in ((b'0', 2500), (b'1', 2500), (b'3', 25000)):
        s.send_frame(b'\xb4' + q, addr=addr, flag=0x80); s.rx_wait(); s.run_ms(wait)
        report("B4 '%s' immediate" % q.decode())
    s.send_frame(b'\xb4\x30', addr=addr, flag=0x00); s.rx_wait(); s.run_ms(30000)
    report("B4 '0' deferred (30 s wait)")
    s.send_frame(b'\x03', addr=0x2a); s.rx_wait(); s.run_ms(1500)
    big = b'\x09\x30\x31\x0e\x12' + b'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG ' * 5
    s.send_frame(big[:254], addr=addr); s.rx_wait(); s.run_ms(1500)
    s.send_frame(b'\x09\x30\x31\xb3' + b'AND AGAIN ' * 20, addr=addr); s.rx_wait(); s.run_ms(1500)
    s.send_frame(b'\x04\x30\x31\x30\x30', addr=addr); s.rx_wait(); s.run_ms(3000)
    report('clear + chunked message + seq')
    s.ir_key('STOP'); s.ir_wait(); s.run_ms(800); report('IR STOP -> editor')
    for k in ('H', 'I', 'SPACE', 'BOLD', 'W', 'O', 'W', 'FLASH', 'COLOR', '3', 'RIGHT', 'LEFT', 'DEL'):
        s.ir_key(k); s.ir_wait(); s.run_ms(300)
    report('editor typing')
    s.ir_key('SHIFT'); s.ir_key('STOP'); s.ir_key('MAGIC'); s.ir_wait(); s.run_ms(1500); report('FUNC+MAGIC = ADDRESS? menu')
    s.ir_key('2'); s.ir_key('STOP'); s.ir_wait(); s.run_ms(1500); report('address set')
    s.ir_key('SEQ'); s.ir_wait(); s.run_ms(1500)
    s.ir_key('0'); s.ir_key('0'); s.ir_key('STOP'); s.ir_wait(); s.run_ms(1500)
    s.ir_key('STOP'); s.ir_wait(); s.run_ms(1500); report('SEQ menu, leave editor')
    s.run_ms(5000); report('display resumes 5 s')
    print('address now', s.ram('MY_ADDRESS', 2).hex(), ' store head', s.ram('MSG_STORE', 12).hex(),
          ' writes into ROM', s.rom_writes)


def session(rom, syms):
    s = Sign(rom, syms, fresh_ram=False)
    marks = []
    def mark(name):
        marks.append((name, list(s.frames), s.tx_bytes().hex(), s.depth()))
        s.tx_edges.clear(); s.frames.clear()
    s.run_ms(3000); mark('boot + demo 3 s')
    s.send_frame(FX_PLAIN); s.rx_wait(); s.run_ms(45000); mark('effects message 45 s')
    s.send_frame(b'\xb4\x31', flag=0x80); s.rx_wait(); s.run_ms(2500); mark("B4 '1'")
    s.ir_key('STOP'); s.ir_wait(); s.run_ms(800)
    for k in ('H', 'I', 'SPACE', 'BOLD', 'W', 'O', 'W', 'FLASH', 'COLOR', '3', 'RIGHT', 'LEFT', 'DEL',
              'LARGE', 'X', 'Y', 'Z', 'SPACE', 'NORMAL', 'Q', 'SPACE', 'SHIFT', 'STOP', 'FLASH'):
        s.ir_key(k); s.ir_wait(); s.run_ms(300)
    mark('editor typing')
    s.ir_key('SHIFT'); s.ir_key('STOP'); s.ir_key('MAGIC'); s.ir_wait(); s.run_ms(1500)
    s.ir_key('2'); s.ir_key('STOP'); s.ir_wait(); s.run_ms(1500)
    s.ir_key('SEQ'); s.ir_wait(); s.run_ms(1500)
    s.ir_key('0'); s.ir_key('0'); s.ir_key('STOP'); s.ir_wait(); s.run_ms(1500)
    s.ir_key('STOP'); s.ir_wait(); s.run_ms(8000); mark('menus, back to display 8 s')
    s.send_frame(b'\xb4\x33', flag=0x80, addr=2); s.rx_wait(); s.run_ms(25000); mark("B4 '3'")
    return marks


def _transient(f):
    """a frame the panel only sees because the row-0 pass fell inside an effect's
    rewrite: blank after clear_framebuf, or a fill in progress (run of colour bytes)"""
    d = f[1:]
    if all(c == 0x80 for c in d):
        return True
    run = best = 0
    for c in d:
        run = run + 1 if c & 0x80 else 0
        best = max(best, run)
    return best >= 16


def _shifted(x, y):
    """the same image one or two scroll steps apart"""
    dx, dy = x[1:], y[1:]
    return any(dx[k:] == dy[:-k] or dx[:-k] == dy[k:] for k in (1, 2))


def _phase_artefact(fa, fb):
    return _shifted(fa, fb) or _transient(fa) or _transient(fb)


def _extra_is_phase(f, own, idx):
    """an inserted/deleted frame is timing if it is a scroll step of its neighbour"""
    if _transient(f):
        return True
    for n in (idx - 1, idx + 1):
        if 0 <= n < len(own) and (_shifted(f, own[n]) or f == own[n]):
            return True
    return False


def cmd_compare(dir_a, dir_b):
    import difflib
    a = session(*assemble(dir_a))
    b = session(*assemble(dir_b))
    clean = True
    prev_a = prev_b = None
    for (name, fa, ta, da), (_, fb, tb, db) in zip(a, b):
        # a segment may open with the previous segment's last frame if the row-0
        # pass straddled the mark: not a difference
        if prev_a and fa and fa[0] == prev_a: fa = fa[1:]
        if prev_b and fb and fb[0] == prev_b: fb = fb[1:]
        prev_a = fa[-1] if fa else prev_a
        prev_b = fb[-1] if fb else prev_b
        sm = difflib.SequenceMatcher(a=fa, b=fb, autojunk=False)
        phase = real = 0
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag == 'equal':
                continue
            if tag == 'replace' and i2 - i1 == j2 - j1:
                for k in range(i2 - i1):
                    if _phase_artefact(fa[i1 + k], fb[j1 + k]): phase += 1
                    else: real += 1
            else:
                for k in range(i1, i2):
                    if _extra_is_phase(fa[k], fa, k): phase += 1
                    else: real += 1
                for k in range(j1, j2):
                    if _extra_is_phase(fb[k], fb, k): phase += 1
                    else: real += 1
        txs = 'same' if ta == tb else 'DIFFER'
        print('%-28s frames %4d vs %4d, phase %2d, real %2d   replies %s   depth %d vs %d'
              % (name, len(fa), len(fb), phase, real, txs, da, db))
        if ta != tb:
            print('    A', ta[:70]); print('    B', tb[:70])
        clean &= real == 0 and (ta == tb or name == "B4 '1'")   # B4 '1' reports the store size
    print('OK: same behaviour' if clean else 'CHECK: real frame differences or reply mismatch')


if __name__ == '__main__':
    args = sys.argv[1:]
    if not args or args[0] not in ('stack', 'compare'):
        sys.exit(__doc__)
    if args[0] == 'stack':
        cmd_stack(args[1] if len(args) > 1 else 'patched')
    else:
        if len(args) != 3:
            sys.exit('compare needs two source directories')
        cmd_compare(args[1], args[2])
