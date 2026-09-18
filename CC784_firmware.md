# CC784NIR firmware — reference notes

Color Cells CC784NIR LED message display. Firmware in ST M27C256B (32 KB, code
in `0x0000–0x3C20`, rest `0xFF`). Hand-written Z80 assembly, ROM ID string
`78409O1702930205` (read as: model 784, rev 09, 17-02-93, build 0205).

Companion files: `cc784nir.asm` (reassembles byte-identical with sjasmplus),
`CC784NIR_annotated.asm` (listing with addresses/hex and comments),
`CC784_protocol.md` (wire protocol), `cc784.py` / `cc784_esphome.py` (tools),
`CC784_hardware.md` (board).

Confidence key: **[H]** traced instruction by instruction and/or verified on
hardware; **[M]** structure understood, details inferred; **[L]** hypothesis.

---

## 1. Memory map [H]

| Range | Use |
|---|---|
| `0000–3C20` | ROM code + data |
| `3C21–7FFF` | unused (`0xFF`) — free for patches |
| `4000–403F` | **stack** (64 bytes, grows down from `403F`; below `4000` is ROM) |
| `4040–4197` | `FRAMEBUF` — 4 × 86 bytes |
| `4198–41A1` | frame-buffer pointers/temps |
| `41A2–41F7` | `TXBUF` — reply frame buffer (len byte + up to 0x55 data) |
| `41F8–43E1` | variables (see `equ` block in the source) |
| `43CB/43CC` | `MY_ADDRESS` / its complement (RAM-validity check at boot) |
| `43E2–5EF0` | `MSG_STORE` — message store (see §6); `STORE_LIMIT` at `43D8` |
| `5EF0` | `PKT_READY` flag |
| `5EF1–5FF0` | `PKT_BUF` — received payload (≤255 bytes) |
| `5FF1–5FFB` | packet-parser state (`PKT_STATE`, `PKT_CKSUM`, `PKT_FLAG`, `PKT_LEN`, `PKT_VECTOR`, `PKT_ADDR`, `PKT_PTR`, `PKT_REMAIN`) |
| `8000` | memory-mapped write-only **control latch** (`CTRL_LATCH`), shadow copy at `422D` |

I/O ports: `IN C0` (input mux), `OUT 40` (column shift clock), `OUT 48–4F`
(column data, row in A0–A2), `OUT 80` (strobe). See hardware notes.

Data blocks in ROM: `INIT_DATA 0601`, `RX_TIMING 164A`, `TX_TIMING 1654`,
`DEC_TABLE 18E8`, `IR_KEY_TABLE 2427`, `FG_IDX_TABLE 2718`, `BG_IDX_TABLE 2722`,
`IGNORE_TABLE 2D57`, `GLYPH_PTR_TABLE 2D61`, `MENU_STRINGS 2FF3`, `FONT 3135`
(8 bytes/glyph: 7 columns + width), `CHARSET_* 382D–396E`, `DEMO_MESSAGE 396F`.

## 2. Execution architecture [H]

- **Reset** (`0000`): `LD SP,403F`, init routines, `IM 1`, `EI`, jump to `main_loop`.
- **/INT** (`0038` → `int_timer`): 7812.5 Hz (8 MHz crystal ÷1024 via 74HC4020).
  Swaps register banks, increments `TICK6_COUNT`/`TICK1_COUNT`, and *pushes the
  addresses* of `tick6_service` (every 6th tick) and the handler in `TICK_VECTOR`
  (every tick, = IR decoder) so they execute as the ISR "returns" (`EI; RETI`).
  The ISR itself is ~30 cycles; the scheduled routines run with interrupts
  enabled.
- **`tick6_service`** (1302 Hz): serial RX bit engine, serial TX bit engine,
  countdowns, display row refresh, flashing, then `rx_consume` (pop RX FIFO →
  packet parser). Has a re-entrancy guard testing `(IX)==AA && (IY)==55` that is
  effectively dead code (never true in shipped code).
- **/NMI** (`0066` → `clock_tick`): 60 Hz mains zero-cross. Counts `NMI_COUNT`
  to `NMI_PER_SEC`(=60) → seconds → minutes → 12-hour clock with `CLK_PM`.
- **`main_loop`** (`009A`): if `PKT_READY` → `pkt_process`; else render/effect
  step; loop. The rendering engine (`render_next_char`, `attr_dispatch`, `fx_*`)
  runs here.

Timing: one display row refresh is an `OTIR` of 86 bytes (~1,900 T). Serial
bit = 4.33 tick6 = 3.33 ms.

## 3. Serial link [H]

Fully bit-banged. **300 baud is fixed by the tick tables**, not configurable.

- **RX**: `rx_bit_engine` samples `PORT_IN` bit 3 every tick6 (1 = space/start
  bit, i.e. after one inversion of RS-232). Waits for start, samples bits per
  `RX_TIMING` (4,5,4,4,5,…), checks one stop bit (byte dropped on framing
  error), pushes into `RX_FIFO` (8 bytes, `RX_COUNT`). `rx_fifo_get` pops.
- **TX**: `tx_send_byte` queues one byte (`TX_PENDING`, `TX_STATUS` bit 1) and
  spin-waits if busy. `tx_bit_engine` shifts it out on `CTRL_LATCH` **bit 4**
  (1 = space/start, 0 = mark) with `TX_TIMING` (4,4,5,…; stop = 10 ticks ≈ 2.3
  bits). The latch is written through `CTRL_LATCH_SHADOW`; the display refresh
  also read-modify-writes the shadow (`AND 70 / OR row`) and preserves bit 4.

## 4. Packet parser (`pkt_st_*`, `16EF–178C`) [H]

Frame: `B1 addr flag len payload[len] cksum`.

| State | Action |
|---|---|
| idle | byte must be `B1` (and not while a packet is pending) |
| `pkt_st_addr` | → `PKT_ADDR` |
| `pkt_st_flag` | → `PKT_FLAG` (NETCC sends `80`) |
| `pkt_st_len` | → `PKT_LEN`, reset checksum, `PKT_PTR=PKT_BUF`; len 0 skips to cksum |
| `pkt_st_data` | store, `PKT_CKSUM += byte` |
| `pkt_st_cksum` | `E = PKT_CKSUM − byte`. If `PKT_ADDR == 2A` (`*`): no reply. Else if `PKT_ADDR != MY_ADDRESS`: discard silently. Else reply `06` (ACK) if `E==0` else `15` (NAK). If OK and len>0: set `PKT_READY`; **if `PKT_FLAG == 80` jump to `pkt_process` immediately** (from inside `tick6_service`), else return and let `main_loop` do it. |

Checksum = 8-bit sum of payload bytes only. Verified against a 2009 NETCC
capture and live ACKs.

## 5. Packet processing and command set (`pkt_process 2A68`) [H]

`pkt_process`: wait for TX idle, `DI`, `LD SP,403F`, blank display
(`CTRL_LATCH |= 0F`), then walk `PKT_BUF`. Each byte: if in `IGNORE_TABLE`
(`00 01 05 08 0A 0B 0C 1C 1D 7F`) skip; else dispatch:

| Byte | Handler | Effect |
|---|---|---|
| `02 n` | `cmd_02_speed` | insert `F0 \| (n&7)` |
| `03` | `cmd_03_clear_all` | reset the whole store |
| `04 dd…[D/d]` | `cmd_04_sequence` | rebuild `SEQ_LIST` from 2-ASCII-digit channels (00–99) |
| `09 dd` | `cmd_09_channel` | select channel dd; insertion point at its start; dd=100 sets `CHAN_LOCK` |
| `0D` | — | end of packet |
| `0E` | `cmd_0E_delete_text` | delete the selected channel's existing text |
| `15 n` | `cmd_15_fore_idx` | insert `FG_IDX_TABLE[n]` (`8C 8D 8F 87 83 84 8E 80 8B 81`) |
| `16 n` | `cmd_16_back_idx` | insert `BG_IDX_TABLE[n]` (`91 93 93 93 92 90`) |
| `17 hhmm a` | `cmd_17_set_time` | 4 ASCII digits → `CLK_H10..CLK_M1`; `a`=`Y`/`y` AM else PM |
| `1E n` | `cmd_1E_colour_A0` | insert `A0 \| (n&15)` |
| `B3` | `cmd_B3_append` | insertion point → end of selected channel |
| `B4 c` | `cmd_B4_query` | `'0'` ROM ID, `'1'` memory, `'2'` nop, `'3'` dump — **see bug B1** |
| other | `pkt_insert_text` | insert byte into the store at the cursor |

`pkt_process_done` (`2B68`): clear flags, `OUT (40)` pulse, re-init render, jump
to `main_loop` (never returns to the caller — this is why immediate-mode
processing "works" for normal packets).

Query replies (`tx_send_frame 178D`): `B1 MY_ADDRESS len data cksum(data)` —
note: **no flag byte** in replies. `'3'` sends `B1 addr <5 ASCII digits> <store…DA> cksum(store)`.

## 6. Message store format [H]

One contiguous byte stream at `MSG_STORE` (`43E2`) up to `STORE_LIMIT`
(`5EEF`), 6 925 bytes:

```
D0 D0 <text ch 0> 03   D0 D1 <text ch 1> 03  …  D9 D9 <text ch 99> 03   DA
```

- Channel marker = **two bytes `D0+tens`, `D0+units`** (channel 42 → `D4 D2`).
  `03` terminates a channel's text, `DA` the store.
- `store_clear_all` writes 100 empty channels + `DA` = 301 bytes of framing,
  leaving **6 625 bytes of text shared by all channels** (`0x19E1`); there is
  no per-channel limit. `STORE_SIZE` (`0x1B0E` = 6 926) is what `B4 '1'`
  reports; `0x5E8B` = limit − 100 triggers the "100 KEYS LEFT" warning.
- Attribute/colour bytes are stored inline exactly as received.
- **Channel 100 (`0x64`) is the ROM demo message**: `chan_select` returns
  `DEMO_MESSAGE` and `cmd_09` sets `CHAN_LOCK` so inserts are refused. The
  default sequence plays channel 100, hence the demo after a clear.
- `pkt_insert_text`: `store_make_room` advances `STORE_CURSOR`, then `LDDR`
  shifts everything from the cursor **up to `STORE_LIMIT`** (not just to
  `STORE_END`) by one byte and writes the character. ~6 900 byte moves per
  inserted byte with interrupts off (≈20–40 ms); a 250-byte chunk takes
  seconds. Shifting only to `STORE_END` would be ~50× faster (patch candidate).
- **Cursor seating quirk:** `09 dd` alone leaves the cursor on the marker's
  first byte, so a following insert would split the marker. `0E` (re-seats
  at the marker's last byte and deletes old text) or `B3` (seats before the
  `03`) must follow `09 dd` before any text. NETCC always sends `0E`.
- Suspected typo at `2B1F`: `LD (STORE_CURSOR),A` (opcode `32`) where
  `LD (STORE_CURSOR),HL` (`22`) was intended — writes the byte `03` into the
  cursor's low byte if the cursor is on a `03`. Rarely reached with the
  standard command sequences.

## 7. Rendering [M]

`render_next_char` walks the store from `STORE_CURSOR`; `attr_dispatch`
handles: `10` large, `11` normal, `12` bold, `13` italic, `14` flash, `1F`
magic, `06` pause, `07` beep, `03` end of channel, `18` crawl, `19` jump, `1A`
wipe up, `1B` wipe down, `0F` wipe back, `BB` extra effect (unnamed), `BD`
restart, `BE` tiny-font mode. `attr_colour_speed` handles `80–8F` foreground
(`0x80 | red<<2 | green`; names in `MENU_STRINGS`: BLACK D-GRE M-GRE GREEN
D-RED D-YEL D-LIM LIME M-RED D-ORA M-YEL LEMON RED ORANGE GOLD YELLOW), `90–9F`
background, `A0–AF` second colour range, `F0–F7` speed. `B0` remark (skip to
next `B0`), `B8` graphic, `BA` wait-for-key, `BC` rainbow, `5F` time.
Glyphs: `char_to_glyph` → index → `FONT + 8*idx`; extended glyph ranges
`94–9D`, `C0–CF`, `E0–EF`. Movement effects are state machines in `fx_*`
driven from `main_loop` via `EFFECT_VECTOR`.

## 8. IR remote decoder (`ir_*`, `1482–1571`) [H — verified against a capture of the sign's own receiver]

Runs every tick (128 µs) on `PORT_IN` bit 1 (1 = burst present; the receiver
module is active-low and the HC14 inverts it). State machine:

1. idle: line quiet for 130 ticks;
2. leader burst seen, then its end;
3. **21 ticks (2688 µs) after the leader ends** a burst must be present (the
   "start" cell), and **3 ticks later** the line must be quiet;
4. **6 data cells of 8 ticks (1024 µs)**, biphase: sample at tick 4, and at
   tick 8 the level must be the complement or the frame is discarded;
5. `IR_CODE = bits | 0x80` → `0x80–0xBF`. Index `0x3E` (`0xBE`) = **key
   released**.

Measured at the receiver output: leader burst ≈ 810 µs, start burst begins
≈ 3060 µs after the leader starts, half-bit 512 µs; bursts come out ~250 µs
longer than transmitted (receiver stretch) and the firmware's sample points sit
where that stretch is harmless. Frames repeat every ~90 ms while a key is held,
one `0xBE` frame on release.

Consumer (`editor_getkey 233F`): `code & 0x3F` → **`IR_KEY_TABLE` gives a glyph
index**, which is looked up in `CHARSET_UPPER`/`CHARSET_UPPER2` (shifted) /
`CHARSET_LOWER*` (case) / `CHARSET_GRAPHICS` to get the character or control
byte. Key 29 is SHIFT (toggles `4337`, intercepted before the table). A key is
accepted on its *second* consecutive frame (debounce), auto-repeats after ~1 s
(`GEN_COUNTDOWN 0x514`) at ~0.23 s (`0x12C`); key 36 (STOP/START, code `0xA4`, glyph CR)
never repeats and, in display mode, stops the display and enters the editor
(`rx_consume`). Key 44 = CLEAR (`0x0E`); SHIFT+CLEAR = CLEAR ALL (`0x03`).
Code `0xA5` (key 37) is SPACE. The full 62-key map, an encoder and ESPHome
`remote_transmitter` output are in `cc784_ir.py`; the encoder round-trips
through a simulation of this decoder for all 64 codes at every sampling phase
with 100–350 µs of receiver stretch. Capture used (labels confirmed by the owner): SHIFT, CLEAR, Y, STOP/START —
the "clear all" sequence.

## 9. On-sign editor / menu (`19CA–2A60`) [M]

`menu_enter` → `editor_loop`. `editor_getkey` (`2313`) takes keys from the
serial RX FIFO *or* the IR decoder and **echoes the previous key on serial TX**,
so the menu (ADDRESS?, TIME?, PROG MSG?, SEQ MSG? … in `MENU_STRINGS`) can be
driven from a terminal. `editor_key_to_attr` (`2675`) maps function keys
`10–1F` to message bytes. `keypad_scan` (`196A`) walks an 8×8 matrix via the
latch upper nibble and the input mux; it is reached only through the IR
handler path (`IR_CODE` A4/A5) and no keypad is fitted on this unit
(earlier models had a wired keypad on a 10-pin IDC header).

## 10. Bugs found

### B1 — `B4` queries overflow the stack and corrupt RAM **[H, reproduced on hardware]**
`cmd_B4_query` does `EI` and then `tx_send_frame` spin-waits per byte, while
the call depth (`pkt_process→cmd_B4→query→tx_send_frame→tx_send_byte→tx_try_queue`
≈ 38 bytes) plus each interrupt's cost (return address + scheduled-handler
pushes + `tick6_service`'s 6 saved pairs and its calls ≈ 26 bytes) reaches the
64-byte stack limit; pushes below `4000` vanish into ROM. Observed: garbled
replies that differ every run, stray bytes emitted spontaneously afterwards,
`SEQ_LIST` corrupted, eventual lock-up. Processing in immediate mode
(`PKT_FLAG=80`) makes it worse (runs inside the tick service), but deferred
mode (`flag=00`) still corrupts. NETCC never sent `B4`, so it was never seen.

### B2 — `cmd_17_set_time` stops the clock on a short packet **[H]**
Sets `CLK_RUN=0` before reading its 5 argument bytes; if the packet ends early
(`pkt_next_byte` jumps to `pkt_process_done`) `CLK_RUN` is never restored.
NETCC's "status query" `17 32` triggers exactly this.

### B3 — immediate-mode processing is a latent hazard **[M]**
`PKT_FLAG==80` runs `pkt_process` from within `tick6_service` with the stack
half-consumed, relying on `pkt_process` never returning. Any future handler
that returns or waits (like `B4`) breaks. No effect in normal use.

### B4 — RX bytes lost while a packet is being processed **[H by design]**
`pkt_process` runs with `DI` for the whole insert. The ACK is sent *before*
processing, so a sender must pad after each ACK (or after each broadcast
frame, which gets no ACK). ~0.3 s is safe.

### B5 — default address after RAM loss is 0 **[H]**
NETCC's default is address 1; a sign with dead/absent battery answers only to
0 or `*`. Not a bug per se, but a support trap.

## 11. Suggested patches (all small; keep original bytes under `IF ORIGINAL`)

Build with sjasmplus; add new code after `DEMO_MESSAGE` (`3C21+`) and reach it
with `CALL`/`JP` from patched sites so existing addresses don't move.

1. **Relocate the stack** (fixes B1). Change the three `LD SP,0x403F` (reset
   `0000`, `pkt_process`, `menu_enter`) to `LD SP,0x5EF0` and lower the value
   stored to `STORE_LIMIT` by 256 so the message store cannot grow into the new
   stack. Alternative with no store cost: `LD SP,0x5EF1` is not safe (packet
   buffer), so reduce `STORE_LIMIT`.
2. **Always defer processing** (fixes B3). In `pkt_st_cksum` replace the
   `CP 80 / JP z,pkt_process` with NOPs — `PKT_READY` is already set and
   `main_loop` will pick it up.
3. **Restore the clock** (fixes B2). In `cmd_17_set_time`, set `CLK_RUN` back
   to `FF` on the early-exit path (or move the `CLK_RUN=0` to after all five
   bytes are fetched).
4. **Send ACK after processing** (mitigates B4). Move the `06` transmit from
   `pkt_st_cksum` to `pkt_process_done` (broadcast still silent). This lets a
   sender stream frames at full rate with no padding. Requires care: the ACK
   must not be sent for NAK'd frames (keep the NAK in `pkt_st_cksum`).
5. **Default address 1** (B5). One byte in `init_vars`' RAM-invalid path.
6. Optional: remove the dead `IX/IY` guard and unreachable subs
   (`sub_1B91`, `fx_138B` path), and the mid-code strings.

Test plan after patching: `cc784.py -a 0 --unsafe id` should return
`B1 00 10 "78409O1702930205" 4A`-style frame cleanly ten times in a row;
`dump` should show the store; `time` then `17` alone should not stop the clock.

## 12. Rebuilding

```
git clone --recurse-submodules https://github.com/z00m128/sjasmplus && make
sjasmplus cc784nir.asm          # -> cc784nir.bin, byte-identical to the dump
```
For a W27C512 in the 27C256 socket, program the 32 KB image twice
(`cat cc784nir.bin cc784nir.bin > w27c512.bin`): the board ties pin 1 (A15)
high so the upper half is what runs.

## 13. What is still unknown in the firmware

- Exact behaviour of effects `BB`, `BE` (tiny mode is confirmed by the demo
  text), `BD`, and background codes `94–9F`.
- Exact reply layout for `B4 '3'` (only decodable from the TX code; not yet
  captured on hardware because of B1).
- The IR carrier frequency (module part number not yet read; 38 or 40 kHz).
- Full menu/editor semantics (only structurally read).
