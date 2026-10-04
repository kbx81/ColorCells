# CC784NIR firmware — reference notes

Color Cells CC784NIR LED message display. Firmware in ST M27C256B (32 KB, code
in `0x0000–0x3C20`, rest `0xFF`). Hand-written Z80 assembly, ROM ID string
`78409O1702930205` (read as: model 784, rev 09, 17-02-93, build 0205).

These notes describe the **stock** firmware as shipped. Companion files:
`src/stock/cc784nir.asm` (reassembles byte-identical with sjasmplus),
`CC784_protocol.md` (wire protocol), `cc784.py` / `cc784_esphome.py` (tools),
`CC784_hardware.md` (board). The fixes and additions of the patched build,
including the over-the-air update mechanism, are in `CC784_patched.md` and
`CC784_ota.md`; the bugs they fix are listed in §10 here.

**Branches:** `main` carries the untouched reconstruction in `src/stock/` only;
`src/patched/` and its tasks live on `wip`.

Confidence key: **[H]** traced instruction by instruction and/or verified on
hardware; **[M]** structure understood, details inferred; **[L]** hypothesis.

---

## 1. Memory map [H]

| Range | Use |
|---|---|
| `0000–3C20` | ROM code + data |
| `3C21–7FFF` | unused (`0xFF`) — free for patches |
| `4000–403F` | **stack** (64 bytes, grows down from `403F`; below `4000` is ROM) — see B1 |
| `4040–4197` | `FRAMEBUF` — 4 × 86 bytes |
| `4198–41A1` | frame-buffer pointers/temps |
| `41A2–41F7` | `TXBUF` — reply frame buffer (len byte + up to 0x55 data) |
| `41F8–43E1` | variables (the `equ` block in the source names each from its use; the handful the firmware writes but never reads are marked "never read") |
| `43CB/43CC` | `MY_ADDRESS` / its complement (RAM-validity check at boot) |
| `43E2–5EF0` | `MSG_STORE` — message store (see §6); `STORE_LIMIT` at `43D8` |
| `5EF0` | `PKT_READY` flag |
| `5EF1–5FF0` | `PKT_BUF` — received payload (≤255 bytes) |
| `5FF1–5FFB` | packet-parser state (`PKT_STATE`, `PKT_CKSUM`, `PKT_FLAG`, `PKT_LEN`, `PKT_VECTOR`, `PKT_ADDR`, `PKT_PTR`, `PKT_REMAIN`) |
| `8000` | memory-mapped write-only **control latch** (`CTRL_LATCH`), shadow copy at `422D` |

Every RAM symbol in the source is written as `FRAMEBUF`, `FRAMEBUF_SIZE` or
`RAM_VARS+offset` (the variable block's layout is baked into `INIT_DATA`, so
only its base moves). The patched build uses a different geometry
(`CC784_patched.md` §1).

I/O ports: `IN C0` (input mux), `OUT 40` (column shift clock), `OUT 48–4F`
(column data, row in A0–A2), `OUT 80` (strobe). See hardware notes.

Data blocks in ROM:

| Address | Block | What it is |
|---|---|---|
| `0601` | `INIT_DATA` | RAM images copied out by `init_vars` (below) |
| `164A` | `RX_TIMING` | serial RX bit-sampling intervals (§3) |
| `1654` | `TX_TIMING` | serial TX bit intervals (§3) |
| `18E8` | `DEC_TABLE` | decimal conversion |
| `2427` | `IR_KEY_TABLE` | IR code → key number (§8) |
| `2718` | `FG_IDX_TABLE` | `15 n` foreground colour bytes (§5) |
| `2722` | `BG_IDX_TABLE` | `16 n` background colour bytes (§5) |
| `2D57` | `IGNORE_TABLE` | packet bytes skipped by `pkt_process` (§5) |
| `2D62–2FF2` | `ATTR_LABEL_TABLE` and its strings | the editor's name for each attribute byte (§7) |
| `2FF3` | `MENU_STRINGS` | menu prompts and colour names |
| `3135` | `FONT` | 8 bytes per glyph: 7 columns + width; glyphs 0–190 only |
| `372D` | `CHAR_FLAGS` | 256 flag bytes indexed by character code (below) |
| `382D–396E` | `CHARSET_*` | the five key layers (§9) |
| `396F` | `DEMO_MESSAGE` | channel 100 |
| `3C09` | `TEST_MESSAGE` | the factory test pattern, inside the demo text with its own `03` |

`CHAR_FLAGS` bit 0 is tested by `store_fix_bad_bytes`, bit 1 by the message
scanners to decide whether a byte is printable text. `TEST_MESSAGE` is
"CURRENT TEST" plus seven `17` bytes.

`INIT_DATA` is four RAM images copied out by `init_vars` — to `FB_COLPTR`
(10 bytes), `STAGE_PTR` (8), `CLK_RUN` (90) and `4336` (36) — so every byte
maps to a known variable; the source is annotated accordingly. Offsets
`+12..+17` and `+72` are copied nowhere and are dead. Six entries hold **ROM
addresses as data** (`RX_TIMING` ×2, `rx_st_wait_start` ×2, `TX_TIMING` ×2):
they must stay symbolic, or moving any code before `164A` silently breaks the
serial engine with no build error. Note the two `RX_TIMING` copies land at
`4257`/`4259`, *not* on `RX_TIMING_PTR` (`4256`).

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
  runs here. Note the `PKT_READY` test runs **once, on entry** — the inner loop
  at `00A7` never falls back to `009A`. Re-entry is via `fx_end_of_channel`
  (`0F5E`, end of a display cycle) or `JP RESET`/`restart_display`. The `JR nz` at `00B0`
  tests `effect_step`'s flags, not `MAGIC_MODE`: `LD A,(nn)` sets no flags.

Timing: one display row refresh is an `OTIR` of 86 bytes (~1,900 T). Serial
bit = 4.33 tick6 = 3.33 ms.

**Row refresh cadence [H]:** a row takes three tick6 periods. The 86 bytes are
written twice with identical data, first to port `40+row` and then to
`48+row` (`ROW_PORT` selects the group; `ROW_OUT_PENDING` marks the row as
still owed), and the third tick advances `ROW_INDEX`. 21 ticks per frame gives
a **62 Hz frame rate**. In plain LEFT crawl `SCROLL_SPEED` (0–7, from
`F0`–`F7`) adds that many *blanked* ticks after each frame via `BLANK_TIMER`,
which is the entire speed mechanism; effects and the editor skip it. Each row
is preceded by one colour byte (`ROW_COLOUR`) on the same port, and bit 5 of
the port address is set while `BEEP_TICKS` is non-zero, so the beeper is an
I/O decode, not a latch bit. `CTRL_LATCH` bit 7 (`LATCH_BIT7`) is toggled by
the firmware every 13 frames (≈210 ms, a 2.4 Hz square wave): **it is the
FLASH blink clock** [H — a build with 7 instead of 13 blinked at ~5 Hz on the
sign]. The patched source exposes the count as `FLASH_HALF_PERIOD`.

**The CPU runs at 8 MHz [H by arithmetic, seen in emulation].** Per tick the
ISR costs ~190 T and the IR handler ~100 T; six of those plus one row refresh
(OTIR 86 bytes, ~2200 T) come to ~3900 T per `tick6_service` period. At 4 MHz
that period is 3072 T, so the service could never finish before the next one
was scheduled — the emulator shows exactly that runaway nesting at 4 MHz and
a stable ~40-byte stack at 8 MHz. Hardware question H1 is settled from the
firmware side.

**Stack use, measured [H in emulation]:** `tools/cc784_sim.py stack` drives
the ROM through the demo, a message using every effect, the three `B4`
queries and an editor session while watching every write at SP. High-water
marks: demo 40 bytes, effects 46, editor menus 52–62, `B4` queries **70** —
always the NMI frame landing on top of a query's `tx_send_byte` chain with a
tick interrupt in progress. Stock's 64-byte stack loses 6–17 bytes into ROM on
every `B4`, which is B1 in numbers. The worst case that can be constructed by
hand (query chain 26 + `tick6_service` 28 + a nested `tick6_service` from the
ACK spin 28 + IR tick 10 + NMI 12) is ~108, so a 128-byte stack is the right
size and 256 was twice too generous.

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

The command bytes are named in the source (`CMD_*`); the docs use those
names, with the byte in brackets where the wire matters.

| Command | Bytes | Handler | Effect |
|---|---|---|---|
| SPEED | `02 n` | `cmd_02_speed` | insert `F0 \| (n&7)` |
| CLEAR_ALL | `03` | `cmd_03_clear_all` | reset the whole store |
| SEQUENCE | `04 dd…[D/d]` | `cmd_04_sequence` | rebuild `SEQ_LIST` from 2-ASCII-digit channels (00–99) |
| CHANNEL | `09 dd` | `cmd_09_channel` | select channel dd; insertion point at its start; dd=100 sets `CHAN_LOCK` |
| END | `0D` | — | end of packet |
| DELETE_TEXT | `0E` | `cmd_0E_delete_text` | delete the selected channel's existing text |
| FORE_IDX | `15 n` | `cmd_15_fore_idx` | insert `FG_IDX_TABLE[n]` (`8C 8D 8F 87 83 84 8E 80 8B 81`) |
| BACK_IDX | `16 n` | `cmd_16_back_idx` | insert `BG_IDX_TABLE[n]` (`91 93 93 93 92 90`) |
| SET_TIME | `17 hhmm a` | `cmd_17_set_time` | 4 ASCII digits → `CLK_H10..CLK_M1`; `a`=`Y`/`y` AM else PM |
| COLOUR_A0 | `1E n` | `cmd_1E_colour_A0` | insert `A0 \| (n&15)` |
| APPEND | `B3` | `cmd_B3_append` | insertion point → end of selected channel |
| QUERY | `B4 c` | `cmd_B4_query` | `c` = ROMID `'0'`, MEMORY `'1'`, NOP `'2'`, DUMP `'3'` — **see bug B1** |
| (text) | other | `pkt_insert_text` | insert byte into the store at the cursor |

The patched build adds OTA (`B5`), `CC784_ota.md`.

`pkt_process_done` (`2B68`): clear flags, `OUT (40)` pulse, re-init render, jump
to `main_loop` (never returns to the caller — this is why immediate-mode
processing "works" for normal packets).

Query replies (`tx_send_frame 178D`): `B1 MY_ADDRESS len data cksum(data)` —
note: **no flag byte** in replies, and `len` is a single binary byte.

QUERY DUMP cannot use that path — the store exceeds 255 bytes — so it sends
`B1 addr <5 ASCII decimal digits = data length> <data…DA> cksum(data)`.
Captured on hardware **[H]**, 100 empty channels plus three short messages:

```
06  B1 01 30 30 33 31 35  <315 bytes>  25
│   │  │  └─ "00315", the length as ASCII, not a binary byte
│   │  └─ MY_ADDRESS
│   └─ frame start          (checksum = 8-bit sum of the 315 data bytes)
└─ the ACK for the query frame itself, when addressed rather than broadcast
```

`data` is `MSG_STORE` verbatim through its `DA`, so a cleared store with three
messages is 300 framing bytes + text + 1. Remember the two-byte channel markers
(§6) when parsing: `D4 D2` is channel 42, not channels 4 and 2.

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
- `store_finalize` (`1C38`) is what maintains `STORE_END`: it `CPIR`s from
  `MSG_STORE` for the `DA` and stores its address. `STORE_END` is therefore the
  position of the store terminator, not one past the last text byte.
- `pkt_insert_text`: `store_make_room` advances `STORE_CURSOR`, then `LDDR`
  shifts everything from the cursor **up to `STORE_LIMIT`** (not just to
  `STORE_END`) by one byte and writes the character. ~6 900 byte moves per
  inserted byte with interrupts off (≈20–40 ms); a 250-byte chunk takes
  seconds. See bug B8 — fixed by a two-byte operand change.
- **Cursor seating quirk:** CHANNEL alone leaves the cursor on the marker's
  first byte, so a following insert would split the marker. DELETE_TEXT
  (re-seats at the marker's last byte and deletes old text) or APPEND (seats
  before the `03`) must follow CHANNEL before any text. NETCC always sends
  DELETE_TEXT.
- Typo at `2B1F` confirmed — see bug B6.

## 7. Rendering [M for behaviour, **H for the names**]

### Attribute bytes — the sign's own names [H]

`ATTR_LABEL_TABLE` (`2D62`, indexed `+2*attr`) and `ATTR_LABEL_TABLE_B0`
(`2EC2`, indexed `+2*(attr−B0)`) map each attribute byte to the string the
on-sign editor displays for it. These are the firmware's own words, not
inferred:

| Byte | Name | Byte | Name | Byte | Name |
|---|---|---|---|---|---|
| `01` | SPEED | `13` | ITALIC | `1F` | MAGIC |
| `03` | END | `14` | FLASH | `B0` | REM |
| `04` | SEQ MSG? | `15` | COLOR | `B8` | DRAW |
| `06` | **HALT** | `16` | BGRND | `B9` | **THIN** |
| `07` | BEEP | `18` | **LEFT** | `BA` | WAIT |
| `09` | PROG MSG? | `19` | **PAUSE** | `BB` | **HOLD** |
| `0F` | **RIGHT** | `1A` | UP | `BC` | RAINBOW |
| `10` | BIG | `1B` | DOWN | `BD` | **MAGIC OFF** |
| `11` | NORM | `1D` | **SHIFT** | `BE` | TINY |
| `12` | BOLD | `1E` | **GRAPH** | | |

Related tables in the same block: `COLOUR_NAME_TABLE` (`2E62`) gives the 16
foreground names then the four background names repeated four times;
`SPEED_STR_TABLE` (`2F42`) gives `S0`–`S7`; `MSG_TOP_TABLE` (`2F02`) gives
"TOP OF MSG 1–10" and "TOP DEMO MSG".

**`B8` DRAW vs `1E` GRAPH [H — from the sign's owner]:** GRAPH selects a
*built-in* graphic (apparently just further glyphs); DRAW takes user-defined
artwork as a string of hex values and paints it **column by column**.

**The model name is the geometry:** the panel is **7 rows × 84 columns** —
CC**784**. The firmware carries 86 bytes per row, not 84 (`FRAMEBUF` is
4 × 86 = 344, the `0x0158` constant; one row refresh is an `OTIR` of 86), and
`shift_chain_clear` clocks 85 zeros to flush the LS164 chain. So there are one or two
positions of slack beyond the visible 84.

### Behaviour [M]

`render_next_char` walks the store from `STORE_CURSOR`; `attr_dispatch`
dispatches on the bytes above. `attr_colour_speed` handles `80–8F` foreground
(`0x80 | red<<2 | green`; names in `MENU_STRINGS`: BLACK D-GRE M-GRE GREEN
D-RED D-YEL D-LIM LIME M-RED D-ORA M-YEL LEMON RED ORANGE GOLD YELLOW), `90–9F`
background, `A0–AF` second colour range, `F0–F7` speed. `B0` remark (skip to
next `B0`), `B8` graphic, `BA` wait-for-key, `BC` rainbow, `5F` time.
Glyphs: `char_to_glyph` → index → `FONT + 8*idx`. Codes `94–9E`, `C0–CF`,
`DC–DF` and `E0–EF` are the **47 European accented characters** [H] — the
count matches the demo text's "PROGRAMS 47 EUROPEAN CHARACTERS" exactly, the
glyphs render as Á á Ç ç Ë É é ä ö ü å, and the editor displays "EURO" while
that layer is active (`2928`). They are *not* graphics: built-in graphics are
the `1E` GRAPH attribute and user-drawn ones the `B8` DRAW attribute.
Movement effects are state machines in `fx_*` driven from `main_loop` via
`EFFECT_VECTOR`.

### Engine internals [H — traced; not yet all seen on hardware]

- **Fetch/render pipeline.** `fetch_char` reads one store byte into
  `CUR_CHAR`; `render_next_char` runs the attribute checks (`attr_*_check`),
  then `glyph_lookup` → `glyph_bold`/`glyph_italic`/`glyph_big` build the
  styled glyph in `GLYPH_BUF*` and `glyph_blit` writes a colour byte plus the
  columns into the 344-byte `FRAMEBUF` ring at `FB_COLPTR`. The panel is fed
  from the output window `FB_OUT_PTR`/`FB_OUT_LEN` (+`FB_EXTRA_LEN` after the
  wrap); `SCROLLING` is set until the window has caught up with `FB_COLPTR`,
  one column per frame, and `effect_step` waits for that.
- **Effects stage through `TXBUF`.** With any `EFFECT_ID` other than 0 (LEFT),
  glyphs are staged into `TXBUF` via `STAGE_PTR` instead of the frame buffer.
  When the stage fills (`COL_COUNT` reaches 0) or a movement attribute
  arrives, the handler in `EFFECT_VECTOR` moves the staged frame onto the
  panel: `fxv_pause` (19) copies it at once and holds `FRAME_DELAY` = 0x50
  frames (~1.3 s); `fxv_right` (0F) copies one column per frame left to right;
  `fxv_hold` (BB) blanks and copies right to left; `fxv_wipe_updown` (1A/1B)
  makes eight passes through a growing row mask. The text is centred by
  `STAGE_OFFSET` = free columns / 2. `FLUSH_PENDING` defers an attribute until
  the stage has been shown. `06` HALT is `fx_halt`: hold 0x50 frames with every
  frame-buffer colour byte reset to `8F` by `fb_colours_default`.
- **FLASH is per word.** `14` sets `FLASH_PENDING`; the next printable byte
  moves it into `FLASH_BIT` (0x10), which is OR-ed into the colour bytes until
  the next space. Two spaces in a row clear the background colour bits.
- **MAGIC mode** (`MAGIC_MODE`, 1F…BD) is `magic_preprocess`: each word gets a
  random font (words of six or more letters stay NORM), the colour changes
  every 2–5 words or at `. ! ? : ,`, walking `MAGIC_COLOUR_CYCLE` while
  skipping the too-similar pairs in `MAGIC_CLASH_PAIRS`; spaces are 9 columns
  wide (`WIDE_SPACE_GLYPH`); a word starting with `$` flashes; text is pushed
  off (`scroll_off_text`) before each movement attribute.
- **RAINBOW** (`BC`) cycles red, orange, yellow, lime, green per character
  (`RAINBOW_COLOURS`, `RAINBOW_IDX`) until a colour attribute.
- **DRAW** (`B8`): hex digit pairs are packed by `RRD` into `DRAW_BUF`, up to
  16 columns, ended by the first non-hex byte (a `03` there is pushed back).
  Consecutive DRAW items butt together with no gap column (`DRAW_NO_GAP`).
- **Glyphs `00`–`0F` are 14-column pairs:** `glyph_lookup` doubles their width
  so the second glyph slot is read as the right half.
- **The clock** (`5F`) is `render_clock`: it re-enters `glyph_lookup` once per
  character for `H:MM AM/PM` (leading zero suppressed) using
  `CLK_RENDER_STEP`/`CLK_RENDER_PTR`, and afterwards forces a LEFT crawl
  (`CLK_RENDERED`).
- **`BE` TINY** renders into `FRAMEBUF_TINY` with `TINY_FRAME_READY`
  handshaking the copy to the panel, and ends at the first attribute byte.
- **`1D` SHIFT** is only a key: as a message byte it is ignored by
  `attr_dispatch` and dropped from packets by `IGNORE_TABLE`.

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
`CHARSET_LOWER*` (case) / `CHARSET_EURO` (the EUROPE layer) to get the character or control
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

`key_handler` → `editor_loop` (serial `01` or the STOP/START key; the
`menu_enter` address-login gate in the ROM is unreachable). `editor_getkey` (`2313`) takes keys from the
serial RX FIFO *or* the IR decoder and **echoes the previous key on serial TX**,
so the menu (ADDRESS?, TIME?, PROG MSG?, SEQ MSG? … in `MENU_STRINGS`) can be
driven from a terminal. `editor_key_to_attr` (`2675`) maps function keys
`10–1F` to message bytes. `keypad_scan` (`196A`) walks an 8×8 matrix via the
latch upper nibble and the input port, but nothing calls it: the CC784NET
firmware (§13) uses it for the keypad on the DB9.

### Editor keys [H — from `editor_dispatch`; remote labels from the owner]

| Byte | Remote key | Action |
|---|---|---|
| `08` / `0A` | ← / → | cursor left / right one byte |
| `0B` / `0C` | SHIFT ← / SHIFT → | cursor left / right eight |
| `7F` | DEL | delete the byte under the cursor |
| `0E` / `03` | CLEAR / SHIFT CLEAR | clear the message / CLR ALL Y/N |
| `0D` (and `B1`) | STOP/START | leave the editor, resume display |
| `B7` | SHIFT STOP/START = **FUNC** | next key picks a second function (below) |
| `1C` / `B6` | UPPER/LOWER / SHIFT = **EUROPE** | `CAPS_LOCK` / `EURO_STATE` |
| `1D` / `9F` | SHIFT (shows SHIFT) | `9F` is the shift-off code, ignored |
| `15` / `16` | COLOR / SHIFT = **BGRND** | then a digit |
| `09` / `02` | PROG / SHIFT = **SPEED** | PROG MSG? / speed digit |
| `04` / `BB` | SEQ / SHIFT = **HOLD** | SEQ MSG? / insert HOLD |
| `1E` / `5F` | GRAPH / SHIFT = **TIME** | digit → `A0–AF` / insert the clock |
| `11` / `17` | NORMAL / SHIFT = **ADJ TIME** | NORM / TIME? HHMM, AM? Y/N |
| `05` / `B3` | *(no key)* | to top / end of message — serial only |
| `5E` | *(FUNC + MAGIC)* | ADDRESS? |
| other | | insert into the message |

`B7` FUNC gives each function key a second meaning (`editor_key_to_attr`):
GRAPH → `B8` DRAW, NORM → `B9` THIN, PAUSE → `BA` WAIT, FLASH → `B0` REM,
BOLD → `06` HALT, COLOR → `BC` RAINBOW, BIG → `BE` TINY, MAGIC → ADDRESS?
menu, Q → `?`, X → `!`. The editor shows FUNC/COLOR/BGRND/GRAPH/SPEED/EURO
while a prefix is pending (`*_PENDING`). MAGIC as the *first* key after
entering the editor (or on the demo channel) is `magic_new_message`: it takes
the first empty channel (asking "FULL!! MSG# ?" if none), makes it the whole
sequence and announces "MAGIC MSG nn". Leaving the editor adds the edited
channel to `SEQ_LIST` if it is not there and shows it first (`NEXT_CHAN`),
unless the sequence was set by hand (`SEQ_SET`).

**Test mode:** in SEQ MSG?, MAGIC then `C` copies `TEST_MESSAGE` to
`TEST_MSG_BUF`, appends the 16-bit sum of ROM `0000–3FFF` as four hex digits
and displays that instead of the sequence (`TEST_MODE`) until the next key —
a factory ROM-checksum check.

### Key layers [H]

`IR_KEY_TABLE` turns an IR code into a key number 0–63 (the 8×8 matrix
position). That number then indexes one of five 64-byte tables to get the
character or attribute byte, chosen at `23C1`:

| `EURO_STATE` | `SHIFT_STATE` | `CAPS_LOCK` | table |
|---|---|---|---|
| set | — | — | `CHARSET_EURO` |
| clear | clear | `00` | `CHARSET_LOWER` |
| clear | clear | `FF` | `CHARSET_UPPER` |
| clear | set | `00` | `CHARSET_UPPER2` |
| clear | set | `FF` | `CHARSET_LOWER2` |

So SHIFT selects the alternate *function* layer **and** flips case, while
`CAPS_LOCK` (`4358`, toggled at `216C`, defaults to `FF`) flips case alone.
`SHIFT_STATE` (`4337`) and `EURO_STATE` (`4364`, toggled at `2184`) are both
one-shot — cleared after every key.

Both toggles live on **one physical key**, confirmed against the remote: it is
labelled **UPPER/LOWER**, with **EUROPE** as its shifted function. Unshifted
(key 41, IR code `95`, byte `1C`) it toggles `CAPS_LOCK`; shifted (byte `B6`)
it toggles `EURO_STATE`. The EUROPE layer is not a graphics mode: it selects
the 47 accented characters of §7, and the firmware displays "EURO" for it.

The tables are laid out 8 keys per row in the source with each entry glossed,
so the full map is readable there. It cross-checks the attribute names from
§7 independently: key 2 is BOLD unshifted and LEFT shifted, key 18 is
MAGIC/MAGIC OFF, key 55 is COLOR/BGRND. Key 25 is SHIFT in every layer.

## 10. Bugs

All in the stock firmware; the patched build fixes most of them.

### B1 — QUERY replies overflow the stack and corrupt RAM **[H]**
`cmd_B4_query` does `EI` and then `tx_send_frame` spin-waits per byte, while
the call depth (`pkt_process→cmd_B4→query→tx_send_frame→tx_send_byte→tx_try_queue`
≈ 38 bytes) plus each interrupt's cost (return address + scheduled-handler
pushes + `tick6_service`'s 6 saved pairs and its calls ≈ 26 bytes) reaches the
64-byte stack limit; pushes below `4000` vanish into ROM. Observed: garbled
replies that differ every run, stray bytes emitted spontaneously afterwards,
`SEQ_LIST` corrupted, eventual lock-up. Processing in immediate mode
(`PKT_FLAG=80`) makes it worse (runs inside the tick service), but deferred
mode (`flag=00`) still corrupts. NETCC never sent a QUERY, so it was never seen.
*Fixed by patch 1.*

### B2 — `cmd_17_set_time` stops the clock on a short packet **[H]**
Sets `CLK_RUN=0` before reading its 5 argument bytes; if the packet ends early
(`pkt_next_byte` jumps to `pkt_process_done`) `CLK_RUN` is never restored.
NETCC's "status query" `17 32` triggers exactly this.
*Fixed by patch 2.*

### B3 — immediate-mode processing is a latent hazard **[M]**
`PKT_FLAG==80` runs `pkt_process` from within `tick6_service` with the stack
half-consumed, relying on `pkt_process` never returning. Any future handler
that returns or waits (like QUERY) breaks. No effect in normal use.
*Documented only; patch 1 removes its known trigger.*

### B4 — RX bytes lost while a packet is being processed **[H by design]**
`pkt_process` runs with `DI` for the whole insert, and interrupts stay off
through `restart_display` (`store_repair`, then `init_sequence`, which calls
`chan_select` for every channel in the sequence and each call scans the store
from the start). The ACK is sent *before* all that, so a sender must pad after
each ACK (or after each broadcast frame, which gets no ACK). Measured in
emulation on the patched build: **0.24 s** deaf after a short message into an
empty store, rising to **~0.75 s** with the store nearly full. A frame started
inside the window loses its header and is never seen — no NAK. On the sign
this showed as every first attempt of a chunked message vanishing while its
retry 12 s later succeeded.
*By design; the host pauses after each reply, or waits for the DONE byte of patch 16.*

### B5 — default address after RAM loss is 0 **[H]**
NETCC's default is address 1; a sign with dead/absent battery answers only to
0 or `*`. The on-sign menu explicitly *refuses* to set 0 (`1FED`), so address 0
is only ever reachable through this path. Not a bug per se, but a support trap.
*Fixed by patch 4.*

### B6 — `pkt_insert_text` corrupts `STORE_CURSOR` at `2B1F` **[H]**
`LD (STORE_CURSOR),A` (opcode `32`) where `LD (STORE_CURSOR),HL` (`22`) was
meant. Reached when the cursor sits on a channel's `03` terminator: `A` is `3`
there (the `CP 3` just matched), so instead of backing the cursor off the
terminator it stamps `03` into the cursor's **low byte** and the next insert
lands at a random offset inside the store. Not reachable from the standard
CHANNEL / DELETE_TEXT / APPEND sequences, which never leave the cursor on an `03`.
*Fixed by patch 3.*

### B7 — `MY_ADDRESS_INV` is not a complement on the reset path **[H]**
`init_vars` (`05C4`) writes `00` to *both* `MY_ADDRESS` and `MY_ADDRESS_INV`,
but the validity test is `CPL(MY_ADDRESS_INV) == MY_ADDRESS` — and `CPL(00)`
is `FF`, not `00`. The pair therefore never validates, so this path re-runs on
every boot. Harmless in the stock ROM (it rewrites the same 0), but it means
the "RAM is intact" check is permanently failing after a battery loss. The
menu path (`1FF2`) does it correctly: `LD (MY_ADDRESS),A / CPL / LD (…INV),A`.
*Fixed by patch 4.*

### B8 — every inserted byte shifts the whole store, not just the live text **[H]**
`pkt_insert_text` sets `MOVE_DST` from `STORE_LIMIT` (`2B3D`) although
`STORE_END` was just updated at `2B37` and everything above it is dead space.
The `LDDR` therefore moves ~6.9 KB per inserted character with interrupts off,
so a 250-byte message takes seconds. Shifting to `STORE_END` instead moves
only `STORE_END − STORE_CURSOR + 1` bytes — 174 for channel 42 in an empty
store, i.e. ~39× fewer; for channel 0 it is ~6900× fewer. Verified by
simulating both loops: the resulting store is byte-identical.
*Fixed by patch 5.*

### B9 — a pending deferred packet turns the next frame into an editor session **[H]**
While a packet accepted with `PKT_FLAG != 80` waits for `main_loop` to get
round to it, `rx_idle_byte` ignores the next `B1` but not the bytes after it:
the address byte goes through `rx_not_start`, and `CP 1 → key_handler` opens
the on-sign editor if it is `01`. With address 1 as the default,
every frame to a sign that still has a deferred packet pending drops it into
the editor, which then echoes every following byte on TX. Harmless with
NETCC (always `80`) and with `cc784.py`.
*A trap for hand-built frames; not changed.*

### B10 — `tx_send_byte` drops a `00` byte offered to a busy transmitter **[H]**
`tx_try_queue` returned A = 0 for "queued" and A unchanged for "busy", and
`tx_send_byte` retried on A ≠ 0 — so a `00` byte that found the transmitter
busy looked queued and was lost. Invisible in stock, where no reply ever
carries a `00`; binary replies do.
*Fixed by patch 12.*

### B11 — APPEND into an empty channel loses the first and last byte **[H]**
`09 01 B3 "XYZW"` leaves `YZ`; `09 02 0E "XYZW"` stores all four.
`cmd_B3_append` seats the cursor on the byte before the channel's `03`, then,
if that byte is a marker byte (the channel is empty), steps back once more
onto the marker's first byte; the first insert then splits the marker and
`store_repair` discards the strays. Appending to a channel that already has
text is unaffected.
*Fixed by patch 15.*

### B12 — a `20` byte inside a packet releases WAIT **[H]**
`rx_fifo_get` leaves every received byte in `RX_BYTE`, and `wait_poll` (the
`BA` WAIT spin) releases on `RX_BYTE == 20`, meaning the SPACE key. So any
packet carrying a `20` — a space in a message, or `JR nz` in OTA page data —
ends the wait.
*Fixed by patch 14.*

## 11. Rebuilding

```
git clone --recurse-submodules https://github.com/z00m128/sjasmplus && make
cd src/stock && sjasmplus cc784nir.asm   # -> cc784nir.bin
```
Or the `Build stock ROM` task. `src/stock/cc784nir.bin` must stay at md5
`c021af146a50b93a22d13535201b7eaa` — that is the regression test for every
edit to the stock source, and the `Verify stock ROM is byte-identical` task
asserts it. The patched build and its packaging: `CC784_patched.md` §6.

**Emulation.** `tools/cc784_sim.py` runs either build under an emulated Z80
(kosarev's `z80` package; `uv run tools/cc784_sim.py …` fetches it) with a
fake 300-baud line, IR receiver and mains NMI. `stack [stock|patched]` prints
the stack high-water mark and the transmitted bytes through a scripted
session; `compare DIR_A DIR_B` assembles two source trees and checks that the
panel sees the same sequence of frames and the PC the same replies. It
reproduces the hardware captures byte for byte (`B4 '0'` → `06 B1 01 10
"78409O1702930205" 58`) and B1's overflow on stock, so it is the regression
test for anything that moves RAM or touches the interrupt paths. MAGIC mode
seeds its randomness from the mains counter, so frame comparisons use a
message without it. The emulator also models the AT28C256 with the OTA
bodges and the board's watchdog (`CC784_ota.md` §6).

For a W27C512 in the 27C256 socket, program the 32 KB image twice
(`cat cc784nir.bin cc784nir.bin > w27c512.bin`): the board ties pin 1 (A15)
high so the upper half is what runs. The AT28C256 that makes the ROM
writable in circuit is wired per `AT28C256.md`.

## 12. What is still unknown in the firmware

- `BB` HOLD blanks the display and wipes the held text in from right to
  left [H — owner]; `18` LEFT is the plain scroll, the effect to name after a
  PAUSE, HOLD, UP, DOWN or RIGHT section to get scrolling text back. `BD`
  MAGIC OFF ends MAGIC's automatic colouring and fonts; `B9`
  THIN goes with PAUSE, UP, DOWN, LEFT or RIGHT to keep text that stops on
  the display in the normal font, since held text is otherwise drawn bold
  [H — owner].
- `8F` is **YELLOW** [H — owner], the default text colour. `fx_halt` and WAIT
  reset every frame-buffer colour byte to it and effects force the row lead
  colour to it, so HALT and WAIT turn the held text yellow [H — owner].
- Text sent without a CHANNEL command while the sign is playing the ROM demo
  (after a bare CLEAR_ALL, or on an empty sign) is ACKed and lost: the
  insertion point is derived from the renderer's cursor, which is in ROM,
  and the EEPROM's write protection swallows the bytes [H — watched: a
  dump afterwards shows an empty store]. NETCC always sends CHANNEL first.
- Background codes `94–9F` draw no background at all; only `90–93` (black,
  red, green, yellow) do, and a hold (WAIT, HALT) drops the background along
  with the text colour [H — owner].
- The IR carrier frequency (module part number not yet read; 38 or 40 kHz).
- Full menu/editor semantics (only structurally read), though the label tables
  now give every function key its name.

## 13. The CC784NET firmware [H — from a ROM dump, `78409n1401920145`]

Same code base, built 14-01-92, 13 months before the NIR's. Read from a
CC784NET (keypad/PC model, no IR hardware, same `CC784-4` board).

| | NET | NIR |
|---|---|---|
| ROM ID (`0048`) | `78409n1401920145` | `78409O1702930205` |
| Code end | `398E` | `3C20` |
| IR decoder | none | `ir_*` |
| `keypad_scan` | called from `tick6` and the editor | unreferenced |
| Input mode | chosen at boot (below) | always serial |
| Timer ISR | runs the serial bit engines and the row scan every interrupt, at 1302 Hz (4 MHz crystal, hardware notes §3) | 7812.5 Hz tick, ÷6 for the same work |
| Packet commands and `B4` queries `0`–`3` | same | same |
| Demo message | "CC700 SERIES MULTI COLOR DISPLAY ... NETWORKABLE FROM YOUR PC" | "ULTIMATE INFRARED REMOTE CONTROL ..." |

**Boot-time mode test** (`13CB`, called from the store/serial init at
`1376`): sync to a tick
with `HALT`, interrupts off, then 16 clocks of a `55 55` pattern out on
`CTRL_LATCH` bits 6 (data, DB9 pin 7) and 5 (clock, DB9 pin 4), sampling
`PORT_IN` bit 0 (DB9 pin 2) after each clock. If the last 8 samples are all 0
the flag at `4223` is set: serial mode, the RX/TX bit engines run from the
timer ISR and `rx_consume` feeds the packet parser. Otherwise keypad mode:
`tick6` calls `keypad_scan` instead, code `35` (STOP/START) enters the editor,
and the serial engines never run. The factory cable's pin 2–5 short is what
makes the test pass; a plain crossover leaves a NET sign deaf.

**Editor keys** are the raw key codes (`00`–`3F`, see hardware notes §6):
`19` toggles SHIFT, and the charsets are indexed by the code directly, with
no `IR_KEY_TABLE`.

The timer ISR starts with a check that `(IX)=AA` and `(IY)=55`, the sentinel
the mode test sets so that its `HALT` returns without running the tick
machinery. The NIR dropped the check.
