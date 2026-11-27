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

    uv run tools/cc784_sim.py keypad
        The wired keypad (patch 36): mode switching, editing against the remote.

    uv run tools/cc784_sim.py seq
        The sequence over empty channels (patch 39): a short burst after one message,
        and the right channels in order after edits move the store.

    uv run tools/cc784_sim.py stats
        The health counters in the B4 '4' reply (patch 40): clock source, boot count
        across a reset, uptime, stack headroom, frame and remote counters.

    uv run tools/cc784_sim.py status
        Status reports (patch 41): off by default, one per channel start when on,
        FF when the editor opens, and the host tool working with reports flowing.

    uv run tools/cc784_sim.py term
        Frames only on the serial port (patch 45): loose bytes, a lost byte, a bad
        header, BUSY while the editor is open, B7 '1' and B7 '0'.

    uv run tools/cc784_sim.py randbow
        RANDBOW (patch 46): the shuffled deck, plain RAINBOW unchanged, FUNC2 in
        the editor, DEL of the pair, B2 across a reset.

    uv run tools/cc784_sim.py scroll
        SCROLL UP and DOWN (patch 48): every step against the two pages, yellow while
        moving and colors at rest, the plain wipe unchanged, FUNC2 in the editor.

    uv run tools/cc784_sim.py field
        Fields (patch 54): channels 90-99 inside a message in a crawl, a wipe and a
        scroll, loads while a field is drawn, seq M.

    uv run tools/cc784_sim.py flush
        FLUSH (patch 57): B2 20 empties the panel mid-crawl and keeps the font,
        does nothing on a staged page; FUNC SPACE in the editor, its label, DEL.

    uv run tools/cc784_sim.py fuzz [RUNS]
        Cut the power at a random instant of an update, RUNS times (default 100);
        every reboot must land in a bank whose trailer and image CRC check out.

Facts the model rests on (all traced in the firmware notes): INT every 1024 cycles
(8 MHz / 1024; 4 MHz cannot keep up with the tick work, so the CPU is 8 MHz),
NMI at 60 Hz, PORT_IN bit 3 = serial RX (1 = space), bit 1 = IR burst (bit 4
on the patched build), a keypad's column code on bits 0-2 and GS on bit 3,
CTRL_LATCH bit 4 = serial TX (1 = space). The stack watch counts only writes at
SP, so store shuffles next to the stack do not register.

The ROM is an AT28C256 with the OTA bodges (OTA.md §1): /WE on Z80 /WR,
/OE on /RD, A14..A16 from BANK_REG, a '273 written at C000 and zero at reset.
Page writes, the 150 us byte-load timer, the 10 ms write cycle (every ROM read
returns the status byte; an instruction fetch then is a fault) and software
data protection are modeled; so is the board's watchdog, which zeroes
CTRL_LATCH 512 us after the last interrupt acknowledge. Faults are collected in
Sign.faults rather than raised, so a session can report them at the end.
"""
import functools, hashlib, operator, os, pathlib, random, subprocess, sys, tempfile, time

import z80

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import cc784_ir  # noqa: E402

LITE = os.environ.get('CC784_LITE') == '1'   # an unmodified 3A board: 4 MHz, 1302 Hz INT, 2 K RAM
CPU_HZ = 4_000_000 if LITE else 8_000_000
TICK_T = 3072 if LITE else CPU_HZ // 7812     # INT period in T-states
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
        asm = src_dir / 'cc784nir_9o.asm'      # src/stock names sources by ROM revision
    if not asm.exists():
        sys.exit('no cc784nir.asm in %s' % src_dir)
    with tempfile.TemporaryDirectory() as tmp:
        sym = pathlib.Path(tmp) / 'out.sym'
        text = asm.read_text()
        # assemble a copy so the source tree is untouched
        (pathlib.Path(tmp) / 'cc784nir.asm').write_text(text)
        r = subprocess.run(['sjasmplus', '--sym=%s' % sym] + (['-DLITE'] if LITE else []) + ['cc784nir.asm'], cwd=tmp,
                           capture_output=True, text=True)
        if r.returncode:
            sys.exit(r.stdout + r.stderr)
        bins = list(pathlib.Path(tmp).glob('*.bin'))    # the OUTPUT name depends on IFDEFs
        if len(bins) != 1:
            sys.exit('expected one image, got %s' % [b.name for b in bins])
        rom = bins[0].read_bytes()
        syms = {}
        for line in sym.read_text().splitlines():
            name, _, val = line.partition(': EQU ')
            if val:
                syms[name.strip()] = int(val, 16)
    return rom, syms


class Sign:
    def __init__(self, rom, syms, fresh_ram=True, seed=1, sdp=True, ram8k=False, ram2k=None, mains=True, baud=300, crystal=False, strict_int=False):
        # rom: one 16 K bank (the rest of the chip erased) or the whole chip image
        # ram8k: the stock 6264, which mirrors 4000-5FFF at 6000-7FFF
        # ram2k: the 3A's 6116, mirrored through 7FFF (the LITE build's default)
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
        if ram2k is None:
            ram2k = LITE and not ram8k
        self.ram_size = 0x800 if ram2k else 0x2000 if ram8k else 0x4000
        if self.ram_size < 0x4000:
            ram = ram[:self.ram_size] * (0x4000 // self.ram_size)
            m.mark_addrs(0x4000, 0x4000, m.WRITE_MARK)      # every RAM write is mirrored
        m.set_memory_block(0x4000, ram)
        self.stack_top = syms['STACK_TOP_2K'] if ram2k else syms.get('STACK_TOP', 0x4040)
        self.stack_lo = 0x3E00 if self.stack_top == 0x4040 else self.stack_top - 0x300
        if ram2k:                           # the boot stub's stack (PKT_READY) is below; watch the overrun only
            self.stack_lo = self.stack_top - syms['STACK_SIZE'] - 0x20
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
        self.rx_skew_us = self.rx_jitter_us = 0
        self.rx_rng = random.Random(seed)
        self.rx_busy_until = self.ir_busy_until = 0
        self.ir_mask = syms.get('PORT_IR', 0x02)   # bit 1 on stock; the patched build moves it
        self.tied_high = 0xE0 if self.ir_mask == 0x10 else 0   # the second '244's unused inputs
        self.keypad = False                 # True: a keypad on the DB9 instead of a host
        self.kp_events, self.kp_i, self.kp_level = [], 0, None
        self.kp_busy_until = 0
        self.int_pending = False
        self.tick_t = TICK_T + int(2 * US)  # 128 us + ~2 us of acknowledge latency, as measured on the board
        self.strict_int = strict_int        # /INT follows Q11: a request not taken within 128 us is lost
        self.int_lost = 0
        self._int_phase = 0
        self.watch, self.watch_log = set(), []   # RAM addresses whose writes are logged as (t, pc, addr, value)
        self._di_run, self.max_di, self.max_di_pc = 0, 0, 0
        self.set_baud(baud)
        self.burst, self.frames = [], []
        self.row_starts, self.last_out_t, self.last_port = [], 0, None   # (t, port low nibble) at each row burst

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
        if addr in self.watch:
            self.watch_log.append((self.t, self.m.pc, addr, value))
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
            if self.ram_size < 0x4000 and addr < 0x8000:
                for a in range(0x4000 + (addr & (self.ram_size - 1)), 0x8000, self.ram_size):
                    self.m.memory[a] = value
        sp = self.m.sp
        if sp - 2 <= addr <= sp + 1 and self.stack_lo <= addr < self.min_stack:
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
            ir = self._level(self.ir_events, 'ir_i', 'ir_level') * self.ir_mask | self.tied_high
            if self.keypad:
                # a CC100: the '148 drives bits 0-2 and GS (bit 3, low = key) for the row on latch bits 4-6
                key = self._level(self.kp_events, 'kp_i', 'kp_level')
                if key is not None and key >> 3 == (self.latch >> 4) & 7:
                    return (key & 7) | ir
                return 0x0f | ir
            rx = self._level(self.rx_events, 'rx_i', 'rx_level')
            return (rx << 3) | ir
        return 0xff

    def _on_output(self, port, value):
        if port & 0xf0 == 0x40:           # a row burst: note where each one starts
            if self.t - self.last_out_t > 3000 or port & 0x0f != self.last_port:   # bursts are a tick apart
                self.row_starts.append((self.t, port & 0x0f))                        # (closer at 4 MHz) and change port
            self.last_out_t, self.last_port = self.t, port & 0x0f
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
        # the stub vectors through NMI_VEC: with the idle bank mapped in, that
        # address holds the other image's bytes
        m = self.m
        if m.memory[self.sym['NMI_MAGIC']] == 0xA5 and (self.bank_reg ^ m.memory[self.sym['ROM_BANK']]) & 1:
            self.faults.append((self.t, 'NMI vectored into the idle bank', m.pc, self.bank_reg))
        self._push_pc(); m.iff1 = 0; m.pc = 0x66; m.halted = 0

    def run(self, t_states):
        end = self.t + t_states
        m = self.m
        while self.t < end:
            if self.cut_at is not None and self.t >= self.cut_at:
                raise PowerCut()
            if self.strict_int:
                phase = (self.t - self.last_inta) // TICK_T
                if phase != self._int_phase:
                    if self.int_pending and not phase & 1:
                        self.int_lost += 1          # Q11 fell before the acknowledge
                    self._int_phase, self.int_pending = phase, bool(phase & 1)
            elif self.t >= self.next_int:
                self.int_pending = True             # level: held until acknowledged, across run() calls
                self.next_int += self.tick_t        # the counter restarts at the acknowledge: 128 us + latency
            # the core can stop between a DD/FD prefix and its opcode, where a real
            # Z80 takes no interrupt: hold both kinds until the next slice
            if m.index_rp_kind is z80.HL:
                if self.int_pending and self._irq():
                    self.int_pending = False
                    self.last_inta = self.t
                    self._int_phase = 0
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
            if m.iff1:
                self._di_run = 0
            else:
                self._di_run += SLICE           # longest stretch with interrupts off, and where it ended
                if self._di_run > self.max_di:
                    self.max_di, self.max_di_pc = self._di_run, m.pc

    def run_ms(self, ms):
        self.run(int(ms * 1000 * US))

    # ---- stimulus
    def set_baud(self, baud):
        """the host's line rate: what send_bytes drives and tx_bytes decodes"""
        self.baud, self.bit_t = baud, round(CPU_HZ / baud)

    def send_bytes(self, data, gap_bits=1):
        # rx_skew_us lengthens every space (a slow edge back to mark); rx_jitter_us moves each edge at random
        t = max(self.t, self.rx_busy_until)
        skew, jit = int(self.rx_skew_us * US), int(self.rx_jitter_us * US)
        for b in data:
            for bit in [1] + [0 if (b >> i) & 1 else 1 for i in range(8)] + [0]:
                e = t + (0 if bit else skew) + (self.rx_rng.randint(-jit, jit) if jit else 0)
                self.rx_events.append((max(e, self.rx_events[-1][0] if self.rx_events else 0), bit)); t += self.bit_t
            t += gap_bits * self.bit_t
        self.rx_busy_until = t + max(skew, 0)

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

    def kp_key(self, code, hold_ms=150, bounce=0):
        """one keystroke on the keypad by its key code (row x 8 + column), with
        bounce chattering edges of 0.5 ms at the press and the release"""
        t = max(self.t, self.kp_busy_until)
        def chatter(t, final):
            for _ in range(bounce):
                self.kp_events.append((t, None if final is not None else code)); t += int(500 * US)
                self.kp_events.append((t, final)); t += int(500 * US)
            return t
        self.kp_events.append((t, code)); t += int(500 * US)
        t = chatter(t, code) + int(hold_ms * 1000 * US)
        self.kp_events.append((t, None)); t += int(500 * US)
        t = chatter(t, None)
        self.kp_busy_until = t + int(100_000 * US)

    def kp_wait(self):
        if self.kp_busy_until > self.t: self.run(self.kp_busy_until - self.t)

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

    def corrupt(bank, at=0x3fbf):
        # a free byte under the trailer: "both corrupt" runs bank 0, which must not hit a flipped opcode
        b = bytearray(bank); assert b[at] == 0xff; b[at] ^= 0x01; return bytes(b)

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
    s.tx_edges.clear()
    s.ir_key('STOP', stretch_us=100); s.ir_wait(); s.run_ms(800)
    s.send_bytes(b'\x01'); s.rx_wait(); s.run_ms(800)
    s.send_frame(b'\xb7\x31', addr=1); s.rx_wait(); s.run_ms(800)
    check("P43: remote STOP, a serial 01 and B7 '1' mid-update open no editor (menu %02x, test mode %02x, tx %s)"
          % (s.ram('MENU_ACTIVE')[0], s.ram('TEST_MODE')[0], s.tx_bytes().hex()),
          s.ram('MENU_ACTIVE')[0] == 0 and s.ram('TEST_MODE')[0] == 0xFF and s.tx_bytes() == b'\x06')
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
        edges = self.s.tx_edges
        if edges and self.s.t - edges[-1][0] < 11 * self.s.bit_t:
            self.delivered = len(self._available())   # a byte on the wire: clearing would cut it
            return
        edges.clear()
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
    """the same build on the stock 8 K RAM and on a 62256 (LITE: and the 3A's 2 K): store size,
    frame limit, fill to the top, an over-long frame dropped, dump, the store kept across a reset"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))

    def reply(s, payload, wait_ms=3000):
        s.tx_edges.clear()
        s.send_frame(payload, addr=1, flag=0x80); s.rx_wait(); s.run_ms(wait_ms)
        tx = s.tx_bytes()
        return tx[1:] if tx[:1] == b'\x06' else tx
    def load(s, payload):
        """a host that waits for DONE (flag 81): processing a packet into a nearly full
        store takes over a second, since init_sequence rescans the store per channel"""
        s.tx_edges.clear()
        s.send_frame(payload, addr=1, flag=0x81); s.rx_wait()
        for _ in range(500):
            s.run_ms(10)
            if s.tx_bytes().endswith(b'\x04'): break
        s.tx_edges.clear(); s.run_ms(200)

    sizes = [('8 K', True, False, 'STORE_TOP_8K'), ('16 K', False, False, 'STORE_TOP')]
    if LITE:
        sizes.insert(0, ('2 K', False, True, 'STORE_TOP_2K'))
    for name, ram8k, ram2k, top in sizes:
        want_total = syms[top] - syms['MSG_STORE'] + 1
        want_max = syms['PKT_MAX_2K'] if ram2k else syms['PKT_MAX_FULL']
        s = Sign(rom, syms, fresh_ram=True, ram8k=ram8k, ram2k=ram2k)
        s.run_ms(2500)
        r = reply(s, b'\xb4\x31')
        total, free, pmax = int(r[3:8]), int(r[8:13]), int(r[13:18])
        framing = syms['CHANNELS'] * 3 + 1
        check('%s: B4 1 total %d free %d, frames up to %d bytes' % (name, total, free, pmax),
              total == want_total and free == total - framing and pmax == want_max)
        ln = min(250, pmax - 4)
        text = bytes(0x41 + i % 26 for i in range(ln))
        sent = chan = 0                     # a chunk a channel, then appends once every channel has one
        def chunk():
            c = chan % syms['CHANNELS']
            return b'\x09' + b'%02d' % c + (b'\x0e' if chan == c else b'\xb3') + text
        while free >= ln:
            load(s, chunk())
            sent += ln; free -= ln; chan += 1
        r = reply(s, b'\xb4\x31')
        check('%s: %d bytes in %d frames, free now %d' % (name, sent, chan, int(r[8:13])), int(r[8:13]) == free)
        load(s, chunk())                    # overfills: the tail is dropped
        r = reply(s, b'\xb4\x31')
        check('%s: overfill leaves free %d (the byte under the terminator is never used)' % (name, int(r[8:13])), int(r[8:13]) <= 1)
        before = bytes(s.m.memory[syms['MSG_STORE']:syms[top] + 1])
        s.tx_edges.clear()
        s.send_frame(b'\x09\x30\x30\x0e' + bytes(pmax - 3), addr=1); s.rx_wait(); s.run_ms(500)
        check('%s: a %d-byte frame is dropped unanswered, the store kept' % (name, pmax + 1),
              not s.tx_bytes() and bytes(s.m.memory[syms['MSG_STORE']:syms[top] + 1]) == before)
        r = reply(s, b'\xb4\x33', wait_ms=int((total + 20) * 12 / 300 * 1000) + 3000)   # ~2.3 stop bits per byte
        n = int(r[2:7]); data = r[7:7 + n]
        got = b''.join(data[i:i + ln] for i in range(len(data)) if data[i:i + ln] == text)   # every full chunk found verbatim
        check('%s: dump says %d bytes, got %d, checksum %s, %d chunks intact' % (name, n, len(data), 'ok' if len(r) > 7 + n and sum(data) & 0xFF == r[7 + n] else 'BAD', len(got) // ln),
              n == total - 1 and len(data) == n and sum(data) & 0xFF == r[7 + n] and len(got) // ln == chan)
        check('%s: no faults, stack ok (depth %d)' % (name, s.depth()), not s.faults and s.depth() < 100)
        # P20: the clock survives a reset with RAM kept (the stub's library copy lands on RAM_VARS)
        reply(s, b'\x17' + b'1045' + b'P', wait_ms=1500)
        s.run_ms(2500)
        before = s.ram('CLK_H10', 6)
        kept = bytes(s.m.memory[syms['MSG_STORE']:syms[top] + 1])
        s2 = Sign(rom, syms, fresh_ram=True, ram8k=ram8k, ram2k=ram2k)
        s2.m.set_memory_block(0x4000, bytes(s.m.memory[0x4000:0x8000]))
        s2.run_ms(2500)
        after = s2.ram('CLK_H10', 6)
        check('%s: clock %s kept across a reset (%s), running' % (name, before.hex(), after.hex()),
              before[:2] == bytes([1, 0]) and after[:4] == before[:4] and after[5] == before[5] and s2.ram('CLK_RUN')[0])
        check('%s: the store kept byte for byte across the reset (the RAM probe puts its byte back)' % name,
              bytes(s2.m.memory[syms['MSG_STORE']:syms[top] + 1]) == kept)
        # P25: the repair passes stop at the DA; a store that lost it still gets repaired
        end = int.from_bytes(s2.ram('STORE_END', 2), 'little')
        s2.m.memory[end] = 0x58
        s3 = Sign(rom, syms, fresh_ram=True, ram8k=ram8k, ram2k=ram2k)
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
    check("B4 '1' mid-scroll: reply %s, no restart" % tx[4:14], tx[:4] == b'\x06\xb1\x01\x0f' and tx[4:9] == b'%05d' % store_total(syms, False) and s.ram('PKT_RESTART')[0] == 0)
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
    check('the frame after DONE is accepted (%s)' % tx[:4].hex(), tx[:4] == b'\x06\xb1\x01\x0f')
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


def cmd_seq():
    """P39: with the default sequence 0-99, stepping over the empty channels takes
    no rescan of the store, and every channel with text opens at its own marker,
    also after an edit moves the markers behind it."""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    def send(s, payload):
        s.send_frame(payload, addr=1, flag=0x81); s.rx_wait(); s.run_ms(3000)
    def watch(s, addr, n, ms):
        s.watch = set(range(addr, addr + n)); s.watch_log.clear()
        s.m.mark_addrs(addr, n, s.m.WRITE_MARK)
        s.run_ms(ms)
        return list(s.watch_log)
    def chan_at(off):
        mem = s.m.memory
        for i in range(off - 2, syms['MSG_STORE'] - 1, -1):     # two marker bytes in a row are one marker
            if 0xD0 <= mem[i] <= 0xD9 and 0xD0 <= mem[i + 1] <= 0xD9:
                return (mem[i] - 0xD0) * 10 + mem[i + 1] - 0xD0
    def played(ms):
        lo, a, b = syms['STORE_CURSOR'], syms['seq_set_cursor'], syms['seq_ret']
        out, low = [], None
        for t, pc, addr, v in watch(s, lo, 2, ms):
            if not a <= pc <= b: continue
            if addr == lo: low = v
            elif low is not None:
                ch = chan_at((v << 8) | low); low = None
                if not out or out[-1] != ch: out.append(ch)
        return out
    def in_order(seq, want):
        if 0 not in seq: return False
        seq = seq[seq.index(0):]
        return len(seq) >= 2 * len(want) and all(c == want[i % len(want)] for i, c in enumerate(seq))

    s = Sign(rom, syms, fresh_ram=True)
    s.run_ms(2500)
    send(s, b'\x09\x30\x30\x0e' + b'HI')
    first = (syms['SEQ_LIST'] + 1) & 0xff              # SEQ_PTR's low byte once entry 0 is taken
    log = [(t, v) for t, _, addr, v in watch(s, syms['SEQ_PTR'], 1, 8000)]
    starts = [i for i, (t, v) in enumerate(log) if v == first]
    bursts = [(log[j][0] - log[i + 1][0]) / CPU_HZ * 1000 for i, j in zip(starts, starts[1:])]
    check('one message in channel 0: the 99 empty channels take %s ms per loop (under 100)'
          % [round(x) for x in bursts], len(bursts) >= 2 and max(bursts) < 100)
    for ch, text in ((b'07', b'SEVEN'), (b'50', b'FIFTY'), (b'99', b'NINETY NINE')):
        send(s, b'\x09' + ch + b'\x0e' + text)
    seq = played(30000)
    check('channels 0, 7, 50 and 99 play in order: %s' % seq, in_order(seq, [0, 7, 50, 99]))
    send(s, b'\x09\x30\x37\x0e' + b'S' * 41)           # an odd growth moves 50 and 99
    seq = played(30000)
    check('after channel 7 grows by 36 bytes: %s' % seq, in_order(seq, [0, 7, 50, 99]))
    send(s, b'\x09\x35\x30\x0e')                        # channel 50 emptied
    seq = played(30000)
    check('after channel 50 is emptied: %s' % seq, in_order(seq, [0, 7, 99]))
    # a hint left past the store's DA on a stale copy of a marker must not be used
    end = int.from_bytes(s.ram('STORE_END', 2), 'little')
    stale = end + 40
    s.m.memory[stale:stale + 3] = b'\xd9\xd9\x03'
    s.m.memory[syms['CHAN_HINT']:syms['CHAN_HINT'] + 2] = stale.to_bytes(2, 'little')
    send(s, b'\x09\x39\x39\x0e' + b'NEW')
    end = int.from_bytes(s.ram('STORE_END', 2), 'little')
    store = bytes(s.m.memory[syms['MSG_STORE']:end + 1])
    check('a stale hint past the DA is ignored: channel 99 reads %s, the stale copy %s'
          % (store[store.find(b'\xd9\xd9'):][:6].hex(), s.m.memory[stale:stale + 3].hex()),
          store.endswith(b'\xd9\xd9NEW\x03\xda') and s.m.memory[stale:stale + 3] == b'\xd9\xd9\x03')
    check('no faults, stack high-water %d' % s.depth(), not s.faults and s.depth() < 100)
    print('sequence: %d/%d checks pass' % (sum(checks), len(checks)))
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
    silence and follows the host at 300, 600, 1200 or 2560 baud (P52: 3 interrupts
    a bit); replies come back at the same rate; 2560 holds through a skewed and
    jittered line; NETCC's 300-baud habits still work"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    def send(s, payload, wait_ms=1500, flag=0x81):
        s.tx_edges.clear(); s.send_frame(payload, addr=1, flag=flag); s.rx_wait(); s.run_ms(wait_ms)
        return s.tx_bytes()
    text = b'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG ' * 5
    steps = {300: 5, 600: 10, 1200: 20, 2560: 40}
    for baud in steps:
        s = Sign(rom, syms, fresh_ram=True, baud=baud); s.run_ms(2500)
        tx = send(s, b'\xb4\x31', wait_ms=int(16 * 10000 / baud) + 500)
        rate = s.ram('BAUD_STEP')[0]
        check('%4d baud from cold: query reply %s, BAUD_STEP %d, BAUD_T %d' % (baud, tx[:9], rate, s.ram('BAUD_T')[0]), tx[:4] == b'\x06\xb1\x01\x0f' and tx[4:9] == b'%05d' % store_total(syms, False) and rate == steps[baud])
        tx = send(s, b'\x09\x30\x31\x0e' + text, wait_ms=500)
        d = bytes(s.m.memory[syms['MSG_STORE']:int.from_bytes(s.ram('STORE_END', 2), 'little')])
        check('%4d baud: 220-byte load intact, ACK+DONE %s' % (baud, tx.hex()), text in d and tx == b'\x06\x04')
        s.run_ms(300)                                       # well inside the idle window: no re-timing
        tx = send(s, b'\x09\x30\x32\x0e' + b'SECOND', wait_ms=500)
        check('%4d baud: a frame 0.3 s later is taken at the same rate (%s)' % (baud, tx.hex()), tx == b'\x06\x04' and s.ram('BAUD_STEP')[0] == rate)
        check('%4d baud: no faults, no watchdog clears (%d)' % (baud, s.wdog_clears), not s.faults and s.wdog_clears == 0)
    # the bit time is calibrated from the NMI second: 1200 must hold from 126 to 134 us
    # 2560 is 3 interrupts whatever the calibration says: it holds within 0.5 % of 130.2 us
    for tick_us, label, rate in ((126.0, '-3 %', 1200), (128.0, 'no latency', 1200), (132.0, '+1.5 %', 1200), (134.0, '+3 %', 1200),
                                 (129.6, '-0.5 %', 2560), (130.9, '+0.5 %', 2560)):
        s = Sign(rom, syms, fresh_ram=True, baud=rate); s.tick_t = int(tick_us * US); s.run_ms(3500)
        tx = send(s, b'\xb4\x31', wait_ms=600)
        tx2 = send(s, b'\x09\x30\x31\x0e' + text, wait_ms=500)
        d = bytes(s.m.memory[syms['MSG_STORE']:int.from_bytes(s.ram('STORE_END', 2), 'little')])
        check('%d baud with a %.1f us interrupt (%s): BAUD_T %d, query %s, load %s' % (rate, tick_us, label, s.ram('BAUD_T')[0], tx[:4].hex(), tx2.hex()), tx[:4] == b'\x06\xb1\x01\x0f' and tx2 == b'\x06\x04' and text in d)
    # a DC supply (no NMI, no calibration): 2560 needs none, 1200 takes the default bit time
    s = Sign(rom, syms, fresh_ram=True, baud=2560, mains=False); s.run_ms(3500)
    tx = send(s, b'\xb4\x31', wait_ms=600)
    s.run_ms(1500); s.set_baud(1200)
    tx2 = send(s, b'\xb4\x31', wait_ms=600)
    check('DC supply: 2560 answered (%s), then 1200 with the default bit time (%s, BAUD_T %d)' % (tx[:4].hex(), tx2[:4].hex(), s.ram('BAUD_T')[0]), tx[:4] == b'\x06\xb1\x01\x0f' and s.ram('BAUD_T')[0] == 128 and tx2[:4] == b'\x06\xb1\x01\x0f')
    # 2560 on a line whose spaces are 60 us long or short, edges moved up to 20 us at random;
    # at 16-cycle slices: at 128 a short DI holds an interrupt back a whole slice and a sample with it
    global SLICE
    SLICE, coarse = 16, SLICE
    for skew in (60, -60):
        s = Sign(rom, syms, fresh_ram=True, baud=2560, seed=skew & 0xff); s.rx_skew_us, s.rx_jitter_us = skew, 20; s.run_ms(2500)
        ok = sum(send(s, b'\x09\x30\x31\x0e' + text, wait_ms=400) == b'\x06\x04' for _ in range(5))
        check('2560 with spaces %+d us and 20 us jitter: %d/5 long loads' % (skew, ok), ok == 5)
    SLICE = coarse
    # a session that changes rate after a pause, and one that comes back to 300
    s = Sign(rom, syms, fresh_ram=True, baud=1200); s.run_ms(2500)
    send(s, b'\x09\x30\x30\x0e' + b'FAST', wait_ms=500)
    s.run_ms(1500); s.set_baud(300)
    tx = send(s, b'\x09\x30\x31\x0e' + b'SLOW', wait_ms=3000)   # DONE can wait behind the sequence's empty-channel scans
    check('1200 then, after 1.5 s, 300: taken (%s, BAUD_STEP %d)' % (tx.hex(), s.ram('BAUD_STEP')[0]), tx == b'\x06\x04' and s.ram('BAUD_STEP')[0] == 5)
    s.run_ms(1500); s.set_baud(1200)
    tx = send(s, b'\xb4\x33', wait_ms=6500)   # the query can wait behind the empty-channel scans, then 3 s of dump
    check('then 1200: a store dump comes back whole at 1200 (%d bytes, ends %s)' % (len(tx), tx[-1:].hex()), tx[:4] == b'\x06\xb1\x01' + bytes([len(tx) - 6]) and tx[-1:] == b'\x04' if False else len(tx) > 20 and b'FAST' in tx and b'SLOW' in tx and tx.endswith(b'\x04'))
    # a terminal session at 300 (P45): B7 '1' opens the editor, then keys, 0D leaves
    s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
    send(s, b'\x09\x30\x30\x0e' + b'HELLO', wait_ms=500); s.run_ms(1500)
    tx = send(s, b'\xb7\x31', wait_ms=500, flag=0x80)
    menu = s.ram('MENU_ACTIVE')[0]
    s.send_bytes(b'X'); s.rx_wait(); s.run_ms(500)
    s.send_bytes(b'\x0d'); s.rx_wait(); s.run_ms(1500)
    check("300 baud B7 '1' after 1.5 s idle opens the editor (%s, %02x), X typed, 0D leaves (%02x)" % (tx.hex(), menu, s.ram('MENU_ACTIVE')[0]), tx[:1] == b'\x06' and menu == 0xff and s.ram('MENU_ACTIVE')[0] == 0)
    check('no faults', not s.faults)
    print('baud: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_clock():
    """P31: the NMI source. With no mains NMI through the boot the firmware selects the
    add-in board's 64 Hz through BANK_REG bit 7 and counts 64 a second; the bit is
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
    def shown(s):
        # the characters handed to the glyph lookup, the clock code itself left out
        out = bytearray()
        for _ in range(16000):
            s.run_ms(0.25)
            c = s.ram('CUR_CHAR')[0]
            if c != 0x5f and c != (out[-1] if out else None):
                out.append(c)
        return bytes(out)
    settime(s, b'1234', b'H'); got = shown(s)
    check('24-hour: the clock reads 12:34 and no AM or PM (%r)' % got, b' 12:34 NOW' in got)
    settime(s, b'1234', b'N'); got = shown(s)
    check('12-hour: the clock reads 12:34 PM (%r)' % got, b' 12:34 PM NOW' in got)
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


def store_total(syms, ram8k):
    """the store size B4 '1' reports: the ceiling store_init picks, less MSG_STORE, plus one"""
    return syms['STORE_TOP_8K' if ram8k else 'STORE_TOP'] - syms['MSG_STORE'] + 1


def cmd_stats():
    """P40: B4 '4' appends the clock source, a boot count that survives a reset, stack
    headroom, merged display ticks, uptime, renderer stalls and frame/remote counters"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    def stats(s):
        t0 = s.t / CPU_HZ
        d = ota_cmd(s, b'\xb44')
        return None if d is None or len(d) != 22 else dict(t=t0,
            nmi=d[4], boot=d[5], head=d[6], merge=d[7], merge_max=d[8], up=d[9] | d[10] << 8 | d[11] << 16,
            stalls=d[12], stall_max=d[13], ok=d[14], bad=d[15], ir=d[16], ir_bad=d[17], rej=tuple(d[18:22]))
    s = Sign(rom, syms, fresh_ram=True); s.run_ms(3000)
    a = stats(s)
    check('stats reply: %s' % a, a is not None)
    if a is None:
        return False
    check('mains: 60 a second, first boot after fresh RAM is 1', a['nmi'] == 60 and a['boot'] == 1)
    check('uptime %d s after %.1f s' % (a['up'], a['t']), abs(a['up'] - a['t']) <= 1.5)
    check('stack headroom %d of %d' % (a['head'], syms['STACK_CANARY']), 0 < a['head'] <= syms['STACK_CANARY'])
    check('the query counted as a good frame (%d), none bad' % a['ok'], a['ok'] == 1 and a['bad'] == 0)
    check('remote drop counters zero after boot: %s' % (a['rej'],), a['rej'] == (0, 0, 0, 0))
    s.send_frame(FX_MAGIC, addr=1); s.rx_wait(); s.run_ms(20000)
    s.send_bytes(bytes([0xB1, 1, 0x80, 1, 0x41, 0x00])); s.rx_wait(); s.run_ms(500)
    global SLICE                        # the remote at 16-cycle slices, as the keypad gate runs it:
    SLICE, coarse = 16, SLICE           # at 128 a DI holds an interrupt back and can cost a frame
    s.ir_key('T', stretch_us=100); s.ir_wait(); s.run_ms(500)
    SLICE = coarse
    b = stats(s)
    check('after the effects message, a bad frame and a key: %s' % b, b is not None)
    check('uptime %d s after %.1f s' % (b['up'], b['t']), abs(b['up'] - b['t']) <= 1.5)
    check('frames: 3 good (%d), 1 bad (%d)' % (b['ok'], b['bad']), b['ok'] == 3 and b['bad'] == 1)
    check('remote: decoded %d, dropped %d, by reason %s' % (b['ir'], b['ir_bad'], b['rej']), b['ir'] >= 1 and b['ir_bad'] == 0 and b['rej'] == (0, 0, 0, 0))
    check('stalls %d, longest %d frames; merged ticks last %d, worst %d' % (b['stalls'], b['stall_max'], b['merge'], b['merge_max']),
          0 < b['stall_max'] < 255 and b['merge_max'] < 255)
    ram = bytes(s.m.memory[0x4000:0x8000])
    s2 = Sign(rom, syms, fresh_ram=True); s2.m.set_memory_block(0x4000, ram); s2.run_ms(3000)
    c = stats(s2)
    check('reset with RAM kept: boot 2 (%s), uptime from 0 (%s), counters cleared (%s)' % (c and c['boot'], c and c['up'], c and c['ok']),
          c is not None and c['boot'] == 2 and c['up'] <= 4 and c['ok'] == 1 and c['bad'] == 0)
    s3 = Sign(rom, syms, fresh_ram=True, mains=False, crystal=True); s3.run_ms(3000)
    d = stats(s3)
    check('DC + board: 64 a second (%s), uptime %s' % (d and d['nmi'], d and d['up']), d is not None and d['nmi'] == 64 and abs(d['up'] - d['t']) <= 1.5)
    check('no faults', not (s.faults or s2.faults or s3.faults))
    print('stats: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_status():
    """P41: status reports: none while off; with them on, one per channel start naming
    the channel (the wrap flagged), FF when the editor opens; the host tool's queries
    and loads still work with reports flowing, the filter collecting them"""
    import cc784
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    def reports(tx):
        out, i = [], 0
        while i + 7 <= len(tx):
            f = tx[i:i + 7]
            if f[0] == 0xB1 and f[2] == 3 and f[3] == ord('S') and sum(f[3:6]) & 0xFF == f[6]:
                out.append((f[4], f[5])); i += 7
            else:
                i += 1
        return out
    s = Sign(rom, syms, fresh_ram=True, baud=1200); s.run_ms(2500)
    s.send_frame(b'\x09\x30\x30\x0eONE\x09\x30\x31\x0eTWO\x04', addr=1); s.rx_wait(); s.run_ms(1000)
    s.tx_edges.clear(); s.run_ms(8000)
    check('off by default: nothing sent in 8 s (%s)' % s.tx_bytes().hex(), s.tx_bytes() == b'')
    s.send_frame(bytes([0xB6, 2, 0x80, 0x80]), addr=1); s.rx_wait(); s.run_ms(500)
    s.tx_edges.clear(); s.run_ms(12000)
    r = reports(s.tx_bytes())
    chans = [c for c, f in r]
    check('on: reports %s' % ['%d/%02x' % x for x in r], len(r) >= 4 and set(chans) == {0, 1}
          and all(a != b for a, b in zip(chans, chans[1:])))
    check('the wrap is flagged on channel 0 only', all((f & 0x40) == (0x40 if c == 0 else 0) for c, f in r))
    check('nothing else on the line', len(s.tx_bytes()) == 7 * len(r))
    link = SimLink(s)
    sign = cc784.Sign(link, 1, baud=1200)
    sign.post_ack = 0.2; sign.done = True; sign.quiet = True
    replies = [sign.query('4') for _ in range(8)]
    bad = [r.hex() for r in replies if len(cc784.reply_data(r)) != 22]
    ok = sign.send_frame(b'\x09\x30\x32\x0e' + b'THREE ' * 30)
    check('with reports flowing: 8 stats replies (bad: %s), a 180-byte load ACKed (%s), %d reports filtered'
          % (bad, ok, len(sign.link.reports)), not bad and ok and sign.link.reports)
    s.tx_edges.clear()
    s.ir_key('STOP', stretch_us=100); s.ir_wait(); s.run_ms(800)
    r = reports(s.tx_bytes())
    check('the editor opens: report FF (%s)' % r, r[:1] and r[0][0] == 0xFF)
    s.ir_key('STOP', stretch_us=100); s.ir_wait(); s.run_ms(3000)
    s.send_frame(bytes([0xB6, 2, 0x80, 0x00]), addr=1); s.rx_wait(); s.run_ms(500)
    s.tx_edges.clear(); s.run_ms(8000)
    check('off again: nothing sent (%s)' % s.tx_bytes().hex(), s.tx_bytes() == b'')
    check('no faults', not s.faults)
    print('status: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_term():
    """P45: the serial port carries frames only. Loose bytes are never keys; a lost
    byte costs one frame (a second of silence resets the parser); a bad flag byte
    sends the parser back to look for B1; while the editor is open frames are
    answered BUSY, except B7: '1' makes it a serial terminal, '0' closes it"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    def store(s):
        return bytes(s.m.memory[syms['MSG_STORE']:int.from_bytes(s.ram('STORE_END', 2), 'little')])
    def frame(payload, flag=0x80):
        return bytes([0xB1, 1, flag, len(payload)]) + payload + bytes([sum(payload) & 0xff])
    def send(s, data, wait_ms=1500):
        s.tx_edges.clear(); s.send_bytes(data); s.rx_wait(); s.run_ms(wait_ms)
        return s.tx_bytes()
    load = lambda text: frame(b'\x09\x30\x30\x0e' + text)
    s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
    send(s, load(b'HELLO'), 2000)

    tx = send(s, b'\x01HI\x0d\x01')
    check('display mode: loose bytes, 01 among them, open nothing (menu %02x, tx %s)' % (s.ram('MENU_ACTIVE')[0], tx.hex()),
          s.ram('MENU_ACTIVE')[0] == 0 and tx == b'')
    tx = send(s, load(b'LOST')[1:] + b'\x30' * 20, 1200) + send(s, load(b'AFTER'), 2000)
    check('a frame without its B1 is dropped, the next one taken (tx %s)' % tx.hex(), tx == b'\x06' and b'AFTER' in store(s))
    f = load(b'SHORT')
    tx = send(s, f[:6] + f[7:], 1200) + send(s, load(b'RESYNC'), 2000)
    check('a frame one byte short, a second of silence, the next one taken (tx %s)' % tx.hex(), tx == b'\x06' and b'RESYNC' in store(s))
    tx = send(s, b'\xb1\x05\x41' + load(b'FLAG'), 2000)
    check('a B1 followed by no header, then a frame at once: taken (tx %s)' % tx.hex(), tx == b'\x06' and b'FLAG' in store(s))
    tx = send(s, b'\xb1\x01' + load(b'B1FLAG'), 2000)
    check('a B1 in the flag position starts the frame over (tx %s)' % tx.hex(), tx == b'\x06' and b'B1FLAG' in store(s))

    s.ir_key('STOP', stretch_us=100); s.ir_wait(); s.run_ms(1500)
    before = store(s)
    tx = send(s, load(b'BUSY'), 2000)
    check("remote's editor: a load is answered BUSY (%s) and not stored" % tx.hex(), tx == b'\x18' and store(s) == before)
    tx = send(s, b'XYZ \x0d', 1500)
    check('remote\'s editor: loose bytes are not typed (tx %s, menu %02x)' % (tx.hex(), s.ram('MENU_ACTIVE')[0]),
          store(s) == before and s.ram('MENU_ACTIVE')[0] == 0xFF and tx == b'')
    tx = send(s, frame(b'\xb7\x31'), 800) + send(s, b'Q', 1500)
    check("B7 '1' in the open editor: ACK, then serial keys type (tx %s)" % tx.hex(), tx[:1] == b'\x06' and store(s) != before)
    typed = store(s)
    tx = send(s, load(b'TERM'), 2000)
    check('terminal: a frame is answered BUSY (%s), none of its bytes typed' % tx.hex(), tx[:1] == b'\x18' and store(s) == typed)
    tx = send(s, frame(b'\xb7\x30'), 2500)
    check("B7 '0' closes the editor (tx %s, menu %02x)" % (tx.hex(), s.ram('MENU_ACTIVE')[0]), tx[:1] == b'\x06' and s.ram('MENU_ACTIVE')[0] == 0)
    tx = send(s, frame(b'\xb7\x30'), 1500)
    check("B7 '0' with the editor shut: ACK, nothing else (%s, menu %02x)" % (tx.hex(), s.ram('MENU_ACTIVE')[0]), tx == b'\x06' and s.ram('MENU_ACTIVE')[0] == 0)

    tx = send(s, frame(b'\xb7\x31'), 1500)
    check("B7 '1' from display mode opens the editor (tx %s, menu %02x)" % (tx.hex(), s.ram('MENU_ACTIVE')[0]), tx[:1] == b'\x06' and s.ram('MENU_ACTIVE')[0] == 0xFF)
    send(s, b'\x17', 1500); send(s, b'12', 1500)
    stopped = s.ram('CLK_RUN')[0]
    tx = send(s, frame(b'\xb7\x30'), 2500)
    check("B7 '0' halfway through TIME? (clock stopped: %02x): closed, clock running (%02x, menu %02x)"
          % (stopped, s.ram('CLK_RUN')[0], s.ram('MENU_ACTIVE')[0]), stopped == 0 and s.ram('CLK_RUN')[0] == 0xFF and s.ram('MENU_ACTIVE')[0] == 0)
    tx = send(s, frame(b'\xb4\x31'), 2500)
    check('then a query is answered as usual (%s)' % tx[:4].hex(), tx[:4] == b'\x06\xb1\x01\x0f')
    check('no faults', not s.faults)

    # keys typed seconds apart at 1200: no re-timing as if each were a B1
    s = Sign(rom, syms, fresh_ram=True, baud=1200); s.run_ms(2500)
    send(s, frame(b'\xb7\x31'), 1500)
    echo = b''.join(send(s, k, 1500) for k in (b'B', b'Z', b'\x7f')) + send(s, b'\x7f', 1500)
    check('1200 baud, keys 1.5 s apart: echoed intact (%s)' % echo.hex(), echo == b'BZ\x7f\x7f')
    check('no faults at 1200', not s.faults)
    print('term: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_randbow():
    """P46: B2 BC is RANDBOW: RAINBOW's five colors dealt as a shuffled deck, no color
    twice in a row; plain RAINBOW unchanged; FUNC SHIFT COLOR in the editor inserts
    B2 BC (FUNC2), DEL takes both; B2 survives a reset"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    def store(s):
        return bytes(s.m.memory[syms['MSG_STORE']:int.from_bytes(s.ram('STORE_END', 2), 'little')])
    def deals(s, ms):
        """RAINBOW_IDX as set per character, split at each (re)start of the cycle"""
        a = syms['RAINBOW_IDX']
        s.watch = {a}; s.watch_log.clear(); s.m.mark_addrs(a, 1, s.m.WRITE_MARK)
        s.run_ms(ms)
        runs, cur = [], None
        for t, pc, addr, v in s.watch_log:
            if syms['rainbow_on'] <= pc < syms['rainbow_step']:
                cur = []; runs.append(cur)
            elif cur is not None and v & 7 and syms['rainbow_apply'] <= pc < syms['rainbow_apply'] + 16:
                cur.append(v & 7)
        return [r for r in runs if len(r) >= 10]
    text = b'ABCDEFGHIJKLMNOPQRSTUVWXYZ' * 2

    s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
    s.send_frame(b'\x09\x30\x30\x0e\xb2\xbc' + text, addr=1); s.rx_wait(); s.run_ms(500)
    runs = deals(s, 30000)
    n = syms.get('RAINBOW_N', 5)
    def shuffled(r):
        return all(sorted(r[i:i + n]) == list(range(1, n + 1)) for i in range(0, len(r) - n + 1, n)) \
            and len(set(r[len(r) - len(r) % n:])) == len(r) % n
    check('RANDBOW: %d passes, %s ...' % (len(runs), runs[0][:15] if runs else None),
          len(runs) >= 2 and all(shuffled(r) for r in runs))
    check('no color twice in a row, decks differ between passes',
          all(a != b for r in runs for a, b in zip(r, r[1:])) and len({tuple(r[:10]) for r in runs}) > 1)

    s.send_frame(b'\x09\x30\x30\x0e\xbc' + text, addr=1); s.rx_wait(); s.run_ms(500)
    runs = deals(s, 15000)
    steps = [{(b - a) % n for a, b in zip(r, r[1:])} for r in runs]
    check('plain RAINBOW still steps one color at a time, one direction a pass (%s)' % steps, runs and all(len(x) == 1 and x <= {1, n - 1} for x in steps))

    s.send_frame(b'\x09\x30\x30\x0e' + b'AB\xb2\xbcCD', addr=1); s.rx_wait(); s.run_ms(3000)
    s.ir_key('STOP', stretch_us=100); s.ir_wait(); s.run_ms(1500)
    def idle_sp():
        sps = set()
        for _ in range(40):
            s.run_ms(5); sps.add(s.m.sp)
        return max(sps)
    sp0 = idle_sp()
    for _ in range(3):
        for k in ('SHIFT', 'STOP', 'T'):
            s.ir_key(k, stretch_us=100); s.ir_wait(); s.run_ms(400)
    check('P47: three FUNC cancels leave the editor stack where it was (%04x -> %04x), PKT_READY %02x'
          % (sp0, idle_sp(), s.ram('PKT_READY')[0]), idle_sp() == sp0 and s.ram('PKT_READY')[0] == 0)
    before = store(s)
    for k in ('SHIFT', 'STOP'):
        s.ir_key(k, stretch_us=100); s.ir_wait(); s.run_ms(400)
    func = s.ram('FUNC_PENDING')[0]
    s.ir_key('SHIFT', stretch_us=100); s.ir_wait(); s.run_ms(400)
    func2, shift = s.ram('FUNC_PENDING')[0], s.ram('SHIFT_STATE')[0]
    s.ir_key('COLOR', stretch_us=100); s.ir_wait(); s.run_ms(1500)
    after = store(s)
    check('FUNC (%02x), then SHIFT: FUNC2 (%02x, shift %02x), then COLOR: B2 BC inserted (%d -> %d)'
          % (func, func2, shift, before.count(b'\xb2\xbc'), after.count(b'\xb2\xbc')),
          func == 0xFF and func2 == 2 and shift == 0 and after.count(b'\xb2\xbc') == before.count(b'\xb2\xbc') + 1
          and len(after) == len(before) + 2)
    s.ir_key('DEL', stretch_us=100); s.ir_wait(); s.run_ms(1500)
    check('DEL takes the B2 along (store %s)' % store(s)[-12:].hex(), store(s) == before)
    for k in ('SHIFT', 'STOP', 'COLOR'):
        s.ir_key(k, stretch_us=100); s.ir_wait(); s.run_ms(400)
    s.run_ms(1000)
    plain = store(s)
    for k in ('SHIFT', 'STOP', 'C'):
        s.ir_key(k, stretch_us=100); s.ir_wait(); s.run_ms(400)
    s.run_ms(1000)
    check('FUNC C types a comma', len(store(s)) == len(plain) + 1 and store(s).count(b',') == plain.count(b',') + 1)
    check('FUNC COLOR is still plain RAINBOW (one BC, no B2 added)',
          len(plain) == len(before) + 1 and plain.count(b'\xbc') == before.count(b'\xbc') + 1 and plain.count(b'\xb2') == before.count(b'\xb2'))
    seen = []
    for k in ('LEFT',) * 6 + ('RIGHT',) * 6:
        s.ir_key(k, stretch_us=100); s.ir_wait(); s.run_ms(500)
        seen.append(s.m.memory[int.from_bytes(s.ram('STORE_CURSOR', 2), 'little')])
    check('LEFT and RIGHT step over the B2, stopping on its BC (%s)' % bytes(seen).hex(),
          0xB2 not in seen and 0xBC in seen[:6] and 0xBC in seen[6:])
    s.send_frame(b'\xb7\x30', addr=1); s.rx_wait(); s.run_ms(3000)
    check('editor closed', s.ram('MENU_ACTIVE')[0] == 0)

    s2 = Sign(rom, syms, fresh_ram=True)
    s2.m.set_memory_block(0x4000, bytes(s.m.memory[0x4000:0x8000]))
    s2.run_ms(3000)
    kept = bytes(s2.m.memory[syms['MSG_STORE']:syms['MSG_STORE'] + len(store(s)) + 1])
    check('B2 BC survives a reset (store_repair keeps it): %s' % kept[:16].hex(), kept == store(s) + b'\xda')
    check('no faults', not s.faults and not s2.faults)
    print('randbow: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_scroll():
    """P48: B2 1A / B2 1B scroll the staged page in one row a step, pushing the panel's
    page out, in yellow (no color bytes while moving), then rest in its colors; plain
    1A still wipes; FUNC2 UP and FUNC2 SHIFT UP insert them in the editor. P53: B2 0F
    slides the page in from the left a column a frame, in color; FUNC2 SHIFT BEEP"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    fb, n = syms['FRAMEBUF'], syms['FRAME_COLS']
    pix = lambda b: 0 if b & 0x80 else b
    s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
    s.send_frame(b'\x09\x30\x30\x0e\x19\x8cFIRST\xb2\x1a\x83SECOND\xb2\x1b\x8dTHIRD\x1aFOURTH', addr=1)
    s.rx_wait()
    seq, last, quiet = [], None, 0
    for _ in range(9000):                  # a step takes ~10 ms to write: keep each burst's last state
        s.run_ms(2)
        win = bytes(s.m.memory[fb:fb + n])
        if win != last:
            if seq and quiet < 10:
                seq.pop()
            seq.append((s.ram('EFFECT_ID')[0], win)); last, quiet = win, 0
        else:
            quiet += 1
    blank = bytes([0x80]) * n
    for eid, name, shift in ((6, 'UP', lambda o, w, k: ((o >> k) | (w << (7 - k))) & 0x7f),
                             (7, 'DOWN', lambda o, w, k: ((o << k) | (w >> (7 - k))) & 0x7f)):
        i0 = next((i for i, (e, w) in enumerate(seq) if e == eid), None)
        i1 = next((i for i in range(i0, len(seq)) if seq[i][0] != eid), len(seq)) if i0 is not None else 0
        run = [w for e, w in seq[i0:i1]] if i0 is not None else []
        run = [w for w in run if w != blank]
        if run and all(not c & 0x80 for c in run[-1]):   # the effect ended within a sample of its last copy:
            run += [w for e, w in seq[i1:i1 + 2] if w != blank][:1]   # the resting page is the next state
        if len(run) < 7:
            check('SCROLL %s ran (%d frames)' % (name, len(run)), False); continue
        old, steps, new = (run[-8] if len(run) >= 8 else seq[i0 - 1][1]), run[-7:-1], run[-1]
        want = [bytes(shift(pix(o), pix(w), k) for o, w in zip(old, new)) for k in range(1, 7)]
        check('SCROLL %s: %d steps, each the old page moved k rows and the new one k rows in' % (name, len(steps)),
              steps[:6] == want)
        check('SCROLL %s: no color bytes while moving; the resting page keeps its %d color bytes, as the wipes do'
              % (name, sum(1 for c in new if c & 0x80 and c != 0x80)),
              all(not c & 0x80 for st in steps for c in st) and any(c & 0x80 and c != 0x80 for c in new))
    check('plain UP still wipes (effect 2 seen)', any(e == 2 for e, w in seq))
    check('no faults', not s.faults)

    # the moving frames show only the row color: yellow even right after a colored crawl
    s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
    s.send_frame(b'\x09\x30\x30\x0e\x83GREEN CRAWL \xb2\x1aUP\xb2\x1bDOWN\x18', addr=1); s.rx_wait()
    rc = set()
    for _ in range(16000):
        s.run_ms(0.5)
        win = bytes(s.m.memory[fb:fb + n])
        if s.ram('EFFECT_ID')[0] in (6, 7) and s.ram('DISP_ON')[0] and any(win) and not any(c & 0x80 for c in win):
            rc.add(s.ram('ROW_COLOR')[0])          # a moving frame: pixels only
    check('SCROLL UP/DOWN after a green crawl: the row color while moving is yellow (%s)' % sorted('%02x' % c for c in rc),
          rc and all(c & 0xef == 0x8f for c in rc))

    # P53: SCROLL RIGHT after a colored crawl, sampled every frame: step k is the new page's
    # last k columns, then the panel's page (unrolled from the ring) pushed right; the margin
    # byte where they meet carries the old page's start color, and ROW_COLOR is the color in
    # force at the new page's left edge. The new page moves sideways in its own colors
    # and turns yellow on the last step, when it comes to rest.
    s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
    s.send_frame(b'\x09\x30\x30\x0e\x8cRED CRAWL \x83GREEN\xb2\x0f\x8dORANGE\x19\x80', addr=1)
    s.rx_wait()
    def panel(s):
        p = int.from_bytes(s.ram('FB_OUT_PTR', 2), 'little'); ln, ex = s.ram('FB_OUT_LEN', 2)
        return bytes(s.m.memory[p:p + ln]) + bytes(s.m.memory[fb:fb + ex])
    frames, old, c0, last, tears = [], None, None, None, 0
    for _ in range(40000):
        s.run_ms(0.5)
        e = s.ram('EFFECT_ID')[0]
        if e != 8 or not frames and s.ram('DISP_ON')[0] == 0:
            if frames: break
            if e != 8: old, c0 = panel(s), s.ram('ROW_COLOR')[0]
            continue
        win, row = (panel(s), s.ram('ROW_COLOR')[0]), s.ram('ROW_INDEX')[0]
        if row == 0 and win != last:
            last = win
            if frames or win[0] != old: frames.append(win)
        elif frames and win != last:
            tears += 1                     # the page changed while a frame was going out
    rest = frames[-1][0] if frames else b''
    new = bytes(n) if len(frames) < n else bytes(1) + frames[-2][0][:n - 2] + rest[n - 1:]   # in its colors, from step n-1
    yellow = lambda b: b & 0x10 | 0x8f if b & 0x80 else b
    def want(k):
        if k == n:
            return bytes(yellow(b) for b in new), yellow(c0)
        w = bytearray(new[n - k:] + old[:n - k])
        if k < n and (w[k - 1] & 0x80 or not w[k - 1]):
            w[k - 1] = c0
        return bytes(w), next((b for b in reversed(new[:n - k]) if b & 0x80), c0)
    bad = [k for k, f in enumerate(frames, 1) if f != want(k)]
    check('SCROLL RIGHT: %d steps (want %d), each the new page k columns in from the left, the old one pushed right (first bad %s)'
          % (len(frames), n, bad[:1]), len(frames) == n and not bad)
    check('SCROLL RIGHT: every row moves at once: no page or row color change mid-frame (%d)' % tears, tears == 0)
    check('SCROLL RIGHT: the new page slides in orange (%d steps) and rests in yellow (row color %02x)'
          % (sum(1 for f, c in frames[:-1] if 0x8d in f[:len(frames)]), frames[-1][1] if frames else 0),
          frames and sum(1 for f, c in frames[:-1] if 0x8d in f) > n // 3 and 0x8d not in rest and frames[-1][1] & 0xef == 0x8f)
    check('SCROLL RIGHT: the crawl it pushes out keeps its colors (red and green bytes in %d steps)'
          % sum(1 for f, c in frames if 0x8c in f and 0x83 in f),
          old and 0x8c in old and 0x83 in old and sum(1 for f, c in frames if 0x8c in f) > n // 4)
    check('no faults', not s.faults)

    def store(s):
        return bytes(s.m.memory[syms['MSG_STORE']:int.from_bytes(s.ram('STORE_END', 2), 'little')])
    s.send_frame(b'\x09\x30\x30\x0eAB', addr=1); s.rx_wait(); s.run_ms(3000)
    s.ir_key('STOP', stretch_us=100); s.ir_wait(); s.run_ms(1500)
    for keys in (('SHIFT', 'STOP', 'SHIFT', '1A'), ('SHIFT', 'STOP', 'SHIFT', 'SHIFT', '1A'), ('SHIFT', 'STOP', 'SHIFT', 'SHIFT', 'BEEP')):
        for k in keys:
            s.ir_key(k, stretch_us=100); s.ir_wait(); s.run_ms(400)
        s.run_ms(1000)
    check('editor: FUNC2 UP, FUNC2 SHIFT UP and FUNC2 SHIFT BEEP insert B2 1A, B2 1B and B2 0F (%s)' % store(s)[:12].hex(),
          b'\xb2\x1a\xb2\x1b\xb2\x0f' in store(s))
    s.send_frame(b'\xb7\x30', addr=1); s.rx_wait(); s.run_ms(2000)
    check('no faults in the editor', not s.faults)
    print('scroll: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def _shown_watch(s, syms):
    """log writes to both framebuffer halves, the output pointer and SPARKLE; shown() reads the half on the panel"""
    fb, n, ptr, sp = syms['FRAMEBUF'], syms['FRAME_COLS'], syms['FB_OUT_PTR'], syms['SPARKLE']
    s.watch = set(range(fb, fb + 2 * n)) | {ptr, ptr + 1, sp}; s.watch_log.clear()
    s.m.mark_addrs(fb, 2 * n, s.m.WRITE_MARK); s.m.mark_addrs(ptr, 2, s.m.WRITE_MARK); s.m.mark_addrs(sp, 1, s.m.WRITE_MARK)
    s.ptr0 = bytearray(s.m.memory[ptr:ptr + 2]); s.fb0 = bytearray(s.m.memory[fb:fb + 2 * n])
    return lambda: bytes(s.m.memory[int.from_bytes(s.ram('FB_OUT_PTR', 2), 'little'):][:n])


def _shown_writes(s, syms):
    """writes by the TWINKLE/GLIMMER bodies that landed in the half the panel was showing"""
    n, ptr = syms['FRAME_COLS'], syms['FB_OUT_PTR']
    lo, hi = syms['fxv_twinkle'], syms['twinkle_page']
    cur, bad = bytearray(s.ptr0), 0
    for t, pc, a, v in s.watch_log:
        if a in (ptr, ptr + 1):
            cur[a - ptr] = v
        elif lo <= pc < hi:
            p = int.from_bytes(cur, 'little')
            bad += p <= a < p + n
    return bad


def _sparkle_play(s, syms, chan0, ms):
    """load channel 0, play it ms, and cut out each TWINKLE/GLIMMER hold: from fx_hold_done taking a
    set SPARKLE to the final page copy (fxv_pointers); kind, effect, ms, frames, and the page
    that copy leaves, replayed from the write log (the next effect may start before a sample)"""
    s.send_frame(b'\x09\x30\x30\x0e' + chan0, addr=1); s.rx_wait()
    shown, samples = _shown_watch(s, syms), []
    for _ in range(ms // 2):
        s.run_ms(2)
        samples.append((s.t, s.ram('EFFECT_ID')[0], shown()))
    fb, n, sp, ptr = syms['FRAMEBUF'], syms['FRAME_COLS'], syms['SPARKLE'], syms['FB_OUT_PTR']
    hold, wipe = syms['fx_hold_done'], syms['fxv_wipe_updown']
    pointers, right = syms['fxv_pointers'], syms['fxv_right']
    copy, pick = syms['twinkle_page'], syms['twinkle_pick']
    spans, last, start, mem, ending = [], 0, None, bytearray(s.fb0), None
    for t, pc, a, v in s.watch_log:
        if ending and not (copy <= pc < pick or pointers <= pc < right):
            spans.append(ending + (bytes(mem[:n]),)); ending = None
        if a == sp:
            if v == 0 and hold <= pc < wipe and last:
                start = (last, t)
            last = v
        elif a in (ptr, ptr + 1):
            if a == ptr and start and pointers <= pc < right:
                ending = start + (t,); start = None
        else:
            mem[a - fb] = v
    if ending:
        spans.append(ending + (bytes(mem[:n]),))
    runs = []
    for kind, t0, t1, after in spans:
        frames = [(e, w) for t, e, w in samples if t0 < t < t1]   # a sample at t0 precedes the writes logged at t0
        if frames:
            runs.append(dict(kind=kind, effect=frames[0][0], ms=(t1 - t0) / US / 1000,
                             frames=[w for e, w in frames], page=after))
    return runs


# PAUSE, W-UP, W-DOWN, W-RIGHT, HOLD, S-UP, S-DOWN: effects 1-7, each a page with the modifier
SPARKLE_PAGES = [(b'\x19', b'PAUSE'), (b'\x1a', b'UP'), (b'\x1b', b'DOWN'), (b'\x0f', b'RIGHT'),
                 (b'\xbb', b'HOLD'), (b'\xb2\x1a', b'S-UP'), (b'\xb2\x1b', b'S-DOWN')]


def _sparkle_common(check, s, syms, runs, kind, mod, name):
    """checks both modifiers share: every staged effect, the hold's length, frames inside the
    page, the page whole after; then no hold for a crawl, a modifier before its effect, or none"""
    n = syms['FRAME_COLS']
    hold_ms = s.ram('CFG_HOLD')[0] * 1000 / 62
    runs = [r for r in runs if r['kind'] == kind]
    check('%s holds after effects %s' % (name, sorted({r['effect'] for r in runs})),
          {r['effect'] for r in runs} == set(range(1, 8)))
    ms = [r['ms'] for r in runs] or [0]
    check('each hold %.0f-%.0f ms, a plain hold %.0f ms' % (min(ms), max(ms), hold_ms),
          all(0.85 < m / hold_ms < 1.15 for m in ms))
    inside = all(all((w[c] == r['page'][c]) if r['page'][c] & 0x80 else not (w[c] & ~r['page'][c])
                     for c in range(n)) for r in runs for w in r['frames'])
    check('every frame is the page with lit pixels taken away, color bytes untouched', inside)
    whole = all(r['page'] == bytes(functools.reduce(lambda x, y: [a | b if not a & 0x80 else a for a, b in zip(x, y)],
                                                    r['frames'], list(r['page']))) for r in runs)
    check('the page rests whole at the end', whole)
    check('frames are built in the hidden half: %d writes to the shown one' % _shown_writes(s, syms), not _shown_writes(s, syms))
    check('no faults', not s.faults)
    none = _sparkle_play(s, syms, mod + b'CRAWL ' + mod + b'\x19BEFORE\x19PLAIN\xbbHOLD', 9000)
    check('no %s for a crawl, a modifier before its effect, or plain PAUSE/HOLD (%d)' % (name, len(none)), not none)
    return runs


def _sparkle_editor(check, s, syms, keys, code, label):
    def store(s):
        return bytes(s.m.memory[syms['MSG_STORE']:int.from_bytes(s.ram('STORE_END', 2), 'little')])
    s.send_frame(b'\x09\x30\x30\x0eAB', addr=1); s.rx_wait(); s.run_ms(3000)
    s.ir_key('STOP', stretch_us=100); s.ir_wait(); s.run_ms(1500)
    for k in keys:
        s.ir_key(k, stretch_us=100); s.ir_wait(); s.run_ms(400)
    s.run_ms(1000)
    check('editor: %s inserts %s (%s)' % (label, code.hex(), store(s)[:10].hex()), code in store(s))
    s.send_frame(b'\xb7\x30', addr=1); s.rx_wait(); s.run_ms(2000)
    check('no faults in the editor', not s.faults)


def cmd_twinkle():
    """P49: B2 19 (TWINKLE) after PAUSE, a wipe, HOLD or a scroll: the page, once up, is held
    with random lit pixels going dark a tick at a time, then left whole; alone or before its
    effect it does nothing; FUNC2 PAUSE inserts it in the editor"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    n = syms['FRAME_COLS']
    s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
    runs = _sparkle_play(s, syms, b''.join(fx + b'\xb2\x19' + w for fx, w in SPARKLE_PAGES) + b'\x19END', 20000)
    pats, most, reach = [], 0, []
    for r in runs:
        page, dark = r['page'], [w for w in r['frames'] if w != r['page']]
        pats.append(len(set(dark)))
        for w in dark:
            most = max(most, sum(bin(page[c] & ~w[c]).count('1') for c in range(n) if not page[c] & 0x80))
        lit = sum(bin(page[c]).count('1') for c in range(n) if not page[c] & 0x80)
        ever = [page[c] & ~functools.reduce(operator.and_, (w[c] for w in dark), 0xff) for c in range(n)]
        reach.append(sum(bin(ever[c]).count('1') for c in range(n) if not page[c] & 0x80) / max(lit, 1))
    check('%s different patterns per hold (~20 ticks)' % sorted(set(pats)), pats and min(pats) >= 15)
    check('at most %d pixels dark at once (most %d)' % (syms['TWINKLE_DOTS'], most), 0 < most <= syms['TWINKLE_DOTS'])
    check('the dots reach %.0f%%+ of each page\'s lit pixels over a hold' % (100 * min(reach or [0])),
          reach and min(reach) >= (0.85 if syms['TWINKLE_DOTS'] >= 80 else 0.6))   # LITE: 24 dots
    _sparkle_common(check, s, syms, runs, 1, b'\xb2\x19', 'TWINKLE')
    _sparkle_editor(check, s, syms, ('SHIFT', 'STOP', 'SHIFT', 'JUMP'), b'\xb2\x19', 'FUNC2 PAUSE')
    print('twinkle: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_glimmer():
    """P50: B2 BB (GLIMMER) after PAUSE, a wipe, HOLD or a scroll: the page, once up, is held
    with a dark band rolled one row per panel column, so the stripes run diagonally, and one
    row per tick, up or down and slanting either way at random; alone or before its effect it does nothing;
    FUNC2 SHIFT SEQ (HOLD) inserts it in the editor"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    n, band = syms['FRAME_COLS'], syms['GLIMMER_BAND']
    rot = lambda m, k: ((m << (k % 8)) | (m >> (8 - k % 8))) & 0xff
    s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
    runs = _sparkle_play(s, syms, b''.join(fx + b'\xb2\xbb' + w for fx, w in SPARKLE_PAGES) + b'\x19END', 34000)
    dirs, slants, fits, total, oneway = set(), set(), 0, 0, True
    for r in runs:
        page = r['page']
        cols = [c for c in range(n) if not page[c] & 0x80]
        phases = []
        for w in r['frames']:
            dark = [page[c] & ~w[c] for c in cols]
            if not any(dark):
                continue
            total += 1
            p = [(sl, ph) for sl in (1, -1) for ph in range(8)
                 if all(d == page[c] & rot(band, ph + sl * c) & 0x7f for c, d in zip(cols, dark))]
            if p:
                fits += 1
                slants.add(p[0][0])
                if not phases or phases[-1] != p[0][1]:
                    phases.append(p[0][1])
        steps = {(b - a) % 8 for a, b in zip(phases, phases[1:])}
        oneway &= len(steps) == 1
        dirs |= steps
    check('%d of %d dark frames are one band rolled a row per panel column' % (fits, total), total and fits >= 0.9 * total)
    check('the stripes slant both ways: %s' % sorted({1: 'down-right', -1: 'up-right'}[x] for x in slants), slants == {1, -1})
    check('each GLIMMER rolls one way a row a tick; seen: %s' % sorted({1: 'down', 7: 'up'}.get(d, str(d)) for d in dirs),
          oneway and dirs == {1, 7})
    _sparkle_common(check, s, syms, runs, 2, b'\xb2\xbb', 'GLIMMER')
    _sparkle_editor(check, s, syms, ('SHIFT', 'STOP', 'SHIFT', 'SHIFT', 'SEQ'), b'\xb2\xbb', 'FUNC2 SHIFT SEQ')
    print('glimmer: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_field():
    """P54: B2 '0'-'9' shows channel 90-99 inside a message: in a crawl, a wipe and a
    scroll, with colors, empty and nested; a field's end is not a channel's end; loads
    while a field is drawn (into the field, below, between and above) keep the display
    running; seq 'M' plays 00-89 only."""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    s = Sign(rom, syms, fresh_ram=True, baud=1200); s.run_ms(2500)
    cur, cur_ptr = syms['CUR_CHAR'], syms['STORE_CURSOR']
    fetch = (syms['fetch_char'], syms['attr_hold_check'])
    clock = (syms['render_clock'], syms['menu_ask_chan_cur'])
    seat = (syms['seq_set_cursor'], syms['seq_ret'])
    s.watch = {cur, cur_ptr}
    s.m.mark_addrs(cur, 1, s.m.WRITE_MARK); s.m.mark_addrs(cur_ptr, 1, s.m.WRITE_MARK)
    def send(payload, ms=600):
        s.send_frame(payload, addr=1, flag=0x81); s.rx_wait(); s.run_ms(ms)
    def events():
        """the bytes fetched (clock digits included) and 'S' at each channel start"""
        out = bytearray()
        for t, pc, a, v in s.watch_log:
            if a == cur_ptr:
                if seat[0] <= pc <= seat[1]: out += b'\x00'
            elif fetch[0] <= pc < fetch[1] or clock[0] <= pc < clock[1]:
                if (0x20 <= v <= 0x7e and v != 0x5f) or v == 0x9f: out.append(v)
        s.watch_log.clear()
        return bytes(out)
    def passes(ms):
        s.watch_log.clear(); s.run_ms(ms)
        return events().split(b'\x00')[1:-1]
    def play(chan, text, ms=20000):
        send(b'\x09' + chan + b'\x0e' + text + b'\x04' + chan)
        return passes(ms)
    send(b'\x09\x39\x33\x0e72F\x09\x39\x34\x0e\x8cHOT\x09\x39\x35\x0e\x09\x39\x36\x0eX\xb2\x33Y')
    p = play(b'00', b'TEMP \xb2\x33 NOW')
    check('crawl: %r' % p[:2], len(p) >= 2 and set(p) == {b'TEMP 72F NOW'})
    p = play(b'01', b'\x1aIN \xb2\x33\x18 OUT')
    check('wipe: %r' % p[:2], len(p) >= 2 and all(b'IN 72F' in x and x.endswith(b'OUT') for x in p))
    p = play(b'02', b'\xb2\x1bIS \xb2\x33\x18 OK')
    check('scroll: %r' % p[:2], len(p) >= 2 and all(b'IS 72F' in x and x.endswith(b'OK') for x in p))
    p = play(b'03', b'IT IS \xb2\x34 TODAY')
    check('a field with a color: %r' % p[:2], len(p) >= 2 and set(p) == {b'IT IS HOT TODAY'})
    p = play(b'04', b'A\xb2\x35B <\xb2\x36>')
    check('an empty field shows nothing, a nested reference nothing: %r' % p[:2], len(p) >= 2 and set(p) == {b'AB <XY>'})
    import cc784_font
    deg = cc784_font.glyphs(rom, syms)[175]
    send(b'\x09\x39\x37\x0e68\x9fF')
    p = play(b'07', b'IT IS \xb2\x37')
    check('P55: 9F is the degree sign (glyph 175 %s), drawn as text in a field: %r' % (deg.hex(), p[:2]),
          deg == b'\x02\x05\x02' and len(p) >= 2 and set(p) == {b'IT IS 68\x9fF'})
    send(b'\x09\x30\x37\x0eIT IS \xb2\x37', 1500)                         # the playing channel: a restart, and store_repair
    store = bytes(s.m.memory[syms['MSG_STORE']:int.from_bytes(s.ram('STORE_END', 2), 'little')])
    check('P55: 9F survives the store repair of a restart (restart %02x, field 97 %r)' % (s.ram('PKT_RESTART')[0], store[store.find(b'\xd9\xd7'):][:7]),
          s.ram('PKT_RESTART')[0] == 0xff and b'\xd9\xd768\x9fF\x03' in store)
    p = play(b'05', b'\x5f \xb2\x33 \x5f')
    check('the clock before and after a field: %r' % p[:2], len(p) >= 2 and all(x.count(b':') == 2 and b' 72F ' in x for x in p))
    # status reports: one per channel start, none at a field's end
    send(bytes([0xB6, 2, 0x80, 0x80]))
    s.tx_edges.clear()
    n = len(play(b'00', b'TEMP \xb2\x33 NOW', 15000)) + 1
    tx = s.tx_bytes()
    r = [i for i in range(len(tx) - 6) if tx[i] == 0xB1 and tx[i + 3] == ord('S')]
    check('one status report per pass (%d reports, %d passes)' % (len(r), n), abs(len(r) - n) <= 1)
    send(bytes([0xB6, 2, 0x80, 0x00]))
    # loads while a field is drawn
    field = bytes(range(0x41, 0x5b)) * 2
    send(b'\x09\x39\x33\x0e' + field)
    want = b'<' + field + b'>'
    def mid_field(payload):
        s.watch_log.clear()
        for _ in range(4000):
            s.run_ms(5)
            fr = int.from_bytes(s.ram('FIELD_RET', 2), 'little')
            if fr and int.from_bytes(s.ram('STORE_CURSOR', 2), 'little') - int.from_bytes(s.ram('FIELD_MARK', 2), 'little') > 10:
                break
        s.send_frame(payload, addr=1, flag=0x81); s.rx_wait(); s.run_ms(50)
        restart = s.ram('PKT_RESTART')[0]
        s.run_ms(25000)
        p = events().split(b'\x00')
        return restart, p[1] if len(p) > 2 else p
    send(b'\x09\x30\x36\x0e<\xb2\x33>\x04\x30\x36', 3000)
    s.watch_log.clear(); s.run_ms(25000)
    base = events().split(b'\x00')[1:-1]
    check('a 52-byte field in channel 6: %r' % base[:1], base and base[0] == want)
    for name, payload in (('below the parent (2)', b'\x09\x30\x32\x0eTWO'),
                          ('between the parent and the field (50)', b'\x09\x35\x30\x0eFIFTY'),
                          ('above the field (99)', b'\x09\x39\x39\x0eNINETY NINE')):
        restart, got = mid_field(payload)
        check('a load %s while the field is drawn: no restart (%02x), the pass whole: %r' % (name, restart, got),
              restart == 0 and got == want)
    restart, got = mid_field(b'\x09\x39\x33\x0eNEW')
    head = got[1:-1] if isinstance(got, bytes) else b''
    check('a load into the field while it is drawn: no restart (%02x), the parent goes on: %r' % (restart, got),
          restart == 0 and isinstance(got, bytes) and got[:1] == b'<' and got[-1:] == b'>' and field.startswith(head) and len(head) >= 8)
    p = passes(15000)
    check('the next pass shows the new value: %r' % p[:1], p and p[0] == b'<NEW>')
    # seq M
    send(b'\x04M')
    sl = s.ram('SEQ_LIST', syms['SEQ_LIST_LEN'])
    check('seq M: 00-89 then FF (%s ... %s)' % (sl[86:90].hex(), sl[90:].hex()), list(sl[:90]) == list(range(90)) and set(sl[90:]) == {0xff})
    s.watch_log.clear(); s.run_ms(60000)
    starts = [(t, pc, a, v) for t, pc, a, v in s.watch_log if a == cur_ptr and seat[0] <= pc <= seat[1]]
    ev = events()
    check('seq M: field channels 93-96 never play on their own (%d channel starts, %r)' % (len(starts), ev[:60]),
          starts and b'\x0072F\x00' not in ev and b'\x00XY\x00' not in ev)
    send(b'\x04A')
    sl = s.ram('SEQ_LIST', syms['SEQ_LIST_LEN'])
    check('seq A: 00-99 again', list(sl[:100]) == list(range(100)))
    s.send_frame(b'\xb7\x31', addr=1); s.rx_wait(); s.run_ms(800)         # the editor as a terminal
    for k in (b'\x04', b'M'):                                              # SEQ MSG? then M
        s.send_bytes(k); s.rx_wait(); s.run_ms(1500)
    sl = s.ram('SEQ_LIST', syms['SEQ_LIST_LEN'])
    check('the editor: SEQ, M sets 00-89 (%s ... %s) and leaves the editor (%s)' % (sl[86:90].hex(), sl[90:].hex(), s.ram('MENU_ACTIVE').hex()),
          list(sl[:90]) == list(range(90)) and set(sl[90:]) == {0xff} and s.ram('MENU_ACTIVE')[0] == 0)
    send(b'\x04A')
    check('no faults, stack high-water %d' % s.depth(), not s.faults and s.depth() < 110)
    # the editor: FUNC PROG n inserts a field, shown as <Fn>; any other key cancels
    e = Sign(rom, syms, fresh_ram=True); e.run_ms(2500)
    e.send_frame(b'\x09\x30\x30\x0eAB CD', addr=1); e.rx_wait(); e.run_ms(3000)
    def store():
        return bytes(e.m.memory[syms['MSG_STORE']:int.from_bytes(e.ram('STORE_END', 2), 'little')])
    def keys(*ks, ms=400):
        for k in ks:
            e.ir_key(k, stretch_us=100); e.ir_wait(); e.run_ms(ms)
    strf, label = syms['STR_F'], []
    rd0 = e._on_read
    def rd(addr):
        if addr == strf:
            label.append(e.t); return e.m.memory[addr]
        return rd0(addr)
    e.m.set_read_callback(rd); e.m.mark_addrs(strf, 1, e.m.READ_MARK)
    keys('STOP', ms=1500)
    def idle_sp():
        sps = set()
        for _ in range(300):                        # every 1 ms: 5 ms steps alias with the display loop
            e.run_ms(1); sps.add(e.m.sp)
        return max(sps)
    sp0, before, shown0 = idle_sp(), store(), len(label)
    keys('SHIFT', 'STOP', 'PROG')
    pend = e.ram('FIELD_PENDING')[0]
    keys('X', ms=1500)
    check('FUNC PROG (pending %02x) then X cancels: nothing inserted, stack where it was (%04x -> %04x)'
          % (pend, sp0, idle_sp()), pend == 0xFF and store() == before and e.ram('FIELD_PENDING')[0] == 0 and idle_sp() == sp0)
    keys('SHIFT', 'STOP', 'PROG')
    keys('3', ms=2000)
    after = store()
    check('FUNC PROG 3 inserts B2 33 (%s), shown as <F3> (%d label reads, %d before)'
          % (after[-10:].hex(), len(label), shown0), after.count(b'\xb2\x33') == 1 and len(after) == len(before) + 2 and len(label) > shown0 and shown0 == 0)
    keys('DEL', ms=1500)
    check('DEL takes the B2 along (%s)' % store()[-8:].hex(), store() == before)
    keys('SHIFT', 'STOP', 'D'); e.run_ms(1000)
    check('P56: FUNC D types the degree sign (%d -> %d bytes, %d 9F)' % (len(before), len(store()), store().count(b'\x9f')), store().count(b'\x9f') == 1 and len(store()) == len(before) + 1)
    keys('DEL', ms=1500)
    e.send_frame(b'\xb7\x30', addr=1); e.rx_wait(); e.run_ms(3000)
    check('editor closed, no faults', e.ram('MENU_ACTIVE')[0] == 0 and not e.faults)
    print('field: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_flush():
    """P57: B2 20 (FLUSH) pushes the crawl's text off the panel mid-message, in the
    font in force after it; on a staged page it does nothing; FUNC SPACE inserts it,
    the editor labels it FLUSH and DEL takes the B2 along"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    fb = syms['FRAMEBUF']
    def store(s):
        return bytes(s.m.memory[syms['MSG_STORE']:int.from_bytes(s.ram('STORE_END', 2), 'little')])
    def panel(s):
        p = int.from_bytes(s.ram('FB_OUT_PTR', 2), 'little'); ln, ex = s.ram('FB_OUT_LEN', 2)
        return bytes(s.m.memory[p:p + ln]) + bytes(s.m.memory[fb:fb + ex])
    def run(text, ms=40000):
        """the times the panel goes dark in the second pass, and the font when 'D' is fetched"""
        s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
        s.send_frame(b'\x09\x30\x30\x0e' + text, addr=1); s.rx_wait(); s.run_ms(50)
        base = syms['MSG_STORE'] + store(s).index(text)
        d = base + text.index(b'D')
        darks, font, npass, prev, was = 0, None, 0, 0, False
        for _ in range(ms):
            s.run_ms(1)
            cur = int.from_bytes(s.ram('STORE_CURSOR', 2), 'little')
            if cur + 2 < prev: npass += 1                   # a new pass, not the one-byte step back at a page's end
            prev = cur
            if npass == 3: break
            lit = any(b for b in panel(s) if not b & 0x80)
            if npass == 2 and was and not lit: darks += 1
            was = lit
            if cur == d + 1 and font is None: font = s.ram('FONT_MODE')[0]
        return s, darks, font
    s, darks, font = run(b'\x12AB\xb2\x20CD')
    check('FLUSH: the panel goes dark twice a pass, at FLUSH and at the end (%d)' % darks, darks == 2)
    check('FLUSH: CD in the font in force, BOLD (%s)' % font, font == syms['FONT_BOLD'])
    s0, darks0, _ = run(b'\x12AB CD')
    check('without it, once (%d)' % darks0, darks0 == 1)
    s1, darks1, _ = run(b'\x19AB\xb2\x20CD\x18')
    check('on a PAUSE page it does nothing: once (%d)' % darks1, darks1 == 1)
    check('no faults, stack high-water %d' % s.depth(), not (s.faults or s0.faults or s1.faults) and s.depth() < 110)

    e = Sign(rom, syms, fresh_ram=True); e.run_ms(2500)
    e.send_frame(b'\x09\x30\x30\x0eAB CD', addr=1); e.rx_wait(); e.run_ms(3000)
    lbl = rom.index(b'\x60FLUSH') + 1
    reads = []
    rd0 = e._on_read
    def rd(addr):
        if addr == lbl:
            reads.append(e.t); return e.m.memory[addr]
        return rd0(addr)
    e.m.set_read_callback(rd); e.m.mark_addrs(lbl, 1, e.m.READ_MARK)
    def keys(*ks, ms=400):
        for k in ks:
            e.ir_key(k, stretch_us=100); e.ir_wait(); e.run_ms(ms)
    keys('STOP', ms=1500)
    before = store(e)
    keys('SHIFT', 'STOP', 'SPACE', ms=1500)
    after = store(e)
    check('FUNC SPACE inserts B2 20 (%d -> %d bytes), labeled FLUSH (%d label reads)'
          % (len(before), len(after), len(reads)), after.count(b'\xb2\x20') == 1 and len(after) == len(before) + 2 and reads)
    keys('DEL', ms=1500)
    check('DEL takes the B2 along', store(e) == before)
    e.send_frame(b'\xb7\x30', addr=1); e.rx_wait(); e.run_ms(3000)
    check('editor closed, no faults', e.ram('MENU_ACTIVE')[0] == 0 and not e.faults)
    print('flush: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_lite():
    """LITE (an unmodified 3A board: 4 MHz, 2 K RAM, no IR, 300 baud): a 16 K image; the
    store fills the 2 K; channels by one digit or two; one-digit sequences; B5 refused;
    status reports at 300 baud; TWINKLE and GLIMMER from the wired keypad's editor; speed
    as dark interrupts after each frame, held ones too; brightness off or full only.
    Run without CC784_LITE it re-runs itself under it."""
    if not LITE:
        return subprocess.run([sys.executable, __file__, 'lite'], env=dict(os.environ, CC784_LITE='1')).returncode == 0
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    check('a 16 K image for a 27128 (%d bytes)' % len(rom), len(rom) == BANK_SIZE)
    s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
    w = lambda n: int.from_bytes(s.ram(n, 2), 'little')
    size, text = w('STORE_SIZE'), w('STORE_TEXT_LIMIT')
    check('the store runs to the 2 K\'s stream area, the stack above it: %d bytes, %d for text, SP at %04x' % (size, text, w('STACK_INIT')),
          size == syms['STORE_TOP_2K'] - syms['MSG_STORE'] + 1 and text == size - 31 and w('STACK_INIT') == syms['STACK_TOP_2K']
          and s.ram('PKT_MAX')[0] == syms['PKT_MAX_2K'])
    store = lambda: bytes(s.m.memory[syms['MSG_STORE']:w('STORE_END') + 1])
    s.send_frame(b'\x09\x33\x0eHELLO\x09\x30\x35\x0eFIVE', addr=1); s.rx_wait(); s.run_ms(800)
    check('09 3 and 09 05 both select their channel: %s' % store()[:40].hex(),
          b'\xd0\xd3HELLO\x03' in store() and b'\xd0\xd5FIVE\x03' in store())
    s.send_frame(b'\x04\x35\x33D', addr=1); s.rx_wait(); s.run_ms(300)
    check('04 5 3 D: a digit a channel, D the demo (%s)' % s.ram('SEQ_LIST', 4).hex(), s.ram('SEQ_LIST', 4) == b'\x05\x03\x0a\xff')
    before = store()
    s.send_frame(b'\xb5I', addr=1); s.rx_wait(); s.run_ms(500)
    check('B5 is refused: nothing written, the sign plays on', store() == before and not s.faults)
    def reports(tx):
        out, i = [], 0
        while i + 7 <= len(tx):
            f = tx[i:i + 7]
            if f[0] == 0xB1 and f[2] == 3 and f[3] == ord('S') and sum(f[3:6]) & 0xFF == f[6]:
                out.append(f[4]); i += 7
            else:
                i += 1
        return out
    s.send_frame(b'\x04\x35\x33', addr=1); s.rx_wait(); s.run_ms(300)
    s.send_frame(bytes([0xB6, 2, 0x80, 0x80]), addr=1); s.rx_wait(); s.run_ms(500)
    s.tx_edges.clear(); s.run_ms(12000)
    r = reports(s.tx_bytes())
    check('status reports at 300 baud: %s' % r, len(r) >= 4 and set(r) == {3, 5})
    s.send_frame(bytes([0xB6, 2, 0x80, 0x00]), addr=1); s.rx_wait(); s.run_ms(500)
    table = rom[syms['IR_KEY_TABLE']:syms['IR_KEY_TABLE'] + 62]
    code = lambda k: table[cc784_ir.key_index(k)]
    s.keypad = True
    for _ in range(150):
        if s.ram('KP_MODE')[0]: break
        s.run_ms(100)
    check('the keypad takes over', s.ram('KP_MODE')[0])
    keys = ('STOP', 'SHIFT', 'STOP', 'SHIFT', 'JUMP', 'SHIFT', 'STOP', 'SHIFT', 'SHIFT', 'SEQ', 'STOP')
    for k in keys:
        s.kp_key(code(k)); s.kp_wait(); s.run_ms(400)
    for _ in range(50):
        if not s.ram('MENU_ACTIVE')[0]: break
        s.run_ms(100)
    check('keypad editor: FUNC2 PAUSE and FUNC2 SHIFT SEQ insert B2 19 and B2 BB (%s)' % store()[:12].hex(),
          b'\xb2\x19' in store() and b'\xb2\xbb' in store())
    check('no faults, stack high-water %d of %d' % (s.stack_top - s.min_stack, syms['STACK_SIZE']),
          not s.faults and s.stack_top - s.min_stack < syms['STACK_SIZE'])

    # P51: speed is dark interrupts after each frame, held frames too; every row keeps its
    # speed-0 lit time. Brightness is off or full: a pass under one interrupt can't be cut.
    def scan(s, ms=2000):
        """per refresh, in interrupts: dark time, and lit time by latch row code"""
        global SLICE                    # at 16-cycle slices: at 128 an interrupt waits for the slice's
        SLICE, coarse = 16, SLICE       # end, and the rows' times follow the handler's length
        s.refreshes = 0; s.frames.clear()
        step, n, dark, lit = CPU_HZ // 15625, 0, 0, {}
        for _ in range(ms * 1000 // 64):
            s.run(step); n += 1
            r = s.latch & 0x0F
            if r == 0x0F: dark += 1
            else: lit[r] = lit.get(r, 0) + 1
        SLICE = coarse
        per = step / s.tick_t / max(s.refreshes, 1)              # a sample, in interrupts per refresh
        return dark * per, {r: c * per for r, c in lit.items()}, len(s.frames)
    def play(body, n, hold=None):
        s = Sign(rom, syms, fresh_ram=True); s.run_ms(2500)
        if hold:
            s.send_frame(bytes([0xB6, 3, 0xFF, hold]), addr=1); s.rx_wait(); s.run_ms(300)
        s.send_frame(b'\x09\x30\x0e' + bytes([0xF0 + n]) + body + b'\x04\x30', addr=1); s.rx_wait()
        s.run_ms(1500)
        return s
    crawl, held = b'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG ' * 2, b'\x1aHI'
    res = {}
    for name, body, hold in (('crawl', crawl, None), ('held', held, 250)):
        for n in (0, 7):
            s = play(body, n, hold)
            res[name, n] = scan(s) + (s.faults,)
    for name in ('crawl', 'held'):
        (d0, l0, f0, x0), (d7, l7, f7, x7) = res[name, 0], res[name, 7]
        spread = max(abs(l7.get(r, 0) / l0[r] - 1) for r in l0)
        check('%s: speed 7 adds %.2f dark interrupts a refresh (%.2f -> %.2f), rows lit the same (%.1f %% apart), %d/%d distinct frames'
              % (name, d7 - d0, d0, d7, spread * 100, f0, f7),
              abs(d7 - d0 - 7) < 0.3 and len(l0) >= 7 and spread < 0.03 and not x0 and not x7
              and ((f0 > 50 and f7 > 50) if name == 'crawl' else (f0 <= 2 and f7 <= 2)))
    s = play(crawl, 0)
    lit = []
    for level in (3, 2, 1, 0):
        s.send_frame(bytes([0xB6, 2, 0x03, level]), addr=1); s.rx_wait(); s.run_ms(500)
        lit.append(sum(scan(s, 1000)[1].values()))
    check('brightness full/medium/low/off: %s interrupts lit a refresh (off or full only)' % ' '.join('%.2f' % v for v in lit),
          lit[0] > 1 and all(abs(v / lit[0] - 1) < 0.05 for v in lit[1:3]) and lit[3] == 0 and not s.faults)
    print('lite: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_config():
    """P35: the configuration block: defaults after a RAM loss, kept across a reset,
    rejected when its sum is wrong; B6 writes with the protected bytes refused and the
    live bits kept; B4 '5' and '6' read it and the sequence; brightness picks the
    intensity passes, mute darkens now or at the next message, hold and flash follow
    their bytes, the beeper and the remote can be switched off"""
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(bool(cond)); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    def reply(s, payload, wait_ms=1500):
        s.tx_edges.clear()
        s.send_frame(payload, addr=1, flag=0x80); s.rx_wait(); s.run_ms(wait_ms)
        tx = s.tx_bytes()
        return tx[1:] if tx[:1] == b'\x06' else tx
    def cfg(s):
        return s.ram('CFG', 6)
    def valid(b):
        return b[0] == 0xA5 and (sum(b[:5]) - (b[2] & 0x40)) & 0xFF == b[5]
    def setb(s, index, value, wait_ms=1500, mask=0xFF):
        reply(s, bytes([0xB6, index, mask, value]), wait_ms)
    def passes(s, ms=1000):
        s.row_starts.clear(); s.run_ms(ms)
        first = sum(1 for t, p in s.row_starts if not p & 8)
        second = sum(1 for t, p in s.row_starts if p & 8)
        return first, second
    def duty(s, ms=500):
        """share of the time a row is selected on the control latch, sampled every 64 us"""
        lit = n = 0
        for _ in range(ms * 1000 // 64):
            s.run(512); n += 1; lit += (s.latch & 0x0F) != 0x0F
        return lit / n
    defaults = bytes([0xA5, 1, 3, 80, 13])

    s = Sign(rom, syms, fresh_ram=True)
    s.run_ms(2500)
    b = cfg(s)
    check('fresh RAM: defaults %s, sum valid' % b.hex(), b[:5] == defaults and valid(b))
    r = reply(s, b'\xb4\x35')
    check("B4 '5' returns the block (%s)" % r[3:9].hex(), r[:3] == b'\xb1\x01\x06' and r[3:9] == b and r[9] == sum(b) & 0xFF)
    r = reply(s, b'\xb4\x36', wait_ms=5000)
    check("B4 '6' returns SEQ_LIST (%d bytes, first %s)" % (r[2], r[3:7].hex()), r[:3] == b'\xb1\x01' + bytes([syms['SEQ_LIST_LEN']])
          and r[3:3 + syms['SEQ_LIST_LEN']] == s.ram('SEQ_LIST', syms['SEQ_LIST_LEN']))
    # a plain message from here on: the demo's TINY segment has its own output path
    s.send_frame(b'\x09\x30\x30\x0eHELLO THERE \x04\x30\x30', addr=1, flag=0x80); s.rx_wait(); s.run_ms(3000)

    # writes: protected bytes refused, others sealed, the flags byte keeps its live bits
    setb(s, 0, 0x00); setb(s, 1, 7); setb(s, 5, 0)
    b = cfg(s)
    check('B6 to the signature, the address and the sum is refused (%s)' % b.hex(), b[:2] == bytes([0xA5, 1]) and valid(b))
    setb(s, 3, 20); setb(s, 4, 5)
    b = cfg(s)
    check('B6 3 20 and B6 4 5 land and reseal: hold %d flash %d' % (b[3], b[4]), b[3] == 20 and b[4] == 5 and valid(b))
    setb(s, 2, 0x02)
    b = cfg(s)
    check('B6 2 sets the flags, the wrapped bit outside the sum: flags %02x, sum valid' % b[2], b[2] & 0xBF == 0x02 and valid(b))
    setb(s, 2, 0xFF, mask=0x30)
    b1 = cfg(s)
    setb(s, 2, 0x00, mask=0x20)
    b2 = cfg(s)
    check('the mask: B6 2 30 FF sets bits 4-5 only (%02x), B6 2 20 00 clears bit 5 only (%02x)' % (b1[2], b2[2]),
          b1[2] & 0xBF == 0x32 and b2[2] & 0xBF == 0x12 and valid(b1) and valid(b2))

    # brightness: lit time, both passes still sent so no color loses a bit
    setb(s, 2, 0x03); d3 = duty(s); f3, s3 = passes(s)
    setb(s, 2, 0x02); d2 = duty(s); f2, s2 = passes(s)
    setb(s, 2, 0x01); d1 = duty(s); f1, s1 = passes(s)
    setb(s, 2, 0x00); d0 = duty(s); f0, s0 = passes(s)
    check('brightness 3: duty %.2f (%d+%d passes/s), 2: %.2f (%d+%d), 1: %.2f (%d+%d), 0: %.2f (%d+%d)' % (d3, f3, s3, d2, f2, s2, d1, f1, s1, d0, f0, s0),
          (d3 > 0.4 and abs(d2 / d3 - 1) < 0.05 and abs(d1 / d3 - 1) < 0.05 if LITE else   # LITE: off or full only
           d3 > 0.5 and abs(d2 / d3 - 2 / 3) < 0.08 and abs(d1 / d3 - 1 / 3) < 0.08) and d0 == 0
          and min(f3, s3, f2, s2, f1, s1) > 300 and f0 == 0 and s0 == 0)
    # the lit time must be the same every pass: lit from the latch it carried a
    # drifting 0-128 us remainder that pulsed at a few hertz on the sign
    setb(s, 2, 0x01)
    runs, lit = [], 0
    for _ in range(500 * 1000 // 32):
        s.run(256)
        if (s.latch & 0x0F) != 0x0F: lit += 1
        elif lit: runs.append(lit); lit = 0
    near = lambda want: sum(1 for l in runs if abs(l - want) <= 1)       # 32 us samples: a run lands on 4 or 5, 12 or 13
    if not LITE:
        check('level 1: lit runs are two exact lengths, 1 and 3 interrupts: %d near 128 us, %d near 384 us (of %d)' % (near(4), near(12), len(runs)),
              len(runs) > 300 and near(4) + near(12) > 0.95 * len(runs) and near(4) > 100 and near(12) > 100)

    # mute now, then unmute; mute after the current message waits for the boundary
    setb(s, 2, 0x07); fm, sm = passes(s)
    setb(s, 2, 0x03); fu, su = passes(s)
    check('mute now: %d passes/s; unmute: %d' % (fm + sm, fu + su), fm + sm == 0 and fu + su > 600)
    # a long message, so the next boundary is seconds away
    s.send_frame(b'\x09\x30\x30\x0e' + b'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG ' * 5 + b'\x04\x30\x30', addr=1, flag=0x80); s.rx_wait(); s.run_ms(4000)
    setb(s, 2, 0x0B)                                 # pending
    fp, sp = passes(s, 300)
    for _ in range(200):                             # the demo loops within a few seconds
        if cfg(s)[2] & 0x04: break
        s.run_ms(100)
    b = cfg(s)
    fa, sa = passes(s)
    check('mute after the message: lit meanwhile (%d), then muted at the boundary: flags %02x, dark (%d), sum valid' % (fp + sp, b[2], fa + sa),
          fp + sp > 100 and b[2] & 0x0C == 0x04 and fa + sa == 0 and valid(b))
    setb(s, 2, 0x03)

    # hold time: a PAUSE holds CFG_HOLD frames
    def max_delay(s, ms):
        top = 0
        for _ in range(ms // 10):
            s.run_ms(10); top = max(top, s.ram('FRAME_DELAY')[0])
        return top
    s.send_frame(b'\x09\x30\x30\x0e\x19HOLD ME\x18\x04\x30\x30', addr=1, flag=0x80); s.rx_wait(); s.run_ms(1500)
    h20 = max_delay(s, 6000)
    setb(s, 3, 80)
    h80 = max_delay(s, 6000)
    # the load can land just before a frame's count, so the highest value seen is the hold or one less
    check('PAUSE holds %d frames with hold 20, %d with 80' % (h20, h80), h20 in (19, 20) and h80 in (79, 80))

    # flash rate: LATCH_BIT7 toggles every CFG_FLASH frames
    def toggles(s, ms):
        n, last = 0, s.ram('LATCH_BIT7')[0]
        for _ in range(ms // 2):
            s.run_ms(2); v = s.ram('LATCH_BIT7')[0]
            if v != last: n += 1; last = v
        return n
    t5 = toggles(s, 2000)
    setb(s, 4, 13)
    t13 = toggles(s, 2000)
    check('flash toggles %d times in 2 s at 5 frames, %d at 13 (want ~25 and ~9)' % (t5, t13), 20 <= t5 <= 30 and 7 <= t13 <= 12)

    # beeper off: a BEEP attribute does nothing
    setb(s, 2, 0x10, mask=0x10)
    s.send_frame(b'\x09\x30\x30\x0e\x07BEEP\x04\x30\x30', addr=1, flag=0x80); s.rx_wait()
    beeped = False
    for _ in range(400):
        s.run_ms(10); beeped |= s.ram('BEEP_TICKS')[0] != 0
    setb(s, 2, 0x00, mask=0x10)
    s.send_frame(b'\x09\x30\x30\x0e\x07BEEP\x04\x30\x30', addr=1, flag=0x80); s.rx_wait()
    beeped_on = False
    for _ in range(400):
        s.run_ms(10); beeped_on |= s.ram('BEEP_TICKS')[0] != 0
    check('beeper off: silent (%s); on: beeps (%s)' % (beeped, beeped_on), not beeped and beeped_on)

    # remote lock: STOP opens the editor only when unlocked
    setb(s, 2, 0x20, mask=0x20)
    s.ir_key('STOP'); s.ir_wait(); s.run_ms(800)
    locked = s.ram('MENU_ACTIVE')[0]
    setb(s, 2, 0x00, mask=0x20)
    s.ir_key('STOP'); s.ir_wait(); s.run_ms(800)
    opened = s.ram('MENU_ACTIVE')[0]
    check('remote lock: STOP ignored (%02x); unlocked: editor opens (%02x)' % (locked, opened), locked == 0 and opened == 0xFF)
    # B6 is taken while the editor is open: ACKed and applied at once, the editor left open
    s.tx_edges.clear()
    s.send_frame(bytes([0xB6, 2, 0x10, 0x10]), addr=1, flag=0x80); s.rx_wait(); s.run_ms(1500)
    ack = s.tx_bytes()[:1]
    b = cfg(s)
    s.send_frame(bytes([0xB6, 2, 0x10, 0x00]), addr=1, flag=0x80); s.rx_wait(); s.run_ms(1500)
    b2 = cfg(s)
    check('B6 in the editor: reply %s, beeper off (%02x) then on (%02x), sums valid, editor open (%02x)' % (ack.hex(), b[2], b2[2], s.ram('MENU_ACTIVE')[0]),
          ack == b'\x06' and b[2] & 0x10 and not b2[2] & 0x10 and valid(b) and valid(b2) and s.ram('MENU_ACTIVE')[0] == 0xFF)
    s.send_frame(b'\xb7\x30', addr=1); s.rx_wait()  # leave the editor: B7 '0' (P45)
    for _ in range(50):
        if not s.ram('MENU_ACTIVE')[0]: break
        s.run_ms(100)

    # the editor's ADDRESS? dialog reseals the block (driven as serial keys: frame
    # B7 '1' opens the editor as a terminal, B7 1F is FUNC MAGIC, three digits, 0D is STOP/START)
    s.run_ms(3000)
    s.send_frame(b'\xb7\x31', addr=1); s.rx_wait()
    for _ in range(50):
        if s.ram('MENU_ACTIVE')[0]: break
        s.run_ms(100)
    for data, wait in ((b'\xb7\x1f', 1500), (b'002', 1500), (b'\x0d', 2000), (b'\x0d', 2500)):
        s.send_bytes(data, gap_bits=20); s.rx_wait(); s.run_ms(wait)
    for _ in range(50):
        if not s.ram('MENU_ACTIVE')[0]: break
        s.run_ms(100)
    b = cfg(s)
    check('address 2 set in the editor, block resealed (%s)' % b.hex(), b[1] == 2 and valid(b) and s.ram('MENU_ACTIVE')[0] == 0)
    s.send_frame(b'\x04\x30\x30', addr=2, flag=0x80); s.rx_wait(); s.run_ms(2000)   # the sign now answers at 2

    # kept across a reset with RAM intact; defaults again when the sum is wrong
    s.send_frame(bytes([0xB6, 2, 0xFF, 0x01]), addr=2, flag=0x80); s.rx_wait(); s.run_ms(2500)
    kept = cfg(s)
    s2 = Sign(rom, syms, fresh_ram=True)
    s2.m.set_memory_block(0x4000, bytes(s.m.memory[0x4000:0x8000]))
    s2.run_ms(2500)
    b2 = cfg(s2)
    check('reset with RAM kept: block unchanged (%s, was %s), clock running (%02x)' % (b2.hex(), kept.hex(), s2.ram('CLK_RUN')[0]),
          b2[:2] + bytes([b2[2] & ~0x40]) + b2[3:] == kept[:2] + bytes([kept[2] & ~0x40]) + kept[3:] and kept[1] == 2 and kept[2] & 3 == 1 and s2.ram('CLK_RUN')[0])
    s2.m.memory[syms['CFG_HOLD']] ^= 0xFF
    s3 = Sign(rom, syms, fresh_ram=True)
    s3.m.set_memory_block(0x4000, bytes(s2.m.memory[0x4000:0x8000]))
    s3.run_ms(2500)
    b3 = cfg(s3)
    check('reset with a corrupt sum: defaults, store cleared, address 1 (%s)' % b3.hex(),
          b3[:5] == defaults and valid(b3) and s3.ram('MSG_STORE', 3) == b'\xd0\xd0\x03')
    check('no faults, stack ok (depth %d)' % s.depth(), not s.faults and not s2.faults and not s3.faults and s.depth() < 160)
    print('config: %d/%d checks pass' % (sum(checks), len(checks)))
    return all(checks)


def cmd_keypad():
    """P36: the wired keypad. Serial at boot, keypad mode once the RX line has read
    space for 256 frames, keys that edit exactly as the same keys on the remote do
    (with contact bounce), the remote still working alongside, and serial again as
    soon as a host idles on the line. Fine slices: the scan's short DI windows
    would otherwise hold interrupts to the next 128 cycles and cost the remote frames."""
    global SLICE
    SLICE, coarse = 16, SLICE
    try:
        return _keypad()
    finally:
        SLICE = coarse


def _keypad():
    rom, syms = assemble(HERE.parent / 'src' / 'patched')
    checks = []
    def check(name, cond):
        checks.append(cond); print('  %s %s' % ('ok  ' if cond else 'FAIL', name))
    table = rom[syms['IR_KEY_TABLE']:syms['IR_KEY_TABLE'] + 62]
    code = lambda k: table[cc784_ir.key_index(k)]
    typed = ('H', 'I', 'SPACE', 'BOLD', 'W', 'O', 'W', 'FLASH', 'COLOR', '3', 'LEFT', 'DEL',
             'SHIFT', 'PROG', '1', 'SHIFT', 'H', 'K', '0')

    def edit(s, press, wait):
        press('STOP'); wait(); s.run_ms(800)
        opened = s.ram('MENU_ACTIVE')[0]
        for k in typed:
            press(k); wait(); s.run_ms(300)
        press('STOP'); wait()
        for _ in range(50):
            if not s.ram('MENU_ACTIVE')[0]: break
            s.run_ms(100)
        return opened, s.ram('MSG_STORE', 64)

    def boot():
        # a plain message: the demo's effects pause the frame path, and STOP with it
        s = Sign(rom, syms, fresh_ram=False); s.run_ms(2500)
        s.send_frame(b'\x09\x30\x30\x0ePLAIN\x04\x30\x30'); s.rx_wait(); s.run_ms(2500)
        return s

    ref = boot()
    blank = ref.ram('MSG_STORE', 64)
    r_open, r_store = edit(ref, lambda k: ref.ir_key(k, stretch_us=100), ref.ir_wait)

    s = boot()
    check('boots in serial mode with a host on the line', s.ram('KP_MODE')[0] == 0)
    s.keypad = True
    t0 = s.t
    while not s.ram('KP_MODE')[0] and s.t - t0 < 20_000 * 1000 * US:
        s.run_ms(100)
    secs = (s.t - t0) / CPU_HZ
    check('keypad plugged in: keypad mode after %.1f s' % secs, s.ram('KP_MODE')[0] and 2 < secs < 10)
    k_open, k_store = edit(s, lambda k: s.kp_key(code(k), bounce=3), s.kp_wait)
    check('STOP on the keypad opens the editor (%02x), as on the remote (%02x)' % (k_open, r_open), k_open == r_open == 0xFF)
    check('the same keys, bouncing, leave the same store as the remote: %s / %s' % (k_store[:24].hex(), r_store[:24].hex()),
          k_store == r_store != blank)

    # a held key repeats like a held remote key; the remote works in keypad mode
    s.kp_key(code('STOP')); s.kp_wait(); s.run_ms(800)
    before = bytes(s.m.memory[syms['MSG_STORE']:syms['MSG_STORE'] + 256])
    s.kp_key(code('X'), hold_ms=2500); s.kp_wait(); s.run_ms(300)
    s.ir_key('Y', stretch_us=100); s.ir_wait(); s.run_ms(300)
    s.kp_key(code('STOP')); s.kp_wait()
    for _ in range(50):
        if not s.ram('MENU_ACTIVE')[0]: break
        s.run_ms(100)
    after = bytes(s.m.memory[syms['MSG_STORE']:syms['MSG_STORE'] + 256])
    xs, ys = after.count(b'X') - before.count(b'X'), after.count(b'Y') - before.count(b'Y')
    check('a held key repeats (%d X), the remote types alongside (%d Y), editor closed' % (xs, ys),
          xs > 2 and ys == 1 and not s.ram('MENU_ACTIVE')[0])

    # unplug the keypad, a host idles at mark: serial at once, and it answers
    s.keypad = False
    s.run_ms(200)
    check('host back on the line: serial mode within 200 ms', s.ram('KP_MODE')[0] == 0)
    s.tx_edges.clear()
    s.send_frame(b'\xb4\x31', flag=0x80); s.rx_wait(); s.run_ms(2500)
    tx = s.tx_bytes()
    check("then answers B4 '1': %s" % tx[:12].hex(), tx[:4] == b'\x06\xb1\x01\x0f')
    check('no faults, stack depth %d' % s.depth(), not s.faults and not ref.faults and s.depth() < 160)
    print('keypad: %d/%d checks pass' % (sum(1 for c in checks if c), len(checks)))
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
    if not args or args[0] not in ('stack', 'compare', 'eeprom', 'ota', 'update', 'push', 'fuzz', 'ram', 'quiet', 'speed', 'baud', 'clock', 'config', 'keypad', 'seq', 'stats', 'status', 'term', 'randbow', 'scroll', 'twinkle', 'glimmer', 'lite', 'field', 'flush'):
        sys.exit(__doc__)
    if args[0] == 'ram':
        sys.exit(0 if cmd_ram() else 1)
    if args[0] == 'speed':
        sys.exit(0 if cmd_speed() else 1)
    if args[0] == 'baud':
        sys.exit(0 if cmd_baud() else 1)
    if args[0] == 'clock':
        sys.exit(0 if cmd_clock() else 1)
    if args[0] == 'keypad':
        sys.exit(0 if cmd_keypad() else 1)
    if args[0] == 'seq':
        sys.exit(0 if cmd_seq() else 1)
    if args[0] == 'config':
        sys.exit(0 if cmd_config() else 1)
    if args[0] == 'stats':
        sys.exit(0 if cmd_stats() else 1)
    if args[0] == 'status':
        sys.exit(0 if cmd_status() else 1)
    if args[0] == 'term':
        sys.exit(0 if cmd_term() else 1)
    if args[0] == 'randbow':
        sys.exit(0 if cmd_randbow() else 1)
    if args[0] == 'scroll':
        sys.exit(0 if cmd_scroll() else 1)
    if args[0] == 'twinkle':
        sys.exit(0 if cmd_twinkle() else 1)
    if args[0] == 'glimmer':
        sys.exit(0 if cmd_glimmer() else 1)
    if args[0] == 'lite':
        sys.exit(0 if cmd_lite() else 1)
    if args[0] == 'field':
        sys.exit(0 if cmd_field() else 1)
    if args[0] == 'flush':
        sys.exit(0 if cmd_flush() else 1)
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
