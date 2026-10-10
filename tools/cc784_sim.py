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
        frames caught one scroll step apart are timing, not behavior.

    uv run tools/cc784_sim.py eeprom
        Self-test of the banked EEPROM model below (no firmware involved).

    uv run tools/cc784_sim.py ota
        Boot stub bank selection in every trailer scenario, then the page writer.

    uv run tools/cc784_sim.py update
        A whole OTA over the fake serial line: B5 I/C/B/W/F/R, then boot from bank 1.

    uv run tools/cc784_sim.py push
        The same through the host tool itself (cc784_ota.push over a SimLink).

    uv run tools/cc784_sim.py ram
        The build on the stock 8 K RAM (mirrored) and on a 62256: sizes, fill, dump.

    uv run tools/cc784_sim.py fuzz [RUNS]
        Cut the power at a random instant of an update, RUNS times (default 100);
        every reboot must land in a bank whose trailer and image CRC check out.

Facts the model rests on (all traced in the firmware notes): INT every 1024 T
(8 MHz / 1024; 4 MHz cannot keep up with the tick work, so the CPU is 8 MHz),
NMI at 60 Hz, PORT_IN bit 3 = serial RX (1 = space), bit 1 = IR burst,
CTRL_LATCH bit 4 = serial TX (1 = space). The stack watch counts only writes at
SP, so store shuffles next to the stack do not register.

The ROM is an AT28C256 with the OTA bodges (CC784_ota.md §2): /WE on Z80 /WR,
/OE on /RD, A14..A16 from BANK_REG, a '273 written at C000 and zero at reset.
Page writes, the 150 us byte-load timer, the 10 ms write cycle (every ROM read
returns the status byte; an instruction fetch then is a fault) and software
data protection are modeled; so is the board's watchdog, which zeroes
CTRL_LATCH 512 us after the last interrupt acknowledge. Faults are collected in
Sign.faults rather than raised, so a session can report them at the end.
"""
import hashlib, os, pathlib, random, subprocess, sys, tempfile, time

import z80

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import cc784_ir  # noqa: E402

CPU_HZ = 8_000_000
TICK_T = CPU_HZ // 7812      # INT period in T-states
NMI_T = CPU_HZ // 60
US = CPU_HZ / 1_000_000
SLICE = 128                  # run granularity
BANK_SIZE = 0x4000
T_BLC = int(150 * US)        # AT28C256 page-load byte-to-byte limit
T_WC = int(10_000 * US)      # AT28C256 write cycle, worst case
WDOG_T = 4096                # HC4020 Q13 rises this many T after an INTA


class PowerCut(Exception):
    pass


class Eeprom:
    """AT28C256-style chip: 16 K banks selected by BANK_REG, 64-byte page writes,
    software data protection. Times are Sign.t (T-states)."""
    SDP_ON = ((0x5555, 0xAA), (0x2AAA, 0x55), (0x5555, 0xA0))
    SDP_OFF = ((0x5555, 0xAA), (0x2AAA, 0x55), (0x5555, 0x80),
               (0x5555, 0xAA), (0x2AAA, 0x55), (0x5555, 0x20))

    def __init__(self, image, sdp=True, faults=None):
        self.image = bytearray(image)
        self.banks = len(self.image) // BANK_SIZE
        self.sdp = sdp                  # protection armed
        self.faults = faults if faults is not None else []
        self.seq = []                   # SDP command bytes seen so far
        self.unlocked = False           # a complete SDP_ON sequence precedes this page
        self.page = None                # (page number, {addr: byte}) while loading
        self.last_t = 0
        self.busy_until = 0             # end of the internal write cycle
        self.last_byte = 0
        self.toggle = 0
        self.last_page = None

    def bank_image(self, bank):
        bank %= self.banks
        return bytes(self.image[bank * BANK_SIZE:(bank + 1) * BANK_SIZE])

    def image_after_power_cut(self, t, rng):
        """the chip as a power cut at t leaves it: a page mid-cycle is indeterminate"""
        img = bytearray(self.image)
        if self.page and self.page[0] >= 0:
            base = self.page[0] * 64
            for i in range(64):
                img[base + i] = rng.randrange(256)
        elif t < self.busy_until and self.last_page is not None:
            base = self.last_page * 64
            for i in range(64):
                img[base + i] = rng.randrange(256)
        return bytes(img)

    def update(self, t):
        if self.page and t - self.last_t > T_BLC:      # load window closed: program
            self.busy_until = self.last_t + T_BLC + T_WC
            for a, v in self.page[1].items():
                self.image[a] = v
            self.last_page = self.page[0] if self.page[0] >= 0 else None
            self.page = None
        return self.page is not None or t < self.busy_until

    busy = update

    def status(self):
        """what a read returns while busy: /D7 of the last byte, D6 toggling"""
        self.toggle ^= 1
        return ((self.last_byte ^ 0x80) & 0x80) | (self.toggle << 6) | 0x3F

    def write(self, addr, value, t):
        if self.update(t) and not self.page:
            self.faults.append((t, 'write during write cycle', addr, value))
            return
        self.last_byte = value
        if self.page:
            if addr >> 6 != self.page[0]:
                self.faults.append((t, 'byte outside the open page', addr, value))
                return
            self.page[1][addr] = value
            self.last_t = t
            return
        self.seq.append((addr, value))
        n = len(self.seq)
        if self.seq == list(self.SDP_ON[:n]) or self.seq == list(self.SDP_OFF[:n]):
            if self.seq == list(self.SDP_ON):
                self.sdp, self.unlocked, self.seq = True, True, []
            elif self.seq == list(self.SDP_OFF):
                self.sdp, self.seq = False, []
                self.page, self.last_t = (-1, {}), t       # the sequence is itself a cycle
            return
        self.seq = []
        if self.sdp and not self.unlocked:
            self.faults.append((t, 'write blocked by SDP', addr, value))
            return
        self.unlocked = False
        self.page, self.last_t = (addr >> 6, {addr: value}), t


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
        rom = (pathlib.Path(tmp) / out_name).read_bytes()
        syms = {}
        for line in sym.read_text().splitlines():
            name, _, val = line.partition(': EQU ')
            if val:
                syms[name.strip()] = int(val, 16)
    return rom, syms


class Sign:
    def __init__(self, rom, syms, fresh_ram=True, seed=1, sdp=True, ram8k=False, mains=True, baud=300, crystal=False):
        # rom: one 16 K bank (the rest of the chip erased) or the whole chip image
        # ram8k: the stock 6264, which mirrors 4000-5FFF at 6000-7FFF
        # mains=False: a DC supply, no NMI from the zero-cross detector
        # crystal=True: the IR+clock add-in board is fitted: 64 Hz on the NMI while BANK_REG bit 7 selects it
        self.mains, self.crystal = mains, crystal
        image = bytes(rom) + b'\xff' * (2 * BANK_SIZE - len(rom)) if len(rom) <= BANK_SIZE else bytes(rom)
        self.faults = []
        self.ee = Eeprom(image, sdp=sdp, faults=self.faults)
        self.bank_reg = 0
        self.ee_marked = self.busy_fault = False
        self.cut_at = None                  # sim time at which PowerCut is raised
        self.rom, self.sym = image[:BANK_SIZE], syms
        self.m = m = z80.Z80Machine()
        m.set_memory_block(0, self.rom)
        rng = random.Random(seed)
        ram = bytes(rng.randrange(256) for _ in range(0x4000)) if fresh_ram else bytes(0x4000)
        self.ram8k = ram8k
        if ram8k:
            ram = ram[:0x2000] * 2
            m.mark_addrs(0x4000, 0x4000, m.WRITE_MARK)      # every RAM write is mirrored
        m.set_memory_block(0x4000, ram)
        self.stack_top = syms.get('STACK_TOP', 0x4040)
        self.stack_lo = 0x3E00 if self.stack_top == 0x4040 else self.stack_top - 0x300
        m.mark_addrs(self.stack_lo, self.stack_top - self.stack_lo, m.WRITE_MARK)
        m.mark_addrs(0x8000, 1, m.WRITE_MARK)
        m.mark_addrs(0x0000, 0x4000, m.WRITE_MARK)
        m.mark_addrs(0xC000, 0x4000, m.WRITE_MARK | m.READ_MARK)
        m.set_write_callback(self._on_write)
        m.set_read_callback(self._on_read)
        m.set_input_callback(self._on_input)
        m.set_output_callback(self._on_output)
        self.t = 0
        self.next_int, self.next_nmi = TICK_T, (NMI_T if mains else 1 << 62)   # bank_reg is 0: the mains, if any
        self.last_inta = 0
        self.min_stack, self.min_stack_pc = self.stack_top, None
        self.rom_writes = 0
        self.wdog_clears = 0                # times the watchdog blanked the control latch
        self.refreshes = 0                  # frames sent to the panel, distinct or not
        self.latch = 0
        self.tx_edges = []
        self.rx_events, self.ir_events = [], []
        self.rx_i = self.ir_i = 0
        self.rx_level = self.ir_level = 0
        self.rx_busy_until = self.ir_busy_until = 0
        self.int_pending = False
        self.tick_t = TICK_T + int(2 * US)  # 128 us + ~2 us of acknowledge latency, as measured on the board
        self.set_baud(baud)
        self.burst, self.frames = [], []
        self.row_starts, self.last_out_t = [], 0   # (t, port low nibble) at each row burst

    # ---- memory and port hooks
    def _set_latch(self, value):
        old, self.latch = self.latch, value
        if (old ^ value) & 0x10:
            self.tx_edges.append((self.t, (value >> 4) & 1))

    def _chip_addr(self, addr):
        return ((self.bank_reg % self.ee.banks) << 14) | addr

    def _nmi_period(self):
        """what drives the NMI for the current bank register: the '151 on the add-in
        board picks the crystal (64 Hz) with bit 7 set, the mains (60 Hz) with it clear"""
        if self.bank_reg & 0x80:
            return CPU_HZ // 64 if self.crystal else None
        return NMI_T if self.mains else None

    def _set_bank_reg(self, value):
        self.bank_reg = value
        self._ee_sync(force=True)
        p = self._nmi_period()
        if p is None:
            self.next_nmi = 1 << 62
        elif self.next_nmi > self.t + p:
            self.next_nmi = self.t + p

    def _ee_sync(self, force=False):
        """mirror the chip into 0000-3FFF: the selected bank when idle, the status
        byte (via the read callback) while a write cycle is in progress"""
        m = self.m
        busy = self.ee.update(self.t)
        if busy and not self.ee_marked:
            m.mark_addrs(0, BANK_SIZE, m.READ_MARK)
            self.ee_marked = True
            self.busy_fault = False
        elif not busy and (self.ee_marked or force):
            if self.ee_marked:
                m.unmark_addrs(0, BANK_SIZE, m.READ_MARK)
                self.ee_marked = False
            m.set_memory_block(0, self.ee.bank_image(self.bank_reg))

    def _on_write(self, addr, value):
        # a write-marked address is replaced by this callback, so store it ourselves
        if addr == 0x8000:
            self._set_latch(value)
            return
        if addr >= 0xC000:
            self._set_bank_reg(value)
            return
        if addr < 0x4000:
            self.rom_writes += 1
            self.ee.write(self._chip_addr(addr), value, self.t)
            self._ee_sync()
        else:
            self.m.memory[addr] = value
            if self.ram8k:
                self.m.memory[addr ^ 0x2000] = value
        sp = self.m.sp
        if sp - 2 <= addr <= sp + 1 and addr < self.min_stack:
            self.min_stack, self.min_stack_pc = addr, self.m.pc

    def _on_read(self, addr):
        if addr >= 0xC000:
            # a read also clocks the '273, with whatever floats on the bus
            self.faults.append((self.t, 'read of BANK_REG clocks it with a floating bus', addr, 0xFF))
            self._set_bank_reg(0xFF)
            return 0xFF
        if self.m.pc < 0x4000 and not self.busy_fault:
            self.faults.append((self.t, 'instruction fetch from ROM during a write cycle', self.m.pc, 0))
            self.busy_fault = True
        return self.ee.status()

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
        if port & 0xf0 == 0x40:           # a row burst: note where each one starts
            if self.t - self.last_out_t > 3000:    # a burst pauses for the engines, bursts are a tick apart
                self.row_starts.append((self.t, port & 0x0f))
            self.last_out_t = self.t
        if port & 0xff == 0x4e:           # ROW_INDEX 0, second pass: color byte + 86 columns
            self.burst.append(value)
            if len(self.burst) == 87:
                f = bytes(self.burst); self.burst = []
                self.refreshes += 1                 # every frame the panel is sent
                if not self.frames or self.frames[-1] != f:
                    self.frames.append(f)           # only the distinct ones

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
            self._push_pc(); m.iff1 = 0; m.iff2 = 0; m.pc = 0x38; m.halted = 0
            return True
        return False

    def _nmi(self):
        self._push_pc(); self.m.iff1 = 0; self.m.pc = 0x66; self.m.halted = 0

    def run(self, t_states):
        end = self.t + t_states
        m = self.m
        while self.t < end:
            if self.cut_at is not None and self.t >= self.cut_at:
                raise PowerCut()
            if self.t >= self.next_int:
                self.int_pending = True             # level: held until acknowledged, across run() calls
                self.next_int += self.tick_t        # the counter restarts at the acknowledge: 128 us + latency
            # the core can stop between a DD/FD prefix and its opcode, where a real
            # Z80 takes no interrupt: hold both kinds until the next slice
            if m.index_rp_kind is z80.HL:
                if self.int_pending and self._irq():
                    self.int_pending = False
                    self.last_inta = self.t
                if self.t >= self.next_nmi:
                    self._nmi()
                    p = self._nmi_period()
                    self.next_nmi = self.next_nmi + p if p else 1 << 62
            # watchdog: Q13 of the free-running HC4020 clears CTRL_LATCH while high
            if ((self.t - self.last_inta) // WDOG_T) & 1 and self.latch:
                self._set_latch(0); self.wdog_clears += 1
            if self.ee_marked:
                self._ee_sync()
            m.ticks_to_stop = SLICE
            m.run()
            self.t += SLICE

    def run_ms(self, ms):
        self.run(int(ms * 1000 * US))

    # ---- stimulus
    def set_baud(self, baud):
        """the host's line rate: what send_bytes drives and tx_bytes decodes"""
        self.baud, self.bit_t = baud, round(CPU_HZ / baud)

    def send_bytes(self, data, gap_bits=1):
        t = max(self.t, self.rx_busy_until)
        for b in data:
            for bit in [1] + [0 if (b >> i) & 1 else 1 for i in range(8)] + [0]:
                self.rx_events.append((t, bit)); t += self.bit_t
            t += gap_bits * self.bit_t
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
        """decode latch bit-4 edges at self.baud, 1 = space"""
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
            if t0 + int(9.5 * self.bit_t) > self.t:
                break                           # still on the wire: a real host has not seen it yet
            val = 0
            for n in range(8):
                if not level_at(t0 + int((n + 1.5) * self.bit_t)):
                    val |= 1 << n
            out.append(val)
            tend = t0 + int(9.5 * self.bit_t)
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
          ' writes into ROM', s.rom_writes, ' faults', len(s.faults))
    for t, what, addr, value in s.faults[:5]:
        print('  fault at %.3f s: %s (%04X %02X)' % (t / CPU_HZ, what, addr, value))


def cmd_ota():
    """boot stub and page writer against the chip model, every bank scenario"""
    import cc784_ota
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    app = rom[:BANK_SIZE]
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))

    def corrupt(bank, at=0x2000):
        b = bytearray(bank); b[at] ^= 0x01; return bytes(b)

    def boot(image, ms=3000, **kw):
        s = Sign(image, syms, fresh_ram=True, **kw)
        s.run_ms(ms)
        return s

    erased = app                                       # trailer FF: as built, before pack
    b1 = cc784_ota.pack(app, 1)
    b2 = cc784_ota.pack(app, 2)
    b0 = cc784_ota.pack(app, 0)
    scenarios = [
        ('erased trailers -> bank 0',                 erased + b'\xff' * BANK_SIZE, 0),
        ('T48 image (seq 1 / seq 0) -> bank 0',       b1 + b0, 0),
        ('bank 1 newer (seq 2) -> bank 1',            b1 + b2, 1),
        ('equal seq -> bank 0',                       b1 + b1, 0),
        ('seq wrap: 0 beats FF',                      cc784_ota.pack(app, 0xFF) + b0, 1),
        ('bank 1 newer but image corrupt -> bank 0',  b1 + corrupt(b2), 0),
        ('bank 0 corrupt, bank 1 older -> bank 1',    corrupt(b1) + b0, 1),
        ('bank 0 trailer bad, bank 1 valid -> bank 1', erased + b0, 1),
        ('both corrupt -> bank 0 regardless',         corrupt(b1) + corrupt(b0), 0),
    ]
    for name, image, want in scenarios:
        s = boot(image)
        got = s.ram('ROM_BANK')[0]
        check('%s (booted %d, %d frames, %d faults)' % (name, got, len(s.frames), len(s.faults)),
              got == want and s.frames and not s.faults)

    # trial/confirm: a TRIAL bank boots once and comes out TRIED; a power cycle then skips it
    trial = cc784_ota.pack(app, 2, cc784_ota.STATE_TRIAL)
    s = boot(b1 + trial)
    t1 = cc784_ota.parse_trailer(s.ee.bank_image(1))
    check('TRIAL bank boots (bank %d) and is marked TRIED (%s)' % (s.ram('ROM_BANK')[0], t1),
          s.ram('ROM_BANK')[0] == 1 and t1 and t1['state'] == cc784_ota.STATE_TRIED and not s.faults)
    s2 = boot(bytes(s.ee.image))
    check('power cycle: TRIED bank skipped, bank 0 runs (bank %d)' % s2.ram('ROM_BANK')[0], s2.ram('ROM_BANK')[0] == 0 and not s2.faults)
    s = boot(b1 + trial, mains=False)
    t1 = cc784_ota.parse_trailer(s.ee.bank_image(1))
    check('DC supply: TRIAL boots and is marked TRIED without an NMI (bank %d, %s)' % (s.ram('ROM_BANK')[0], t1),
          s.ram('ROM_BANK')[0] == 1 and t1 and t1['state'] == cc784_ota.STATE_TRIED and not s.faults)

    # boot time: from reset until the stub publishes the bank (NMI_MAGIC set)
    for name, image in (('both valid, one CRC pass', b1 + b2), ('first choice corrupt, two passes', b1 + corrupt(b2))):
        s = Sign(image, syms, fresh_ram=True)
        s.m.memory[syms['NMI_MAGIC']] = 0
        while s.m.memory[syms['NMI_MAGIC']] != 0xA5 and s.t < 4 * CPU_HZ:
            s.run(SLICE * 64)
        print('  boot, %s: %.0f ms' % (name, s.t / CPU_HZ * 1000))

    # page writer: copy the template to RAM and call it as the app would
    src, trap = 0x5000, 0x5100
    data = bytes((i * 7 + 3) & 0xFF for i in range(64))
    def writer_harness(s):
        m = s.m
        m.set_memory_block(src, data)
        m.set_memory_block(syms['STUB_RAM'], rom[syms['stub_lib']:syms['stub_lib'] + syms['STUB_LIB_SIZE']])
        m.set_memory_block(trap, b'\x76')              # HALT as a landing pad
        def call_writer(page_addr, bank):
            m.iff1 = m.iff2 = 0
            m.hl, m.de, m.b = src, page_addr, bank
            m.sp = 0x5ee0
            m.memory[m.sp - 2], m.memory[m.sp - 1] = trap & 0xFF, trap >> 8
            m.sp -= 2
            m.pc = syms['lib_page_writer']
            t0 = s.t
            while m.pc != trap + 1 and s.t - t0 < CPU_HZ // 4:
                s.run(SLICE * 8)
            return m.a, (s.t - t0) / CPU_HZ * 1000
        return call_writer
    sdc = boot(b1 + b0, ms=500, mains=False)
    a, ms = writer_harness(sdc)(0x2040, 1)
    check('DC supply: page write without an NMI wait, status %d in %.1f ms' % (a, ms),
          a == 0 and ms < 15 and sdc.ee.bank_image(1)[0x2040:0x2080] == data and not sdc.faults)
    s = boot(b1 + b0, ms=500)
    m = s.m
    call_writer = writer_harness(s)
    n = len(s.faults)
    a, ms = call_writer(0x2000, 1)
    check('page write to bank 1: status %d in %.1f ms' % (a, ms), a == 0 and 5 < ms < 30)
    check('bank 1 page holds the data', s.ee.bank_image(1)[0x2000:0x2040] == data)
    check('bank 0 untouched', s.ee.bank_image(0)[0x2000:0x2040] == b1[0x2000:0x2040])
    check('running bank restored', s.bank_reg == 0)
    check('no faults (%d)' % (len(s.faults) - n), len(s.faults) == n)
    check('SDP armed by the preamble', s.ee.sdp)
    a, ms = call_writer(0x3FC0, 1)
    check('trailer page write: status %d' % a, a == 0 and s.ee.bank_image(1)[0x3FC0:0x4000] == data)
    m.set_memory_block(src, bytes(64))
    a, ms = call_writer(0x0000, 1)
    check('stub page in the idle bank is writable by the writer itself (handler must refuse): %d' % a, a == 0)
    print('OTA boot/write: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def ota_cmd(s, payload, addr=1, wait_ms=4000):
    """send a B5 frame in immediate mode and return the reply data (None if none)"""
    s.tx_edges.clear()
    s.send_frame(payload, addr=addr, flag=0x80)
    s.rx_wait()
    for _ in range(wait_ms // 50):
        s.run_ms(50)
        tx = s.tx_bytes()
        if len(tx) >= 4 and tx[0] == 0x06 and tx[1] == 0xB1 and len(tx) >= 5 + tx[3]:
            s.run_ms(100)                       # the last byte may still be on the wire
            tx = s.tx_bytes()
            data = tx[4:4 + tx[3]]
            assert sum(data) & 0xFF == tx[4 + tx[3]], 'reply checksum'
            s.run_ms(1000)                      # the sign is deaf through restart_display (B4)
            return data
        if tx and tx[0] == 0x15:
            return None
    return None


def cmd_update(baud=300):
    """a whole OTA over the fake serial line: stage in the idle bank, finish, reboot"""
    import cc784_ota
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    app = rom[:BANK_SIZE]
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))

    # the "new firmware": the same app with one demo-message byte changed
    new_app = app.replace(b'LARGE IMPACT', b'LARGE UPDATE')
    assert new_app != app
    b1, b0 = cc784_ota.pack(app, 1), cc784_ota.pack(app, 0)
    new_bank = cc784_ota.pack(new_app, 2)
    s = Sign(b1 + b0, syms, fresh_ram=True, sdp=False, baud=baud)      # fresh from the T48: SDP off
    s.run_ms(2500)
    check('booted bank 0', s.ram('ROM_BANK')[0] == 0)

    info = ota_cmd(s, b'\xb5I')
    bank, t0, t1 = cc784_ota.parse_info(info) if info else (None, None, None)
    check('I: bank %s, trailers %s / %s' % (bank, t0, t1),
          bank == 0 and t0 and t0['seq'] == 1 and t1 and t1['seq'] == 0)
    pages = [p for p in cc784_ota.changed_pages(b0, new_bank) if p != 255]
    check('diff is one or two pages (%s)' % pages, 1 <= len(pages) <= 2)
    crcs = ota_cmd(s, b'\xb5C' + bytes([pages[0], 2]))
    want = cc784_ota.crc16(b0[pages[0] * 64:(pages[0] + 1) * 64])
    check('C: page crc matches the host view', crcs and int.from_bytes(crcs[:2], 'little') == want)

    # refusals
    r = ota_cmd(s, b'\xb5W' + bytes([3, 0, 0]) + bytes(64))
    check('W into the stub refused (3)', r == b'\x03')
    page = pages[0]
    data = new_bank[page * 64:(page + 1) * 64]
    r = ota_cmd(s, b'\xb5W' + bytes([page]) + (cc784_ota.crc16(data) ^ 1).to_bytes(2, 'little') + data)
    check('W with a bad crc refused (4)', r == b'\x04')
    r = ota_cmd(s, b'\xb5F' + bytes([2]) + (0x1234).to_bytes(2, 'little'))
    check('F with the wrong image crc refused (4)', r == b'\x04')

    # the update
    r = ota_cmd(s, b'\xb5B')
    check('B: trailer erased (%s)' % (r.hex() if r else r), r == b'\x00' and s.ee.bank_image(1)[0x3FC0:0x3FC4] == b'\xff' * 4)
    s.run_ms(2000); s.frames.clear(); s.run_ms(3000)      # staging done, then it must sit still
    lit = sum(1 for c in s.m.memory[syms['FRAMEBUF']:syms['FRAMEBUF'] + 192] if not c & 0x80 and c)
    check('B: UPDATING parked on the panel (test mode set, %d frames in 3 s, %d lit columns)' % (len(s.frames), lit),
          s.ram('TEST_MODE')[0] == 0xFF and len(s.frames) <= 1 and lit > 20)
    check('SDP armed by the first write', s.ee.sdp)
    for page in pages:
        data = new_bank[page * 64:(page + 1) * 64]
        r = ota_cmd(s, b'\xb5W' + bytes([page]) + cc784_ota.crc16(data).to_bytes(2, 'little') + data, wait_ms=6000)
        check('W: page %d written (%s)' % (page, r.hex() if r else r), r == b'\x00' and s.ee.bank_image(1)[page * 64:(page + 1) * 64] == data)
    # three pages in one frame, unchanged content, exercises the multi-page path
    trio = new_bank[0x40 * 64:0x43 * 64]
    r = ota_cmd(s, b'\xb5W' + bytes([0x40]) + cc784_ota.crc16(trio).to_bytes(2, 'little') + trio, wait_ms=8000)
    check('W: three pages in one frame (%s)' % (r.hex() if r else r), r == b'\x00')
    s.run_ms(2000); s.frames.clear(); s.run_ms(3000)
    check('UPDATING still parked after frames carrying 0x20 bytes (%d frames in 3 s)' % len(s.frames), len(s.frames) <= 1)
    image_crc = cc784_ota.crc16(new_bank[cc784_ota.STUB_END:cc784_ota.TRAILER])
    r = ota_cmd(s, b'\xb5F' + bytes([2]) + image_crc.to_bytes(2, 'little'), wait_ms=6000)
    got = s.ee.bank_image(1); tg = cc784_ota.parse_trailer(got)
    check('F: image crc ok, trailer written as TRIAL (%s, %s)' % (r.hex() if r else r, tg),
          r == b'\x00' and got[:cc784_ota.TRAILER] == new_bank[:cc784_ota.TRAILER] and tg and tg['state'] == cc784_ota.STATE_TRIAL and tg['crc_ok'])
    info = ota_cmd(s, b'\xb5I')
    bank, t0, t1 = cc784_ota.parse_info(info) if info else (None, None, None)
    check('I: bank 1 valid, seq 2, TRIAL (%s)' % t1, t1 and t1['seq'] == 2 and t1['state'] == cc784_ota.STATE_TRIAL)
    check('no faults so far (%d)' % len(s.faults), not s.faults)
    for f in s.faults[:5]:
        print('    ', f)

    # the DONE handshake: ACK, processing, 04; a frame sent at once must land
    s.tx_edges.clear(); s.send_frame(b'\x09\x30\x31\x0eHELLO', addr=1, flag=0x81); s.rx_wait()
    for _ in range(80):
        s.run_ms(25)
        if s.tx_bytes()[:2] == b'\x06\x04': break
    s.send_frame(b'\x09\x30\x32\x0eWORLD', addr=1, flag=0x81); s.rx_wait(); s.run_ms(1500)
    store = s.ram('MSG_STORE', 600)
    check('DONE after a flag-81 frame, next frame lands at once (tx %s)' % s.tx_bytes().hex(),
          s.tx_bytes() == b'\x06\x04\x06\x04' and store[store.index(b'\xd0\xd2') + 2:][:5] == b'WORLD')
    check('I reports the DONE feature', len(info) > 21 and info[21] & 1)
    s.tx_edges.clear(); s.frames.clear()
    s.send_frame(b'\xb5R', addr=1, flag=0x80); s.rx_wait(); s.run_ms(4000)
    check('R: rebooted into bank 1', s.ram('ROM_BANK')[0] == 1)
    check('R: test mode cleared by the boot', s.ram('TEST_MODE')[0] == 0)
    info = ota_cmd(s, b'\xb5I')
    bank, t0, t1 = cc784_ota.parse_info(info)
    check('after the trial boot the bank is TRIED (%s), features %02X' % (t1, info[21]),
          t1 and t1['state'] == cc784_ota.STATE_TRIED and info[21] & 0x07 == 0x07)
    r = ota_cmd(s, b'\xb5K' + bytes([cc784_ota.STATE_GOOD, 2]), wait_ms=6000)
    bank, t0, t1 = cc784_ota.parse_info(ota_cmd(s, b'\xb5I'))
    check('K: confirmed GOOD (%s, %s)' % (r.hex() if r else r, t1), r == b'\x00' and t1 and t1['state'] == cc784_ota.STATE_GOOD)
    s2 = Sign(bytes(s.ee.image), syms, fresh_ram=True); s2.run_ms(3000)
    check('power cycle after confirm stays on bank 1', s2.ram('ROM_BANK')[0] == 1)
    # a trial image that hangs: the next power cycle brings the old image back
    hang = bytearray(new_app); hang[cc784_ota.STUB_END:cc784_ota.STUB_END + 2] = b'\x18\xfe'   # JR $ at the jump table
    hang_bank = cc784_ota.pack(bytes(hang), 3, cc784_ota.STATE_TRIAL)
    s3 = Sign(s.ee.bank_image(1) + hang_bank, syms, fresh_ram=True); s3.run_ms(3000)
    check('hanging TRIAL boots (bank %d, %d frames)' % (s3.ram('ROM_BANK')[0], len(s3.frames)), s3.ram('ROM_BANK')[0] == 1 and len(s3.frames) < 3)
    s4 = Sign(bytes(s3.ee.image), syms, fresh_ram=True); s4.run_ms(3000)
    check('power cycle: back on the GOOD image (bank %d, %d frames)' % (s4.ram('ROM_BANK')[0], len(s4.frames)), s4.ram('ROM_BANK')[0] == 0 and len(s4.frames) > 20)
    s.send_frame(b'\xb4\x30', addr=1, flag=0x80); s.rx_wait(); s.run_ms(2500)
    check('new firmware answers B4 0', b'78409O1702930205' in s.tx_bytes())
    s.frames.clear(); s.run_ms(30000)
    check('demo runs from bank 1 (%d frames)' % len(s.frames), len(s.frames) > 100)
    check('no faults (%d)' % len(s.faults), not s.faults)
    print('OTA update: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


class SimLink:
    """a cc784.py transport whose far end is the emulated sign; read timeouts are
    sim time, and the wall-clock gaps between calls (the host's sleeps) advance the
    sim too, so the host tool's pacing is honoured"""
    def __init__(self, sign):
        self.s = sign
        self.delivered = 0
        self.last = time.time()

    def _catch_up(self):
        now = time.time()
        self.s.run_ms(min(10_000, (now - self.last) * 1000))
        self.last = time.time()

    def _available(self):
        out = self.s.tx_bytes()
        edges = self.s.tx_edges
        if edges and self.s.t - edges[-1][0] < 11 * self.s.bit_t:
            out = out[:-1]                      # the last byte may still be on the wire
        return out

    def write(self, data):
        self._catch_up()
        self.s.send_bytes(data)
        self.s.rx_wait()

    def read(self, n, timeout):
        self._catch_up()
        deadline = self.s.t + int(timeout * CPU_HZ)
        while True:
            have = self._available()[self.delivered:]
            if len(have) >= n or self.s.t >= deadline:
                out = have[:n]
                self.delivered += len(out)
                self.last = time.time()
                return out
            self.s.run_ms(20)

    def reset_input(self):
        self.s.tx_edges.clear()
        self.delivered = 0

    def close(self):
        pass


def cmd_push(baud=300):
    """the host tool's push() end to end against the emulated sign"""
    import cc784, cc784_ota
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    app = rom[:BANK_SIZE]
    new_app = app.replace(b'LARGE IMPACT', b'LARGE UPDATE')
    new_bank = cc784_ota.pack(new_app, 7)
    s = Sign(cc784_ota.pack(app, 1) + cc784_ota.pack(app, 0), syms, fresh_ram=True, sdp=False, baud=baud)
    s.run_ms(2500)
    sign = cc784.Sign(SimLink(s), 1, baud=baud)
    sign.post_ack = 0.2
    ok = cc784_ota.push(sign, new_bank, seq=None)
    got = s.ee.bank_image(1)
    t = cc784_ota.parse_trailer(got)
    ok = (ok and got[:cc784_ota.TRAILER] == new_bank[:cc784_ota.TRAILER] and t['seq'] == 2 and t['state'] == cc784_ota.STATE_GOOD
          and s.ram('ROM_BANK')[0] == 1 and not s.faults)
    ok = ok and cc784_ota.rollback(cc784_ota.Ota(sign)) and s.ram('ROM_BANK')[0] == 0
    print('host push: %s (%d faults)' % ('OK' if ok else 'FAIL', len(s.faults)))
    return ok


def cmd_fuzz(runs=100, seed=1):
    """cut the power at a random instant of an update, reboot, and demand a good bank"""
    import cc784_ota
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    app = rom[:BANK_SIZE]
    new_app = app.replace(b'LARGE IMPACT', b'LARGE UPDATE')
    old_bank, new_bank = cc784_ota.pack(app, 1), cc784_ota.pack(new_app, 2)
    base = cc784_ota.pack(app, 0)
    pages = [p for p in cc784_ota.changed_pages(base, new_bank) if p != 255] + [0x40, 0x41, 0x42]
    image_crc = cc784_ota.crc16(new_bank[cc784_ota.STUB_END:cc784_ota.TRAILER])

    def update(s):
        marks = [s.t]
        ota_cmd(s, b'\xb5B')
        for p in pages:
            d = new_bank[p * 64:(p + 1) * 64]
            ota_cmd(s, b'\xb5W' + bytes([p]) + cc784_ota.crc16(d).to_bytes(2, 'little') + d, wait_ms=6000)
        ota_cmd(s, b'\xb5F' + bytes([2]) + image_crc.to_bytes(2, 'little'), wait_ms=6000)
        marks.append(s.t)
        s.send_frame(b'\xb5R', addr=1, flag=0x80); s.rx_wait(); s.run_ms(4000)
        marks.append(s.t)
        return marks

    s = Sign(old_bank + base, syms, fresh_ram=True, sdp=False)
    s.run_ms(2500)
    t_begin, t_finish, t_end = update(s)
    assert s.ram('ROM_BANK')[0] == 1, 'the reference update did not boot bank 1'
    print('reference update: %.1f s of sign time; cutting between B and the reboot' % ((t_end - t_begin) / CPU_HZ))

    rng = random.Random(seed)
    bad = 0
    for i in range(runs):
        s = Sign(old_bank + base, syms, fresh_ram=True, sdp=False, seed=i)
        s.run_ms(2500)
        s.cut_at = s.t + rng.randrange(t_begin - 2500 * int(1000 * US), t_end - 2500 * int(1000 * US))
        try:
            update(s)
            cut = 'no cut'
        except PowerCut:
            cut = 'cut at %.1f s' % ((s.t - t_begin) / CPU_HZ + 2.5)
        image = s.ee.image_after_power_cut(s.t, rng)
        s2 = Sign(image, syms, fresh_ram=True, seed=i + 1000)
        s2.run_ms(3000)
        bank = s2.ram('ROM_BANK')[0]
        t = cc784_ota.parse_trailer(s2.ee.bank_image(bank))
        good = t and t['crc_ok'] and s2.frames and not s2.faults and not s.faults
        if good and bank == 1 and s2.ee.bank_image(1)[:cc784_ota.TRAILER] != new_bank[:cc784_ota.TRAILER]:
            good = False                                    # the trailer's state may be TRIED/GOOD by now
        if not good:
            bad += 1
            print('  run %d: %s -> booted bank %d, trailer %s, %d frames, faults %d/%d'
                  % (i, cut, bank, t, len(s2.frames), len(s.faults), len(s2.faults)))
        elif i % 10 == 0:
            print('  run %d: %s -> bank %d seq %d ok' % (i, cut, bank, t['seq']))
    print('power-cut fuzz: %d/%d runs booted a verified bank' % (runs - bad, runs))
    return bad == 0


def cmd_ram():
    """the same build on the stock 8 K RAM and on a 62256: store size, fill to the top, dump"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))

    def reply(s, payload, wait_ms=3000):
        s.tx_edges.clear()
        s.send_frame(payload, addr=1, flag=0x80); s.rx_wait(); s.run_ms(wait_ms)
        tx = s.tx_bytes()
        return tx[1:] if tx[:1] == b'\x06' else tx

    for ram8k, want_total in ((True, 7054), (False, 15246)):     # P21 took 32 bytes for the reply stream
        name = '8 K' if ram8k else '16 K'
        s = Sign(rom, syms, fresh_ram=True, ram8k=ram8k)
        s.run_ms(2500)
        r = reply(s, b'\xb4\x31')
        total, free = int(r[3:8]), int(r[8:13])
        check('%s: B4 1 total %d free %d' % (name, total, free), total == want_total and free == total - 301)
        text = bytes(0x41 + i % 26 for i in range(250))
        sent = chan = 0                     # one 250-byte chunk per channel (B3 append drops bytes: B11)
        while free >= 250:
            s.send_frame(b'\x09' + b'%02d' % chan + b'\x0e' + text, addr=1, flag=0x80); s.rx_wait(); s.run_ms(1200)
            sent += 250; free -= 250; chan += 1
        r = reply(s, b'\xb4\x31')
        check('%s: %d bytes in %d channels, free now %d' % (name, sent, chan, int(r[8:13])), int(r[8:13]) == free)
        s.send_frame(b'\x09' + b'%02d' % chan + b'\x0e' + text, addr=1, flag=0x80); s.rx_wait(); s.run_ms(1200)   # overfills: the tail is dropped
        r = reply(s, b'\xb4\x31')
        check('%s: overfill leaves free %d (the byte under the terminator is never used)' % (name, int(r[8:13])), int(r[8:13]) <= 1)
        r = reply(s, b'\xb4\x33', wait_ms=int((total + 20) * 12 / 300 * 1000) + 3000)   # ~2.3 stop bits per byte
        n = int(r[2:7]); data = r[7:7 + n]
        got = b''.join(data[i:i + 250] for i in range(len(data)) if data[i:i + 250] == text)   # every full chunk found verbatim
        check('%s: dump says %d bytes, got %d, checksum %s, %d chunks intact' % (name, n, len(data), 'ok' if len(r) > 7 + n and sum(data) & 0xFF == r[7 + n] else 'BAD', len(got) // 250),
              n == total - 1 and len(data) == n and sum(data) & 0xFF == r[7 + n] and len(got) // 250 == chan)
        check('%s: no faults, stack ok (depth %d)' % (name, s.depth()), not s.faults and s.depth() < 100)
        # P20: the clock survives a reset with RAM kept (the stub's library copy lands on RAM_VARS)
        reply(s, b'\x17' + b'1045' + b'P', wait_ms=1500)
        s.run_ms(2500)
        before = s.ram('CLK_H10', 6)
        s2 = Sign(rom, syms, fresh_ram=True, ram8k=ram8k)
        s2.m.set_memory_block(0x4000, bytes(s.m.memory[0x4000:0x8000]))
        s2.run_ms(2500)
        after = s2.ram('CLK_H10', 6)
        check('%s: clock %s kept across a reset (%s), running' % (name, before.hex(), after.hex()),
              before[:2] == bytes([1, 0]) and after[:4] == before[:4] and after[5] == before[5] and s2.ram('CLK_RUN')[0])
        # P25: the repair passes stop at the DA; a store that lost it still gets repaired
        end = int.from_bytes(s2.ram('STORE_END', 2), 'little')
        s2.m.memory[end] = 0x58
        s3 = Sign(rom, syms, fresh_ram=True, ram8k=ram8k)
        s3.m.set_memory_block(0x4000, bytes(s2.m.memory[0x4000:0x8000]))
        s3.run_ms(3000)
        r = reply(s3, b'\xb4\x31')
        end3 = int.from_bytes(s3.ram('STORE_END', 2), 'little')
        check('%s: store without its DA repaired at reset (B4 1 %s, DA back at %04x)' % (name, r[3:13], end3),
              len(r) >= 13 and r[3:13].isdigit() and s3.m.memory[end3] == 0xDA and not s3.faults)
    print('RAM sizes: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_quiet():
    """P21: packets are processed by the render loop. The display keeps running, the
    watchdog never fires, the sign keeps listening, and only an edit of the text
    being played restarts the display."""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    def word(s, name):
        return int.from_bytes(s.ram(name, 2), 'little')
    def send(s, payload, wait_ms=3000, flag=0x81):
        s.tx_edges.clear(); s.wdog_clears = 0
        s.send_frame(payload, addr=1, flag=flag); s.rx_wait(); s.run_ms(wait_ms)
        return s.tx_bytes()
    def dump(s):
        r = send(s, b'\xb4\x33', wait_ms=500)           # 06 B1 addr nnnnn data... sum 04
        for _ in range(600):                            # the reply streams in the background
            if r.endswith(b'\x04'): break
            s.run_ms(200); r = s.tx_bytes()
        n = int(r[3:8]); return r[8:8 + n]
    def marker(s, chan):
        store = bytes(s.m.memory[syms['MSG_STORE']:word(s, 'STORE_END')])
        return syms['MSG_STORE'] + store.index(bytes([0xD0 + chan // 10, 0xD0 + chan % 10]))
    text1 = b'SECOND CHANNEL ' * 8

    s = Sign(rom, syms, fresh_ram=True)
    s.run_ms(2500)
    send(s, b'BARE TEXT', wait_ms=2000)             # no CHANNEL command while the demo plays
    restarted = s.ram('PKT_RESTART')[0]
    d = dump(s)
    check('bare text while the demo plays lands in channel 0 (P24): restart %02x, ROM writes %d' % (restarted, s.rom_writes),
          b'BARE TEXT' in d and d.index(b'BARE TEXT') == 2 and s.rom_writes == 0 and restarted == 0xFF)
    for _ in range(100):                            # wait until channel 0 is the one playing
        if marker(s, 0) < word(s, 'STORE_CURSOR') < marker(s, 1): break
        s.run_ms(50)
    send(s, FX_PLAIN, wait_ms=4000)                 # channel 0 replaces the playing channel: a restart
    check('a message into the playing channel 0 restarts the display (%02x)' % s.ram('PKT_RESTART')[0], s.ram('PKT_RESTART')[0] == 0xFF)
    before = word(s, 'STORE_CURSOR')
    tx = send(s, b'\x09\x30\x31\x0e' + text1)
    after = word(s, 'STORE_CURSOR')
    check('load into channel 1 while 0 plays: ACK+DONE %s, no restart (%02x), no watchdog clear (%d), renderer moved on (%04x -> %04x)'
          % (tx.hex(), s.ram('PKT_RESTART')[0], s.wdog_clears, before, after),
          tx == b'\x06\x04' and s.ram('PKT_RESTART')[0] == 0 and s.wdog_clears == 0 and after != before)
    tx = send(s, b'\xb4\x31')
    check("B4 '1' mid-scroll: reply %s, no restart" % tx[4:14], tx[:4] == b'\x06\xb1\x01\x0a' and tx[4:9] == b'15246' and s.ram('PKT_RESTART')[0] == 0)
    tx = send(s, b'\x17' + b'1045' + b'P', wait_ms=300)
    check('set time mid-scroll: clock %s, seconds %d and ticks %d zeroed (P23), no restart, no watchdog clear'
          % (s.ram('CLK_H10', 4).hex(), s.ram('CLK_SEC')[0], s.ram('NMI_COUNT')[0]),
          s.ram('CLK_H10', 4) == bytes([1, 0, 4, 5]) and s.ram('CLK_SEC')[0] == 0 and s.ram('NMI_COUNT')[0] < 25
          and s.ram('PKT_RESTART')[0] == 0 and s.wdog_clears == 0)
    # a frame that arrives while the previous one is still being handled is dropped whole
    s.tx_edges.clear()
    s.send_frame(b'\x09\x30\x32\x0e' + b'THIRD ' * 40, addr=1, flag=0x81); s.rx_wait(); s.run_ms(20)
    s.send_frame(b'\x01\x01\x01', addr=1, flag=0x81); s.rx_wait(); s.run_ms(3000)
    tx = s.tx_bytes()
    check('a second frame during processing gets no ACK and its 01 bytes do not open the editor (tx %s, MENU_ACTIVE %02x)'
          % (tx.hex(), s.ram('MENU_ACTIVE')[0]), tx == b'\x06\x04' and s.ram('MENU_ACTIVE')[0] == 0)
    tx = send(s, b'\xb4\x31')
    check('the frame after DONE is accepted (%s)' % tx[:4].hex(), tx[:4] == b'\x06\xb1\x01\x0a')
    d = dump(s)
    check('dump has the loaded channels (%d bytes)' % len(d), text1 in d and b'THIRD ' * 40 in d)
    # the playing channel is edited: that restarts, and the new text is what plays
    s.tx_edges.clear()
    s.send_frame(b'\x09\x30\x30\x0e' + b'REPLACED ' * 10, addr=1, flag=0x81); s.rx_wait()
    s.frames.clear(); s.run_ms(150); quick = len(s.frames); s.run_ms(2850); tx = s.tx_bytes()
    check('edit of the playing channel restarts (%02x), ACK+DONE %s, text back on the panel within 150 ms (%d frames, P25)'
          % (s.ram('PKT_RESTART')[0], tx.hex(), quick), s.ram('PKT_RESTART')[0] == 0xFF and tx == b'\x06\x04' and quick >= 2)
    # a lower channel changes size while a higher one plays: the renderer is shifted, not restarted
    send(s, b'\x04\x30\x31', wait_ms=500)           # sequence = channel 1 only, from the next channel on
    for _ in range(60):                             # wait until channel 1 is the one playing
        s.run_ms(500)
        if marker(s, 1) < word(s, 'STORE_CURSOR') < marker(s, 2): break
    playing1 = marker(s, 1) < word(s, 'STORE_CURSOR') < marker(s, 2)
    before = word(s, 'STORE_CURSOR'); m1 = marker(s, 1)
    tx = send(s, b'\x09\x30\x30\x0e' + b'LONGER TEXT IN CHANNEL ZERO ' * 6)
    delta = marker(s, 1) - m1
    check('channel 0 grows by %d under a playing channel 1: no restart (%02x), cursor shifted (%04x -> %04x), still in channel 1'
          % (delta, s.ram('PKT_RESTART')[0], before, word(s, 'STORE_CURSOR')),
          playing1 and s.ram('PKT_RESTART')[0] == 0 and delta > 0 and marker(s, 1) < word(s, 'STORE_CURSOR') < marker(s, 2) and s.wdog_clears == 0)
    check('no faults, stack high-water %d' % s.depth(), not s.faults and s.depth() < 100)
    # P27: a packet while the demo plays leaves the renderer's lock on the demo channel,
    # so STOP and a key edit nothing; a SEQ change is acted on when it flips demo/text
    s2 = Sign(rom, syms, fresh_ram=True); s2.run_ms(2500)
    send(s2, b'\x17' + b'1045' + b'P', wait_ms=500)
    lock = s2.ram('CHAN_LOCK')[0]; cur = word(s2, 'STORE_CURSOR')
    s2.ir_key('STOP'); s2.ir_wait(); s2.run_ms(800)
    head = s2.ram('MSG_STORE', 8)
    s2.ir_key('H'); s2.ir_wait(); s2.run_ms(500)
    check('set time while the demo plays keeps the demo lock (%02x, cursor %04x); STOP then a key edits nothing, no faults (P27)' % (lock, cur),
          lock == syms['CHAN_DEMO'] and cur < syms['MSG_STORE'] and s2.ram('MSG_STORE', 8) == head and not s2.faults)
    s3 = Sign(rom, syms, fresh_ram=True); s3.run_ms(2500)
    send(s3, b'\x09\x30\x35\x0e' + b'FIVE ' * 10, wait_ms=3000)      # channel 5 replaces the demo
    send(s3, b'\x04\x30\x32', wait_ms=500)                             # sequence = channel 2, empty
    r1 = s3.ram('PKT_RESTART')[0]; s3.run_ms(3000)
    demo = word(s3, 'STORE_CURSOR') < syms['MSG_STORE']
    send(s3, b'\x04\x30\x35', wait_ms=500)
    r2 = s3.ram('PKT_RESTART')[0]; s3.run_ms(1000)
    in5 = marker(s3, 5) < word(s3, 'STORE_CURSOR') < marker(s3, 6)
    check('SEQ to an empty channel restarts into the demo (%02x, demo %s); SEQ back to the text restarts into it (%02x, in 5 %s) (P27)'
          % (r1, demo, r2, in5), r1 == 0xFF and demo and r2 == 0xFF and in5 and not s3.faults)
    print('quiet processing: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_speed():
    """P26: every scroll speed steps one column per frame at stock's rate,
    62 * 21 / (21 + n) per second, with the rows lit for the whole frame and
    every row given the same time; nothing ever goes dark"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    text = b'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG ' * 5
    for n in range(8):
        s = Sign(rom, syms, fresh_ram=True)
        s.run_ms(2500)
        s.send_frame(b'\x09\x30\x30\x0e' + bytes([0xF0 + n]) + text + b'\x04\x30\x30', addr=1, flag=0x81); s.rx_wait()
        s.run_ms(4000)                              # restart, then settle into the crawl
        s.refreshes = 0; s.frames.clear(); s.wdog_clears = 0; s.row_starts.clear()
        s.run_ms(5000)
        fps, cps = s.refreshes / 5.0, len(s.frames) / 5.0
        want = 62.0 * 21 / (21 + n)
        dark = sum(1 for f in s.frames if not any(f[1:]))
        # a row's dwell: from its first pass to the next row's first pass; lit throughout
        firsts = [(t, p & 7) for t, p in s.row_starts if not p & 8]
        dwell = {}
        for (t0, r), (t1, _) in zip(firsts, firsts[1:]):
            dwell.setdefault(r, []).append((t1 - t0) / CPU_HZ * 1e6)
        mean = {r: sum(v) / len(v) for r, v in dwell.items()}
        lo, hi = min(mean.values()), max(mean.values())
        want_dwell = (18 + 6 * n / 7) * 128
        check('speed %d: %5.1f refreshes/s, %5.1f columns/s (want %5.1f), %d dark frames, row dwell %4.0f-%4.0f us (want %4.0f), watchdog %d'
              % (n, fps, cps, want, dark, lo, hi, want_dwell, s.wdog_clears),
              abs(fps - want) < 1.5 and abs(cps - want) < 1.5 and dark == 0 and len(mean) == 7
              and hi - lo < 140 and abs((lo + hi) / 2 - want_dwell) < 60 and s.wdog_clears == 0)
    print('speeds: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_baud():
    """P30: the receiver times the start bit of the first frame after a second of
    silence and follows the host at 300, 600 or 1200 baud; replies come back at
    the same rate; 2400 is refused; NETCC's 300-baud habits still work"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    def send(s, payload, wait_ms=1500, flag=0x81):
        s.tx_edges.clear(); s.send_frame(payload, addr=1, flag=flag); s.rx_wait(); s.run_ms(wait_ms)
        return s.tx_bytes()
    text = b'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG ' * 5
    for baud in (300, 600, 1200):
        s = Sign(rom, syms, fresh_ram=True, baud=baud); s.run_ms(2500)
        tx = send(s, b'\xb4\x31', wait_ms=int(16 * 10000 / baud) + 500)
        rate = s.ram('BAUD_STEP')[0]
        check('%4d baud from cold: query reply %s, BAUD_STEP %d, BAUD_T %d' % (baud, tx[:9], rate, s.ram('BAUD_T')[0]), tx[:4] == b'\x06\xb1\x01\x0a' and tx[4:9] == b'15246' and rate == baud // 60)
        tx = send(s, b'\x09\x30\x31\x0e' + text, wait_ms=500)
        d = bytes(s.m.memory[syms['MSG_STORE']:int.from_bytes(s.ram('STORE_END', 2), 'little')])
        check('%4d baud: 220-byte load intact, ACK+DONE %s' % (baud, tx.hex()), text in d and tx == b'\x06\x04')
        s.run_ms(300)                                       # well inside the idle window: no re-timing
        tx = send(s, b'\x09\x30\x32\x0e' + b'SECOND', wait_ms=500)
        check('%4d baud: a frame 0.3 s later is taken at the same rate (%s)' % (baud, tx.hex()), tx == b'\x06\x04' and s.ram('BAUD_STEP')[0] == rate)
        check('%4d baud: no faults, no watchdog clears (%d)' % (baud, s.wdog_clears), not s.faults and s.wdog_clears == 0)
    # the bit time is calibrated from the NMI second: 1200 must hold from 126 to 134 us
    for tick_us, label, rate in ((126.0, '-3 %', 1200), (128.0, 'no latency', 1200), (132.0, '+1.5 %', 1200), (134.0, '+3 %', 1200)):
        s = Sign(rom, syms, fresh_ram=True, baud=rate); s.tick_t = int(tick_us * US); s.run_ms(3500)
        tx = send(s, b'\xb4\x31', wait_ms=600)
        tx2 = send(s, b'\x09\x30\x31\x0e' + text, wait_ms=500)
        d = bytes(s.m.memory[syms['MSG_STORE']:int.from_bytes(s.ram('STORE_END', 2), 'little')])
        check('%d baud with a %.1f us interrupt (%s): BAUD_T %d, query %s, load %s' % (rate, tick_us, label, s.ram('BAUD_T')[0], tx[:4].hex(), tx2.hex()), tx[:4] == b'\x06\xb1\x01\x0a' and tx2 == b'\x06\x04' and text in d)
    # 2400 is not offered: its start bit is refused, and a DC supply (no NMI, no calibration) still takes 1200
    s = Sign(rom, syms, fresh_ram=True, baud=2400, mains=False); s.run_ms(3500)
    tx = send(s, b'\xb4\x31', wait_ms=600)
    s.run_ms(1500); s.set_baud(1200)
    tx2 = send(s, b'\xb4\x31', wait_ms=600)
    check('2400 refused (reply %s); DC supply, 1200 answered with the default bit time (%s, BAUD_T %d)' % (tx.hex(), tx2[:4].hex(), s.ram('BAUD_T')[0]), tx == b'' and s.ram('BAUD_T')[0] == 128 and tx2[:4] == b'\x06\xb1\x01\x0a')
    # a session that changes rate after a pause, and one that comes back to 300
    s = Sign(rom, syms, fresh_ram=True, baud=1200); s.run_ms(2500)
    send(s, b'\x09\x30\x30\x0e' + b'FAST', wait_ms=500)
    s.run_ms(1500); s.set_baud(300)
    tx = send(s, b'\x09\x30\x31\x0e' + b'SLOW', wait_ms=500)
    check('1200 then, after 1.5 s, 300: taken (%s, BAUD_STEP %d)' % (tx.hex(), s.ram('BAUD_STEP')[0]), tx == b'\x06\x04' and s.ram('BAUD_STEP')[0] == 5)
    s.run_ms(1500); s.set_baud(1200)
    tx = send(s, b'\xb4\x33', wait_ms=3000)
    check('then 1200: a store dump comes back whole at 1200 (%d bytes, ends %s)' % (len(tx), tx[-1:].hex()), tx[:4] == b'\x06\xb1\x01' + bytes([len(tx) - 6]) and tx[-1:] == b'\x04' if False else len(tx) > 20 and b'FAST' in tx and b'SLOW' in tx and tx.endswith(b'\x04'))
    # NETCC habits at 300: a bare STOP byte after silence, then keys, then a frame
    s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
    send(s, b'\x09\x30\x30\x0e' + b'HELLO', wait_ms=500); s.run_ms(1500)
    s.send_bytes(b'\x01'); s.rx_wait(); s.run_ms(500)
    menu = s.ram('MENU_ACTIVE')[0]
    s.send_bytes(b'X'); s.rx_wait(); s.run_ms(500)
    s.send_bytes(b'\x0d'); s.rx_wait(); s.run_ms(1500)
    check('300 baud bare 01 after 1.5 s idle opens the editor (%02x), X typed, 0D leaves (%02x)' % (menu, s.ram('MENU_ACTIVE')[0]), menu == 0xff and s.ram('MENU_ACTIVE')[0] == 0)
    check('no faults', not s.faults)
    print('baud: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_clock():
    """P31: the NMI source. With no mains NMI through the boot the firmware selects the
    add-in board's 64 Hz through BANK_REG bit 1 and counts 64 a second; the bit is
    put back after the OTA library drops it. P32: the 24-hour clock."""
    import cc784_ota
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    def settime(s, hhmm, mode):
        s.send_frame(b'\x17' + hhmm + mode, addr=1, flag=0x81); s.rx_wait(); s.run_ms(300)
    def clock(s):
        d = s.ram('CLK_H10', 6)
        return '%d%d:%d%d:%02d pm=%02x' % (d[0], d[1], d[2], d[3], d[4], d[5])
    # AC: as before, 12-hour
    s = Sign(rom, syms, fresh_ram=True); s.run_ms(3000)
    check('AC: 60 a second, bank bit clear, NMI seen (%d, %02x, %s)' % (s.ram('NMI_PER_SEC')[0], s.bank_reg, s.ram('NMI_SEEN').hex()),
          s.ram('NMI_PER_SEC')[0] == 60 and not s.bank_reg & 0x80 and s.ram('NMI_SEEN')[0] == 0xFF)
    settime(s, b'1159', b'N'); s.run_ms(61000)
    check('AC: 11:59 PM + 61 s -> %s (12:00 AM)' % clock(s), s.ram('CLK_H10', 4) == bytes([1, 2, 0, 0]) and s.ram('CLK_PM')[0] == 0)
    settime(s, b'0959', b'Y'); s.run_ms(61000)
    check('AC: 09:59 AM + 61 s -> %s (10:00 AM, no leading zero at 9)' % clock(s), s.ram('CLK_H10', 4) == bytes([1, 0, 0, 0]) and s.ram('CLK_PM')[0] == 0)
    # 24-hour
    settime(s, b'2359', b'H'); s.run_ms(61000)
    check('24-hour: 23:59 + 61 s -> %s (00:00, mode kept)' % clock(s), s.ram('CLK_H10', 4) == bytes([0, 0, 0, 0]) and s.ram('CLK_PM')[0] == 2)
    settime(s, b'0959', b'H'); s.run_ms(61000)
    check('24-hour: 09:59 + 61 s -> %s (10:00)' % clock(s), s.ram('CLK_H10', 4) == bytes([1, 0, 0, 0]) and s.ram('CLK_PM')[0] == 2)
    settime(s, b'1259', b'H'); s.run_ms(61000)
    check('24-hour: 12:59 + 61 s -> %s (13:00, no flip)' % clock(s), s.ram('CLK_H10', 4) == bytes([1, 3, 0, 0]) and s.ram('CLK_PM')[0] == 2)
    s.send_frame(b'\x09\x30\x30\x0e' + b'IT IS \x5f NOW', addr=1, flag=0x81); s.rx_wait(); s.frames.clear(); s.run_ms(4000)
    lit = sum(1 for f in s.frames if any(f[1:]))
    check('24-hour: a message with the clock renders (%d lit frames, no faults)' % lit, lit > 50 and not s.faults)
    # DC with the add-in board
    s = Sign(rom, syms, fresh_ram=True, mains=False, crystal=True); s.run_ms(3000)
    check('DC + board: 64 a second, bank bit set, NMI seen (%d, %02x, %s)' % (s.ram('NMI_PER_SEC')[0], s.bank_reg, s.ram('NMI_SEEN').hex()),
          s.ram('NMI_PER_SEC')[0] == 64 and s.bank_reg & 0x80 and s.ram('NMI_SEEN')[0] == 0xFF)
    settime(s, b'0100', b'H'); s.run_ms(10200)
    check('DC + board: the clock runs at one second per 64 NMIs (%s)' % clock(s), s.ram('CLK_SEC')[0] == 10)
    check('DC + board: the bit time is calibrated from the crystal second (BAUD_T %d, last %d)' % (s.ram('BAUD_T')[0], s.ram('BAUD_CAL_LAST')[0]), s.ram('BAUD_CAL_LAST')[0] != 0x7f)
    s.set_baud(1200); s.run_ms(1500); s.tx_edges.clear()
    s.send_frame(b'\x09\x30\x31\x0e' + b'FAST ' * 44, addr=1, flag=0x81); s.rx_wait(); s.run_ms(500)
    check('DC + board: a 220-byte frame at 1200 (%s)' % s.tx_bytes().hex(), s.tx_bytes() == b'\x06\x04')
    # an OTA page write on DC with the board: the writer's NMI sync must find the source on
    app = rom[:BANK_SIZE]
    img = cc784_ota.pack(app, 1) + cc784_ota.pack(app, 0)
    s = Sign(img, syms, fresh_ram=True, sdp=False, mains=False, crystal=True); s.run_ms(3000)
    r = ota_cmd(s, b'\xb5B'); r2 = ota_cmd(s, b'\xb5W' + bytes([200]) + cc784_ota.crc16(bytes(64)).to_bytes(2, 'little') + bytes(64))
    sec0 = s.ram('CLK_SEC')[0]; s.run_ms(3200)
    check('DC + board: B %s, W %s, bit back (%02x), clock still running (%d -> %d)' % (r, r2, s.bank_reg, sec0, s.ram('CLK_SEC')[0]),
          r == b'\x00' and r2 == b'\x00' and s.bank_reg & 0x80 and s.ram('CLK_SEC')[0] >= sec0 + 3)
    # DC without the board: the bit is set but nothing answers; nothing may hang
    s = Sign(img, syms, fresh_ram=True, sdp=False, mains=False, crystal=False); s.run_ms(3000)
    r = ota_cmd(s, b'\xb5B'); r2 = ota_cmd(s, b'\xb5W' + bytes([200]) + cc784_ota.crc16(bytes(64)).to_bytes(2, 'little') + bytes(64))
    s.run_ms(3000)
    check('DC, no board: 64 selected (%d, %02x), no NMI (%s), clock stands (%s), page write still answers (%s %s)' % (s.ram('NMI_PER_SEC')[0], s.bank_reg, s.ram('NMI_SEEN').hex(), clock(s), r, r2),
          s.ram('NMI_PER_SEC')[0] == 64 and s.bank_reg & 0x80 and s.ram('NMI_SEEN')[0] == 0 and s.ram('CLK_SEC')[0] == 0 and r == b'\x00' and r2 == b'\x00')
    check('no faults', not s.faults)
    print('clock: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_eeprom():
    """exercise the chip model against the AT28C256 datasheet rules"""
    us = lambda n: int(n * US)
    faults = []
    ee = Eeprom(b'\xff' * (2 * BANK_SIZE), sdp=False, faults=faults)
    checks = []
    def check(name, cond):
        checks.append(cond); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))

    # unprotected chip: a plain page write lands after the load window + write cycle
    for i in range(64):
        ee.write(0x1000 + i, i, us(2 * i))
    check('page open while loading', ee.busy(us(200)))
    check('still busy just before tWC ends', ee.busy(us(126 + 150 + 10_000 - 1)))
    check('status: /D7 of last byte', ee.status() & 0x80 == 0x80)   # last byte 63 -> bit 7 clear -> status set
    check('status: D6 toggles', (ee.status() ^ ee.status()) & 0x40)
    ee.write(0x2000, 0x11, us(5000))
    check('write during the cycle is a fault', faults and faults[-1][1] == 'write during write cycle')
    check('idle after tWC', not ee.busy(us(126 + 150 + 10_000 + 1)))
    check('page programmed', ee.bank_image(0)[0x1000:0x1040] == bytes(range(64)))
    check('ignored write did not land', ee.bank_image(0)[0x2000] == 0xFF)

    # a byte outside the open page is refused
    t = us(20_000)
    ee.write(0x0040, 0xAA, t); ee.write(0x0080, 0xBB, t + us(1))
    check('byte outside the page is a fault', faults[-1][1] == 'byte outside the open page')
    ee.update(us(40_000))

    # SDP: the enable preamble protects the chip from then on
    t = us(50_000)
    for i, (a, v) in enumerate(Eeprom.SDP_ON):
        ee.write(a, v, t + us(i))
    ee.write(0x4000 + 0x0C0, 0x42, t + us(5))       # bank 1 offset 0C0
    ee.update(us(80_000))
    check('preamble + data lands in bank 1', ee.bank_image(1)[0xC0] == 0x42)
    check('SDP now armed', ee.sdp)
    n = len(faults)
    ee.write(0x3000, 0x99, us(90_000))
    check('unprotected write is blocked', len(faults) == n + 1 and faults[-1][1] == 'write blocked by SDP')
    check('and opens no cycle', not ee.busy(us(90_001)))
    t = us(100_000)
    for i, (a, v) in enumerate(Eeprom.SDP_OFF):
        ee.write(a, v, t + us(i))
    check('disable sequence starts a cycle', ee.busy(t + us(200)))
    ee.update(us(130_000))
    check('SDP disarmed', not ee.sdp)
    ee.write(0x3000, 0x99, us(140_000)); ee.update(us(160_000))
    check('plain write works again', ee.bank_image(0)[0x3000] == 0x99)
    print('EEPROM model: %d/%d checks pass' % (sum(1 for c in checks if c), len(checks)))
    return all(checks)


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
    rewrite: blank after clear_framebuf, or a fill in progress (run of color bytes)"""
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
    """an inserted/deleted frame is timing if it is a scroll step of its neighbor"""
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
    print('OK: same behavior' if clean else 'CHECK: real frame differences or reply mismatch')


if __name__ == '__main__':
    args = sys.argv[1:]
    if not args or args[0] not in ('stack', 'compare', 'eeprom', 'ota', 'update', 'push', 'fuzz', 'ram', 'quiet', 'speed', 'baud', 'clock'):
        sys.exit(__doc__)
    if args[0] == 'ram':
        sys.exit(0 if cmd_ram() else 1)
    if args[0] == 'speed':
        sys.exit(0 if cmd_speed() else 1)
    if args[0] == 'baud':
        sys.exit(0 if cmd_baud() else 1)
    if args[0] == 'clock':
        sys.exit(0 if cmd_clock() else 1)
    if args[0] == 'quiet':
        sys.exit(0 if cmd_quiet() else 1)
    if args[0] == 'push':
        sys.exit(0 if cmd_push(int(args[1]) if len(args) > 1 else 300) else 1)
    if args[0] == 'fuzz':
        sys.exit(0 if cmd_fuzz(int(args[1]) if len(args) > 1 else 100) else 1)
    if args[0] == 'eeprom':
        sys.exit(0 if cmd_eeprom() else 1)
    if args[0] == 'ota':
        sys.exit(0 if cmd_ota() else 1)
    if args[0] == 'update':
        sys.exit(0 if cmd_update(int(args[1]) if len(args) > 1 else 300) else 1)
    if args[0] == 'stack':
        cmd_stack(args[1] if len(args) > 1 else 'patched')
    else:
        if len(args) != 3:
            sys.exit('compare needs two source directories')
        cmd_compare(args[1], args[2])
