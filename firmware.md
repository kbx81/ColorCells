# CC784 family firmware — reference notes

The firmware of the Color Cells CC784 family of LED message signs: four stock ROMs, one code base revised from 1990 to 1993. §1 traces the line from the original CC784 to the CC784NIR. §2–§13 describe the NIR's firmware in full: it is the newest, the one traced instruction by instruction, and the base of the patched build. §14–§16 describe the NET, the CC710 and the original CC784, each by its differences from the one before it in that chain.

**The reference ROM** is the CC784NIR's: ST M27C256B (32 KB, code in `0x0000–0x3C20`, rest `0xFF`). Hand-written Z80 assembly, ROM ID string `78409O1702930205` (read as: model 784, rev 09, 17-02-93, build 0205).

These notes describe the **stock** firmware as shipped. Companion files: the four sources in `src/stock/` (each reassembles byte-identical with sjasmplus), [protocol.md](protocol.md) (wire protocol), `cc784.py` / `cc784_esphome.py` (tools), [hardware.md](hardware.md) (board). The fixes and additions of the patched build, including the over-the-air update mechanism, are in [patched.md](patched.md) and [ota.md](ota.md); the bugs they fix are listed in §11 here.

**Branches:** `main` carries the untouched reconstruction in `src/stock/` only; `src/patched/` and its tasks live on `wip`.

Confidence key: **[H]** traced instruction by instruction and/or verified on hardware; **[M]** structure understood, details inferred; **[L]** hypothesis.

---

## 1. Lineage of the stock firmware [M — from the four ROMs, their labels and the boards]

The four ROMs are one code base, revised in one sequence. The letter after the `9` in each ROM ID puts them in order, and the code agrees.

| Order | Sign | ROM ID (label) | Date | Board | RAM, channels | Input | Demo text |
|---|---|---|---|---|---|---|---|
| 1 | Original CC784 | `9g` (`CC784-9E-USA ©1990`) | 1990; newest chip from week 26 of 1990 | `CC784-3A`, 4 MHz | 2 KB, 10 | keypad, or serial typed as keys at 300 baud | "NEW COLOR CELLS DYNAMIC DISPLAY SYSTEM", six colors |
| 2 | CC710 | `710` + `09l` (`CC710-9L-USA 1990`) | 1990 | `CC784-3A`, 4 MHz | 2 KB, 10 | keypad, terminal or packet | "NEW COLOR CELLS 700 SERIES", six colors |
| 3 | CC784NET | `78409n1401920145` | built 14-01-92 | `CC784-4`, 4 MHz | 8 KB, 100 | keypad or packet | "CC700 SERIES … NETWORKABLE FROM YOUR PC" |
| 4 | CC784NIR | `78409O1702930205` | built 17-02-93; chips weeks 35–46 of 1992 | `CC784-4`, 8 MHz | 8 KB, 100 | IR remote and packet | "THE ULTIMATE INFRARED REMOTE CONTROL …", ten colors |

**Evidence for the order:**

- The revision letters rise along the chain: `g`, `l`, `n`, `O`.
- The code itself. Each ROM was disassembled and compared with each of the others, instruction by instruction. Two instructions count as the same when they have the same operation and the same 8-bit constants; 16-bit addresses are ignored, since routines move from one build to the next. Each cell in the table below is the number of instructions two ROMs have in common, in the same order (the matching runs found by Python's `difflib`), and in brackets that number as a share of the older ROM's instructions. The figure after each name is that ROM's total instruction count. Each ROM shares the most with its neighbors, and what is left of the original CC784 shrinks at each step. The counts in §14–§16 were made another way, so they differ a little.

| Instructions in common | CC710 (4263) | NET (4991) | NIR (5239) |
|---|---|---|---|
| **Original CC784** (2800) | 2673 (95%) | 2357 (84%) | 2312 (83%) |
| **CC710** (4263) | | 3589 (84%) | 3469 (81%) |
| **NET** (4991) | | | 4780 (96%) |

- Features accumulate in the same order: serial typed as keys (1); the `B1` packet protocol and its queries added beside it (2); 100 channels in 8 KB with terminal mode dropped (3); the IR decoder on an 8 MHz tick, with the keypad scan left in but unreferenced (4).
- The "700 SERIES" name first appears in the CC710's demo, and the NET's demo still uses it.
- `NETCC.EXE` v3.0, the packet host, is ©1991, before the NET was built, so the protocol existed before the `CC784-4`, as the CC710 shows.
- The rating labels agree. Their patent lists grow by one country per sign (US and Australia on the original CC784, Japan added on the CC710, Canada on the NET and NIR), and the keyboard they name changes with the board: the CC100 for the two `CC784-3A` signs, the "CC110 NET" for the two `CC784-4` signs ([hardware notes §14](hardware.md#14-the-four-boards-side-by-side-h--from-photos)).

**Each step:**

1. **Original CC784 → CC710:** the packet parser, queries `0`–`3` and the boot probe that picks keypad, terminal or packet (the original reads one pin, `PORT_IN` bit 0); a 59-column panel on 74HC595s in place of 84 columns. Same board, RAM and channel count ([hardware notes §11](hardware.md#11-the-cc784-3a-board-cc710-h), [§13](hardware.md#13-the-original-cc784s-board-h)).
2. **CC710 → CC784NET:** the `CC784-4` board, with 8 KB RAM, a DB9 in place of the 10-pin header, the power-fail lockout on the regulated 5 V and the delayed `/M1` in copper; 100 channels with two-byte markers; the boot test cut to keypad or packet.
3. **CC784NET → CC784NIR:** the 8 MHz crystal and the `/INT` bodge for the IR decoder's 7812.5 Hz tick, the receiver board and the remote; a new demo.

**Open questions:**

- The original CC784's ROM label and its serial sticker both read `9E`, but the ID inside the ROM is `9g`; the CC710's label and ID agree (`9L`, `09l`).
- The original CC784's board carries the factory `/M1` and beeper bodges ([hardware notes §13](hardware.md#13-the-original-cc784s-board-h)) but the later CC710's does not. The original CC784 here came new and sealed in its box, so its bodges are factory work, not a later service. The CC710's chip date codes settle the rest: both boards come from the same build period, mid-1990, with exact lots in common ([hardware notes §14](hardware.md#14-the-four-boards-side-by-side-h--from-photos)). The fix was applied to some boards, not all; the CC710 shipped without a beeper driver, which may be why it went without [M]. The board dates cannot order the two signs, so the order rests on the ROMs.

**Beyond these four.** `NETCC.EXE` also knows a "CC6x7" name for this family, NC900-series network controllers (model type 2) with their own control bytes, date record and CC900 graphics, and features it marks "(LK)", later models only ([protocol notes](protocol.md)). None of those has been seen in the wild. The company is believed to have been acquired or wound up soon after the NIR began shipping, so the NIR is probably the last firmware of this line.
## 2. Memory map [H]

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
| `43E2–5EF0` | `MSG_STORE` — message store (see §7); `STORE_LIMIT` at `43D8` |
| `5EF0` | `PKT_READY` flag |
| `5EF1–5FF0` | `PKT_BUF` — received payload (≤255 bytes) |
| `5FF1–5FFB` | packet-parser state (`PKT_STATE`, `PKT_CKSUM`, `PKT_FLAG`, `PKT_LEN`, `PKT_VECTOR`, `PKT_ADDR`, `PKT_PTR`, `PKT_REMAIN`) |
| `8000` | memory-mapped write-only **control latch** (`CTRL_LATCH`), shadow copy at `422D` |

Every RAM symbol in the source is written as `FRAMEBUF`, `FRAMEBUF_SIZE` or `RAM_VARS+offset` (the variable block's layout is baked into `INIT_DATA`, so only its base moves). The patched build uses a different geometry ([patched.md §1](patched.md#1-memory-map)).

I/O ports: `IN C0` (input mux), `OUT 40` (column shift clock), `OUT 48–4F` (column data, row in A0–A2), `OUT 80` (strobe). See hardware notes.

Data blocks in ROM:

| Address | Block | What it is |
|---|---|---|
| `0601` | `INIT_DATA` | RAM images copied out by `init_vars` (below) |
| `164A` | `RX_TIMING` | serial RX bit-sampling intervals (§4) |
| `1654` | `TX_TIMING` | serial TX bit intervals (§4) |
| `18E8` | `DEC_TABLE` | decimal conversion |
| `2427` | `IR_KEY_TABLE` | IR code → key number (§9) |
| `2718` | `FG_IDX_TABLE` | `15 n` foreground color bytes (§6) |
| `2722` | `BG_IDX_TABLE` | `16 n` background color bytes (§6) |
| `2D57` | `IGNORE_TABLE` | packet bytes skipped by `pkt_process` (§6) |
| `2D62–2FF2` | `ATTR_LABEL_TABLE` and its strings | the editor's name for each attribute byte (§8) |
| `2FF3` | `MENU_STRINGS` | menu prompts and color names |
| `3135` | `FONT` | 8 bytes per glyph: 7 columns + width; glyphs 0–190 only |
| `372D` | `CHAR_FLAGS` | 256 flag bytes indexed by character code (below) |
| `382D–396E` | `CHARSET_*` | the five key layers (§10) |
| `396F` | `DEMO_MESSAGE` | channel 100 |
| `3C09` | `TEST_MESSAGE` | the factory test pattern, inside the demo text with its own `03` |

`CHAR_FLAGS` bit 0 is tested by `store_fix_bad_bytes`, bit 1 by the message scanners to decide whether a byte is printable text. `TEST_MESSAGE` is "CURRENT TEST" plus seven `17` bytes.

`INIT_DATA` is four RAM images copied out by `init_vars` — to `FB_COLPTR` (10 bytes), `STAGE_PTR` (8), `CLK_RUN` (90) and `4336` (36) — so every byte maps to a known variable; the source is annotated accordingly. Offsets `+12..+17` and `+72` are copied nowhere and are dead. Six entries hold **ROM addresses as data** (`RX_TIMING` ×2, `rx_st_wait_start` ×2, `TX_TIMING` ×2): they must stay symbolic, or moving any code before `164A` silently breaks the serial engine with no build error. Note the two `RX_TIMING` copies land at `4257`/`4259`, *not* on `RX_TIMING_PTR` (`4256`).

## 3. Execution architecture [H]

- **Reset** (`0000`): `LD SP,403F`, init routines, `IM 1`, `EI`, jump to `main_loop`.
- **/INT** (`0038` → `int_timer`): 7812.5 Hz (8 MHz crystal ÷1024 via 74HC4020). Swaps register banks, increments `TICK6_COUNT`/`TICK1_COUNT`, and *pushes the addresses* of `tick6_service` (every 6th tick) and the handler in `TICK_VECTOR` (every tick, = IR decoder) so they execute as the ISR "returns" (`EI; RETI`). The ISR itself is ~30 cycles; the scheduled routines run with interrupts enabled.
- **`tick6_service`** (1302 Hz): serial RX bit engine, serial TX bit engine, countdowns, display row refresh, flashing, then `rx_consume` (pop RX FIFO → packet parser). Has a re-entrancy guard testing `(IX)==AA && (IY)==55` that is effectively dead code (never true in shipped code).
- **/NMI** (`0066` → `clock_tick`): 60 Hz mains zero-cross. Counts `NMI_COUNT` to `NMI_PER_SEC`(=60) → seconds → minutes → 12-hour clock with `CLK_PM`.
- **`main_loop`** (`009A`): if `PKT_READY` → `pkt_process`; else render/effect step; loop. The rendering engine (`render_next_char`, `attr_dispatch`, `fx_*`) runs here. Note the `PKT_READY` test runs **once, on entry** — the inner loop at `00A7` never falls back to `009A`. Re-entry is via `fx_end_of_channel` (`0F5E`, end of a display cycle) or `JP RESET`/`restart_display`. The `JR nz` at `00B0` tests `effect_step`'s flags, not `MAGIC_MODE`: `LD A,(nn)` sets no flags.

Timing: one display row refresh is an `OTIR` of 86 bytes (~1,900 T). Serial bit = 4.33 tick6 = 3.33 ms.

**Row refresh cadence [H]:** a row takes three tick6 periods. The 86 bytes are written twice with identical data, first to port `40+row` and then to `48+row` (`ROW_PORT` selects the group; `ROW_OUT_PENDING` marks the row as still owed), and the third tick advances `ROW_INDEX`. 21 ticks per frame gives a **62 Hz frame rate**. In plain LEFT crawl `SCROLL_SPEED` (0–7, from `F0`–`F7`) adds that many *blanked* ticks after each frame via `BLANK_TIMER`, which is the entire speed mechanism; effects and the editor skip it. Each row is preceded by one color byte (`ROW_COLOR`) on the same port, and bit 5 of the port address is set while `BEEP_TICKS` is non-zero, so the beeper is an I/O decode, not a latch bit. `CTRL_LATCH` bit 7 (`LATCH_BIT7`) is toggled by the firmware every 13 frames (≈210 ms, a 2.4 Hz square wave): **it is the FLASH blink clock** [H — a build with 7 instead of 13 blinked at ~5 Hz on the sign]. The patched source exposes the count as `FLASH_HALF_PERIOD`.

**The CPU runs at 8 MHz [H: by arithmetic, in emulation, and on the scope].** Per tick the ISR costs ~190 T and the IR handler ~100 T; six of those plus one row refresh (OTIR 86 bytes, ~2200 T) come to ~3900 T per `tick6_service` period. At 4 MHz that period is 3072 T, so the service could never finish before the next one was scheduled — the emulator shows exactly that runaway nesting at 4 MHz and a stable ~40-byte stack at 8 MHz.

**Stack use, measured [H in emulation]:** `tools/cc784_sim.py stack` drives the ROM through the demo, a message using every effect, the three `B4` queries and an editor session while watching every write at SP. High-water marks: demo 40 bytes, effects 46, editor menus 52–62, `B4` queries **70** — always the NMI frame landing on top of a query's `tx_send_byte` chain with a tick interrupt in progress. Stock's 64-byte stack loses 6–17 bytes into ROM on every `B4`, which is B1 in numbers. The worst case that can be constructed by hand (query chain 26 + `tick6_service` 28 + a nested `tick6_service` from the ACK spin 28 + IR tick 10 + NMI 12) is ~108, so the patched build's larger stack (`STACK_SIZE`) covers it.

## 4. Serial link [H]

Fully bit-banged. **300 baud is fixed by the tick tables**, not configurable.

- **RX**: `rx_bit_engine` samples `PORT_IN` bit 3 every tick6 (1 = space/start bit, which is RS-232 after one inversion). Waits for start, samples bits per `RX_TIMING` (4,5,4,4,5,…), checks one stop bit (byte dropped on framing error), pushes into `RX_FIFO` (8 bytes, `RX_COUNT`). `rx_fifo_get` pops.
- **TX**: `tx_send_byte` queues one byte (`TX_PENDING`, `TX_STATUS` bit 1) and spin-waits if busy. `tx_bit_engine` shifts it out on `CTRL_LATCH` **bit 4** (1 = space/start, 0 = mark) with `TX_TIMING` (4,4,5,…; stop = 10 ticks ≈ 2.3 bits). The latch is written through `CTRL_LATCH_SHADOW`; the display refresh also read-modify-writes the shadow (`AND 70 / OR row`) and preserves bit 4.

## 5. Packet parser (`pkt_st_*`, `16EF–178C`) [H]

Frame: `B1 addr flag len payload[len] cksum`.

| State | Action |
|---|---|
| idle | byte must be `B1` (and not while a packet is pending) |
| `pkt_st_addr` | → `PKT_ADDR` |
| `pkt_st_flag` | → `PKT_FLAG` (NETCC sends `80`) |
| `pkt_st_len` | → `PKT_LEN`, reset checksum, `PKT_PTR=PKT_BUF`; len 0 skips to cksum |
| `pkt_st_data` | store, `PKT_CKSUM += byte` |
| `pkt_st_cksum` | `E = PKT_CKSUM − byte`. If `PKT_ADDR == 2A` (`*`): no reply. Else if `PKT_ADDR != MY_ADDRESS`: discard silently. Else reply `06` (ACK) if `E==0` else `15` (NAK). If OK and len>0: set `PKT_READY`; **if `PKT_FLAG == 80` jump to `pkt_process` immediately** (from inside `tick6_service`), else return and let `main_loop` do it. |

Checksum = 8-bit sum of payload bytes only. Verified against a NETCC capture and live ACKs.

## 6. Packet processing and command set (`pkt_process 2A68`) [H]

`pkt_process`: wait for TX idle, `DI`, `LD SP,403F`, blank display (`CTRL_LATCH |= 0F`), then walk `PKT_BUF`. Each byte: if in `IGNORE_TABLE` (`00 01 05 08 0A 0B 0C 1C 1D 7F`) skip; else dispatch:

The command bytes are named in the source (`CMD_*`); the docs use those names, with the byte in brackets where the wire matters.

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
| SET_TIME | `17 hhmm a` | `cmd_17_set_time` | 4 ASCII digits → `CLK_H10..CLK_M1`; `a`=`Y`/`y` AM else PM (patched: `H` = 24-hour, [patched.md](patched.md#2-patches) patch 32) |
| COLOR_A0 | `1E n` | `cmd_1E_color_A0` | insert `A0 \| (n&15)` |
| APPEND | `B3` | `cmd_B3_append` | insertion point → end of selected channel |
| QUERY | `B4 c` | `cmd_B4_query` | `c` = ROMID `'0'`, MEMORY `'1'`, NOP `'2'`, DUMP `'3'` — **see bug B1** (patched: `'4'` timing and health counters, `'5'` configuration block, `'6'` sequence list, [patched.md](patched.md#2-patches) patches 30 and 35) |
| CONFIG | `B6 i v` | — | *patched only*: writes byte `i` of the configuration block ([patched.md](patched.md#2-patches), patch 35) |
| (text) | other | `pkt_insert_text` | insert byte into the store at the cursor |

The patched build adds OTA (`B5`), [ota.md](ota.md).

`pkt_process_done` (`2B68`): clear flags, `OUT (40)` pulse, re-init render, jump to `main_loop` (never returns to the caller — this is why immediate-mode processing "works" for normal packets).

Query replies (`tx_send_frame 178D`): `B1 MY_ADDRESS len data cksum(data)` — note: **no flag byte** in replies, and `len` is a single binary byte.

QUERY DUMP cannot use that path — the store exceeds 255 bytes — so it sends `B1 addr <5 ASCII decimal digits = data length> <data…DA> cksum(data)`. Captured on hardware **[H]**, 100 empty channels plus three short messages:

```
06  B1 01 30 30 33 31 35  <315 bytes>  25
│   │  │  └─ "00315", the length as ASCII, not a binary byte
│   │  └─ MY_ADDRESS
│   └─ frame start          (checksum = 8-bit sum of the 315 data bytes)
└─ the ACK for the query frame itself, when addressed rather than broadcast
```

`data` is `MSG_STORE` verbatim through its `DA`, so a cleared store with three messages is 300 framing bytes + text + 1. Remember the two-byte channel markers (§7) when parsing: `D4 D2` is channel 42, not channels 4 and 2.

## 7. Message store format [H]

One contiguous byte stream at `MSG_STORE` (`43E2`) up to `STORE_LIMIT` (`5EEF`), 6925 bytes:

```
D0 D0 <text ch 0> 03   D0 D1 <text ch 1> 03  …  D9 D9 <text ch 99> 03   DA
```

- Channel marker = **two bytes `D0+tens`, `D0+units`** (channel 42 → `D4 D2`). `03` terminates a channel's text, `DA` the store.
- `store_clear_all` writes 100 empty channels + `DA` = 301 bytes of framing, leaving **6625 bytes of text shared by all channels** (`0x19E1`); there is no per-channel limit. `STORE_SIZE` (`0x1B0E` = 6926) is what `B4 '1'` reports; `0x5E8B` = limit − 100 triggers the "100 KEYS LEFT" warning.
- Attribute/color bytes are stored inline exactly as received.
- **Channel 100 (`0x64`) is the ROM demo message**: `chan_select` returns `DEMO_MESSAGE` and `cmd_09` sets `CHAN_LOCK` so inserts are refused. The default sequence plays channel 100, hence the demo after a clear.
- `store_finalize` (`1C38`) is what maintains `STORE_END`: it `CPIR`s from `MSG_STORE` for the `DA` and stores its address. `STORE_END` is therefore the position of the store terminator, not one past the last text byte.
- `pkt_insert_text`: `store_make_room` advances `STORE_CURSOR`, then `LDDR` shifts everything from the cursor **up to `STORE_LIMIT`** (not just to `STORE_END`) by one byte and writes the character. ~6900 byte moves per inserted byte with interrupts off (≈20–40 ms); a 250-byte chunk takes seconds. See bug B8 — fixed by a two-byte operand change.
- **Cursor seating quirk:** CHANNEL alone leaves the cursor on the marker's first byte, so a following insert would split the marker. DELETE_TEXT (re-seats at the marker's last byte and deletes old text) or APPEND (seats before the `03`) must follow CHANNEL before any text. NETCC always sends DELETE_TEXT.
- Typo at `2B1F` confirmed — see bug B6.

## 8. Rendering [H]

### Attribute bytes — the sign's own names [H]

`ATTR_LABEL_TABLE` (`2D62`, indexed `+2*attr`) and `ATTR_LABEL_TABLE_B0` (`2EC2`, indexed `+2*(attr−B0)`) map each attribute byte to the string the on-sign editor displays for it. These are the firmware's own words, not inferred:

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

Related tables in the same block: `COLOR_NAME_TABLE` (`2E62`) gives the 16 foreground names then the four background names repeated four times; `SPEED_STR_TABLE` (`2F42`) gives `S0`–`S7`; `MSG_TOP_TABLE` (`2F02`) gives "TOP OF MSG 1–10" and "TOP DEMO MSG".

**`B8` DRAW vs `1E` GRAPH [H — watched on the sign]:** GRAPH selects a *built-in* graphic (apparently just further glyphs); DRAW takes user-defined artwork as a string of hex values and paints it **column by column**.

**The model name is the geometry:** the panel is **7 rows × 84 columns** — CC**784**. The firmware carries 86 bytes per row, not 84 (`FRAMEBUF` is 4 × 86 = 344, the `0x0158` constant; one row refresh is an `OTIR` of 86), and `shift_chain_clear` clocks 85 zeros to flush the LS164 chain. So there are one or two positions of slack beyond the visible 84.

### Behavior [H — watched on the sign]

`render_next_char` walks the store from `STORE_CURSOR`; `attr_dispatch` dispatches on the bytes above, the single attributes in the table above and these ranges:

| Bytes | Meaning |
|---|---|
| `80–8F` | foreground color: `0x80 \| red<<2 \| green`, two bits of each |
| `90–93` | background: black, red, green, yellow (`94–9F` draw none [H — watched on the sign]) |
| `94–9E`, `C0–CF`, `DC–DF`, `E0–EF` | the 47 European accented characters [H]: the count matches the demo text's "PROGRAMS 47 EUROPEAN CHARACTERS", the glyphs render as Á á Ç ç Ë É é ä ö ü å, and the editor shows "EURO" while that layer is active (`2928`). Not graphics: built-in graphics are `1E` GRAPH, user-drawn ones `B8` DRAW |
| `A0–AF` | the sixteen built-in graphics |
| `F0–F7` | scroll speed, 0 fastest |

The sixteen foreground colors, as `MENU_STRINGS` names them, indexed by the low nibble:

| | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| **green 0–3, red 0** | BLACK | D-GRE | M-GRE | GREEN |
| **red 1** | D-RED | D-YEL | D-LIM | LIME |
| **red 2** | M-RED | D-ORA | M-YEL | LEMON |
| **red 3** | RED | ORANGE | GOLD | YELLOW |

Glyphs: `char_to_glyph` → index → `FONT + 8*idx`. Movement effects are state machines in `fx_*` driven from `main_loop` via `EFFECT_VECTOR`.

### Engine internals [H]

- **Fetch/render pipeline.** `fetch_char` reads one store byte into `CUR_CHAR`; `render_next_char` runs the attribute checks (`attr_*_check`), then `glyph_lookup` → `glyph_bold`/`glyph_italic`/`glyph_big` build the styled glyph in `GLYPH_BUF*` and `glyph_blit` writes a color byte plus the columns into the 344-byte `FRAMEBUF` ring at `FB_COLPTR`. The panel is fed from the output window `FB_OUT_PTR`/`FB_OUT_LEN` (+`FB_EXTRA_LEN` after the wrap); `SCROLLING` is set until the window has caught up with `FB_COLPTR`, one column per frame, and `effect_step` waits for that.
- **Effects stage through `TXBUF`.** With any `EFFECT_ID` other than 0 (LEFT), glyphs are staged into `TXBUF` via `STAGE_PTR` instead of the frame buffer. When the stage fills (`COL_COUNT` reaches 0) or a movement attribute arrives, the handler in `EFFECT_VECTOR` moves the staged frame onto the panel: `fxv_pause` (19) copies it at once and holds `FRAME_DELAY` = 0x50 frames (~1.3 s); `fxv_right` (0F) copies one column per frame left to right; `fxv_hold` (BB) blanks and copies right to left; `fxv_wipe_updown` (1A/1B) makes eight passes through a growing row mask. The text is centered by `STAGE_OFFSET` = free columns / 2. `FLUSH_PENDING` defers an attribute until the stage has been shown. `06` HALT is `fx_halt`: hold `HOLD_FRAMES` frames with every frame-buffer color byte reset to `8F` by `fb_colors_default`, so held text turns yellow and loses its background; WAIT does the same [H — watched on the sign].
- **Holds and wipes.** `BB` HOLD blanks the display and wipes the held text in from right to left; `18` LEFT is the plain scroll, the effect to name after a PAUSE, HOLD, UP, DOWN or RIGHT section to get scrolling text back. `BD` MAGIC OFF ends MAGIC's automatic coloring and fonts; `B9` THIN goes with PAUSE, UP, DOWN, LEFT or RIGHT to keep text that stops on the display in the normal font, since held text is otherwise drawn bold [H — watched on the sign].
- **FLASH is per word.** `14` sets `FLASH_PENDING`; the next printable byte moves it into `FLASH_BIT` (0x10), which is OR-ed into the color bytes until the next space. Two spaces in a row clear the background color bits.
- **MAGIC mode** (`MAGIC_MODE`, 1F…BD) is `magic_preprocess`: each word gets a random font (words of six or more letters stay NORM), the color changes every 2–5 words or at `. ! ? : ,`, walking `MAGIC_COLOR_CYCLE` while skipping the too-similar pairs in `MAGIC_CLASH_PAIRS`; spaces are 9 columns wide (`WIDE_SPACE_GLYPH`); a word starting with `$` flashes; text is pushed off (`scroll_off_text`) before each movement attribute.
- **RAINBOW** (`BC`) cycles red, orange, yellow, lime, green per character (`RAINBOW_COLORS`, `RAINBOW_IDX`) until a color attribute.
- **DRAW** (`B8`): hex digit pairs are packed by `RRD` into `DRAW_BUF`, up to 16 columns, ended by the first non-hex byte (a `03` there is pushed back). Consecutive DRAW items butt together with no gap column (`DRAW_NO_GAP`).
- **Glyphs `00`–`0F` are 14-column pairs:** `glyph_lookup` doubles their width so the second glyph slot is read as the right half.
- **The clock** (`5F`) is `render_clock`: it re-enters `glyph_lookup` once per character for `H:MM AM/PM` (leading zero suppressed) using `CLK_RENDER_STEP`/`CLK_RENDER_PTR`, and afterwards forces a LEFT crawl (`CLK_RENDERED`).
- **`BE` TINY** renders into `FRAMEBUF_TINY` with `TINY_FRAME_READY` handshaking the copy to the panel, and ends at the first attribute byte.
- **`1D` SHIFT** is only a key: as a message byte it is ignored by `attr_dispatch` and dropped from packets by `IGNORE_TABLE`.

## 9. IR remote decoder (`ir_*`, `1482–1571`) [H — verified against a capture of the sign's own receiver]

Runs every tick (128 µs) on `PORT_IN` bit 1 (1 = burst present; the receiver module is active-low and the HC14 inverts it). The remote is a Motorola MC14497 PCM transmitter ([hardware notes §9](hardware.md#9-open-questions)). State machine:

1. idle: line quiet for 130 ticks;
2. leader burst seen, then its end;
3. **21 ticks (2688 µs) after the leader ends** a burst must be present (the "start" cell), and **3 ticks later** the line must be quiet;
4. **6 data cells of 8 ticks (1024 µs)**, biphase: sample at tick 4, and at tick 8 the level must be the complement or the frame is discarded;
5. `IR_CODE = bits | 0x80` → `0x80–0xBF`. Index `0x3E` (`0xBE`) = **key released**.

Measured at the receiver output: leader burst ≈ 810 µs, start burst begins ≈ 3060 µs after the leader starts, half-bit 512 µs; bursts come out ~250 µs longer than transmitted (receiver stretch) and the firmware's sample points sit where that stretch is harmless. Frames repeat every ~90 ms while a key is held, one `0xBE` frame on release.

Consumer (`editor_getkey 233F`): `code & 0x3F` → **`IR_KEY_TABLE` gives a glyph index**, which is looked up in `CHARSET_UPPER`/`CHARSET_UPPER2` (shifted) / `CHARSET_LOWER*` (case) / `CHARSET_EURO` (the EUROPE layer) to get the character or control byte. Key 29 is SHIFT (toggles `4337`, intercepted before the table). A key is accepted on its *second* consecutive frame (debounce), auto-repeats after ~1 s (`GEN_COUNTDOWN 0x514`) at ~0.23 s (`0x12C`); key 36 (STOP/START, code `0xA4`, glyph CR) never repeats and, in display mode, stops the display and enters the editor (`rx_consume`). Key 44 = CLEAR (`0x0E`); SHIFT+CLEAR = CLEAR ALL (`0x03`). Code `0xA5` (key 37) is SPACE. The full 62-key map, an encoder and ESPHome `remote_transmitter` output are in `cc784_ir.py`; the encoder round-trips through a simulation of this decoder for all 64 codes at every sampling phase with 100–350 µs of receiver stretch. Capture used (labels read off the remote): SHIFT, CLEAR, Y, STOP/START — the "clear all" sequence.

## 10. On-sign editor / menu (`19CA–2A60`) [M]

`key_handler` → `editor_loop` (serial `01` or the STOP/START key; the `menu_enter` address-login gate in the ROM is unreachable). `editor_getkey` (`2313`) takes keys from the serial RX FIFO *or* the IR decoder and **echoes the previous key on serial TX**, so the menu (ADDRESS?, TIME?, PROG MSG?, SEQ MSG? … in `MENU_STRINGS`) can be driven from a terminal. `editor_key_to_attr` (`2675`) maps function keys `10–1F` to message bytes. `keypad_scan` (`196A`) walks an 8×8 matrix via the latch upper nibble and the input port, but nothing calls it: the CC784NET firmware (§14) uses it for the keypad on the DB9.

### Editor keys [H — from `editor_dispatch`; remote labels read off the remote]

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

| Key | FUNC + key |
|---|---|
| GRAPH | `B8` DRAW |
| NORM | `B9` THIN |
| PAUSE | `BA` WAIT |
| FLASH | `B0` REM |
| BOLD | `06` HALT |
| COLOR | `BC` RAINBOW |
| BIG | `BE` TINY |
| MAGIC | the ADDRESS? menu |
| Q | `?` |
| X | `!` | The editor shows FUNC/COLOR/BGRND/GRAPH/SPEED/EURO while a prefix is pending (`*_PENDING`). MAGIC as the *first* key after entering the editor (or on the demo channel) is `magic_new_message`: it takes the first empty channel (asking "FULL!! MSG# ?" if none), makes it the whole sequence and announces "MAGIC MSG nn". Leaving the editor adds the edited channel to `SEQ_LIST` if it is not there and shows it first (`NEXT_CHAN`), unless the sequence was set by hand (`SEQ_SET`).

> [!NOTE]
> **Did you know?...**
> 
> There is an undocumented test mode: `SEQ` (`SEQ MSG?`), `MAGIC` then `C` copies `TEST_MESSAGE` to `TEST_MSG_BUF`, appends the 16-bit sum of ROM `0000–3FFF` as four hex digits and displays that instead of the sequence (`TEST_MODE`) until the next key — a factory ROM-checksum check. The patched build removes it ([patched.md](patched.md#2-patches), patch 29) and reuses `TEST_MODE` for the OTA parked display.

### Key layers [H]

`IR_KEY_TABLE` turns an IR code into a key number 0–63 (the 8×8 matrix position). That number then indexes one of five 64-byte tables to get the character or attribute byte, chosen at `23C1`:

| `EURO_STATE` | `SHIFT_STATE` | `CAPS_LOCK` | table |
|---|---|---|---|
| set | — | — | `CHARSET_EURO` |
| clear | clear | `00` | `CHARSET_LOWER` |
| clear | clear | `FF` | `CHARSET_UPPER` |
| clear | set | `00` | `CHARSET_UPPER2` |
| clear | set | `FF` | `CHARSET_LOWER2` |

So SHIFT selects the alternate *function* layer **and** flips case, while `CAPS_LOCK` (`4358`, toggled at `216C`, defaults to `FF`) flips case alone. `SHIFT_STATE` (`4337`) and `EURO_STATE` (`4364`, toggled at `2184`) are both one-shot — cleared after every key.

Both toggles live on **one physical key**, confirmed against the remote: it is labeled **UPPER/LOWER**, with **EUROPE** as its shifted function. Unshifted (key 41, IR code `95`, byte `1C`) it toggles `CAPS_LOCK`; shifted (byte `B6`) it toggles `EURO_STATE`. The EUROPE layer is not a graphics mode: it selects the 47 accented characters of §8, and the firmware displays "EURO" for it.

The tables are laid out 8 keys per row in the source with each entry glossed, so the full map is readable there. It cross-checks the attribute names from §8 independently: key 2 is BOLD unshifted and LEFT shifted, key 18 is MAGIC/MAGIC OFF, key 55 is COLOR/BGRND. Key 25 is SHIFT in every layer.

## 11. Bugs

All in the stock firmware; the patched build fixes most of them.

### B1 — QUERY replies overflow the stack and corrupt RAM **[H]**
`cmd_B4_query` does `EI` and then `tx_send_frame` spin-waits per byte, while the call depth (`pkt_process→cmd_B4→query→tx_send_frame→tx_send_byte→tx_try_queue` ≈ 38 bytes) plus each interrupt's cost (return address + scheduled-handler pushes + `tick6_service`'s 6 saved pairs and its calls ≈ 26 bytes) reaches the 64-byte stack limit; pushes below `4000` vanish into ROM and the matching pops read ROM bytes back, so return addresses become whatever sits there and control flow leaves the firmware: one serial frame hijacks the CPU. Observed: garbled replies that differ every run, stray bytes emitted spontaneously afterwards, `SEQ_LIST` corrupted, eventual lock-up. Processing in immediate mode (`PKT_FLAG=80`) makes it worse (runs inside the tick service), but deferred mode (`flag=00`) still corrupts. NETCC never sent a QUERY, so it was never seen. *Fixed by patch 1.*

### B2 — `cmd_17_set_time` stops the clock on a short packet **[H]**
Sets `CLK_RUN=0` before reading its 5 argument bytes; if the packet ends early (`pkt_next_byte` jumps to `pkt_process_done`) `CLK_RUN` is never restored. NETCC's "status query" `17 32` triggers exactly this. *Fixed by patch 2.*

### B3 — immediate-mode processing is a latent hazard **[M]**
`PKT_FLAG==80` runs `pkt_process` from within `tick6_service` with the stack half-consumed, relying on `pkt_process` never returning. Any future handler that returns or waits (like QUERY) breaks. No effect in normal use. *Not present in the patched build (patch 21).*

### B4 — RX bytes lost while a packet is being processed **[H by design]**
`pkt_process` runs with `DI` for the whole insert, and interrupts stay off through `restart_display` (`store_repair`, then `init_sequence`, which calls `chan_select` for every channel in the sequence and each call scans the store from the start). The ACK is sent *before* all that, so a sender must pad after each ACK (or after each broadcast frame, which gets no ACK). Measured in emulation on the stock structure: **0.24 s** deaf after a short message into an empty store, rising to **~0.75 s** with the store nearly full. A frame started inside the window loses its header and is never seen — no NAK. On the sign the first attempt of every chunked message vanishes while its retry 12 s later succeeds. *By design; the host pauses after each reply, or waits for the DONE byte of patch 16.*

### B5 — default address after RAM loss is 0 **[H]**
NETCC's default is address 1; a sign with dead/absent battery answers only to 0 or `*`. The on-sign menu explicitly *refuses* to set 0 (`1FED`), so address 0 is only ever reachable through this path. Not a bug per se, but a support trap. *Fixed by patch 4.*

### B6 — `pkt_insert_text` corrupts `STORE_CURSOR` at `2B1F` **[H]**
`LD (STORE_CURSOR),A` (opcode `32`) where `LD (STORE_CURSOR),HL` (`22`) was meant. Reached when the cursor sits on a channel's `03` terminator: `A` is `3` there (the `CP 3` just matched), so instead of backing the cursor off the terminator it stamps `03` into the cursor's **low byte** and the next insert lands at a random offset inside the store. Not reachable from the standard CHANNEL / DELETE_TEXT / APPEND sequences, which never leave the cursor on an `03`. *Fixed by patch 3.*

### B7 — `MY_ADDRESS_INV` is not a complement on the reset path **[H]**
`init_vars` (`05C4`) writes `00` to *both* `MY_ADDRESS` and `MY_ADDRESS_INV`, but the validity test is `CPL(MY_ADDRESS_INV) == MY_ADDRESS` — and `CPL(00)` is `FF`, not `00`. The pair therefore never validates, so this path re-runs on every boot. Harmless in the stock ROM (it rewrites the same 0), but it means the "RAM is intact" check is permanently failing after a battery loss. The menu path (`1FF2`) does it correctly: `LD (MY_ADDRESS),A / CPL / LD (…INV),A`. *Fixed by patch 4.*

### B8 — every inserted byte shifts the whole store, not just the live text **[H]**
`pkt_insert_text` sets `MOVE_DST` from `STORE_LIMIT` (`2B3D`) although `STORE_END` was just updated at `2B37` and everything above it is dead space. The `LDDR` therefore moves ~6.9 KB per inserted character with interrupts off, so a 250-byte message takes seconds. Shifting to `STORE_END` instead moves only `STORE_END − STORE_CURSOR + 1` bytes — 174 for channel 42 in an empty store, about 39× fewer; for channel 0 it is ~6900× fewer. Verified by simulating both loops: the resulting store is byte-identical. *Fixed by patch 5.*

### B9 — a pending deferred packet turns the next frame into an editor session **[H]**
While a packet accepted with `PKT_FLAG != 80` waits for `main_loop` to get round to it, `rx_idle_byte` ignores the next `B1` but not the bytes after it: the address byte goes through `rx_not_start`, and `CP 1 → key_handler` opens the on-sign editor if it is `01`. With address 1 as the default, every frame to a sign that still has a deferred packet pending drops it into the editor, which then echoes every following byte on TX. Harmless with NETCC (always `80`) and with `cc784.py`. *A trap for hand-built frames; not changed.*

### B10 — `tx_send_byte` drops a `00` byte offered to a busy transmitter **[H]**
`tx_try_queue` returned A = 0 for "queued" and A unchanged for "busy", and `tx_send_byte` retried on A ≠ 0 — so a `00` byte that found the transmitter busy looked queued and was lost. Invisible in stock, where no reply ever carries a `00`; binary replies do. *Fixed by patch 12.*

### B11 — APPEND into an empty channel loses the first and last byte **[H]**
`09 01 B3 "XYZW"` leaves `YZ`; `09 02 0E "XYZW"` stores all four. `cmd_B3_append` seats the cursor on the byte before the channel's `03`, then, if that byte is a marker byte (the channel is empty), steps back once more onto the marker's first byte; the first insert then splits the marker and `store_repair` discards the strays. Appending to a channel that already has text is unaffected. *Fixed by patch 15.*

### B12 — a `20` byte inside a packet releases WAIT **[H]**
`rx_fifo_get` leaves every received byte in `RX_BYTE`, and `wait_poll` (the `BA` WAIT spin) releases on `RX_BYTE == 20`, meaning the SPACE key. So any packet carrying a `20` — a space in a message, or `JR nz` in OTA page data — ends the wait. *Fixed by patch 14.*

### B13 — text without a CHANNEL command is dropped while the demo plays **[H]**
After a bare CLEAR_ALL, or on an empty sign, the renderer is in the ROM demo and the demo channel carries `CHAN_LOCK`, which turns every insert into a no-op: the text is ACKed and vanishes (a dump afterwards shows an empty store). NETCC always sends CHANNEL first, so it never met this. *Fixed by patch 24.*

## 12. Rebuilding

```
git clone --recurse-submodules https://github.com/z00m128/sjasmplus && make
cd src/stock && sjasmplus cc784nir.asm   # -> cc784nir.bin; likewise cc784net.asm, cc710.asm and cc784.asm
```
Or the `Build stock ROM` task, which assembles all four stock sources. Each must stay byte-identical to its dump — `cc784nir.bin` md5 `c021af146a50b93a22d13535201b7eaa`, `cc784net.bin` `872c87932339e9e072c5525d30ffb5df`, `cc710.bin` `f346d39e5aa7b49709a717c85d7c7e11`, `cc784.bin` `3e7a679f77d7dac121926182442f923a` — that is the regression test for every edit to the stock sources, and the `Verify stock ROM is byte-identical` task asserts it. The NET and CC710 sources carry the NIR's labels and comments wherever the code is the same, and the original CC784's carry the CC710's, so a name means the same routine in all four. The patched build and its packaging: [patched.md §5](patched.md#5-rebuilding-and-testing).

**Emulation.** `tools/cc784_sim.py` runs either build under an emulated Z80 (kosarev's `z80` package; `uv run tools/cc784_sim.py …` fetches it) with a fake 300-baud line, IR receiver and mains NMI. `stack [stock|patched]` prints the stack high-water mark and the transmitted bytes through a scripted session; `compare DIR_A DIR_B` assembles two source trees and checks that the panel sees the same sequence of frames and the PC the same replies. It reproduces the hardware captures byte for byte (`B4 '0'` → `06 B1 01 10 "78409O1702930205" 58`) and B1's overflow on stock, so it is the regression test for anything that moves RAM or touches the interrupt paths. MAGIC mode seeds its randomness from the mains counter, so frame comparisons use a message without it. The emulator also models the AT28C256 with the OTA bodges and the board's watchdog ([ota.md §6](ota.md#6-testing)).

For a W27C512 in the 27C256 socket, program the 32 KB image twice (`cat cc784nir.bin cc784nir.bin > w27c512.bin`): the board ties pin 1 (A15) high so the upper half is what runs. The AT28C256 that makes the ROM writable in circuit is wired per [upgrades.md](upgrades.md).

## 13. What is still unknown in the firmware

- Full menu/editor semantics (only structurally read), though the label tables give every function key its name.

## 14. The CC784NET firmware [H — from a ROM dump, `78409n1401920145`]

Same code base, built 14-01-92, 13 months before the NIR's. Read from a CC784NET (keypad/PC model, no IR hardware, same `CC784-4` board).

| | NET | NIR |
|---|---|---|
| ROM ID (`0048`) | `78409n1401920145` | `78409O1702930205` |
| Code end | `398E` | `3C20` |
| IR decoder | none | `ir_*` |
| `keypad_scan` | called from `tick6` and the editor | unreferenced |
| Input mode | chosen at boot (below) | always serial |
| Timer ISR | runs the serial bit engines and the row scan every interrupt, at 1302 Hz (4 MHz crystal, [hardware notes §3](hardware.md#3-timebase-h)) | 7812.5 Hz tick, ÷6 for the same work |
| Packet commands and `B4` queries `0`–`3` | same | same |
| Demo message | "CC700 SERIES MULTI COLOR DISPLAY ... NETWORKABLE FROM YOUR PC" | "ULTIMATE INFRARED REMOTE CONTROL ..." |

**Boot-time mode test** (`13CB`, called from the store/serial init at `1376`): sync to a tick with `HALT`, interrupts off, then 16 clocks of a `55 55` pattern out on `CTRL_LATCH` bits 6 (data, DB9 pin 7) and 5 (clock, DB9 pin 4), sampling `PORT_IN` bit 0 (DB9 pin 2) after each clock. If the last 8 samples are all 0 the flag at `4223` is set: serial mode, the RX/TX bit engines run from the timer ISR and `rx_consume` feeds the packet parser. Otherwise keypad mode: `tick6` calls `keypad_scan` instead, code `35` (STOP/START) enters the editor, and the serial engines never run. The factory cable's pin 2–5 short is what makes the test pass; a plain crossover leaves a NET sign deaf.

**Editor keys** are the raw key codes (`00`–`3F`, see [hardware notes §6](hardware.md#6-connectors)): `19` toggles SHIFT, and the charsets are indexed by the code directly, with no `IR_KEY_TABLE`.

The timer ISR starts with a check that `(IX)=AA` and `(IY)=55`, the sentinel the mode test sets so that its `HALT` returns without running the tick machinery. The NIR's firmware has no cable test and no such check: its `int_timer` goes straight to the tick counters.

The annotated source is [src/stock/cc784net.asm](src/stock/cc784net.asm) (`mode_test`, `store_init`, `int_timer`); 4554 of its 4921 instructions are the NIR's, label for label.

## 15. The CC710 firmware [H — from a ROM dump, ID `710`]

The original CC784's code base ([§16](#16-the-original-cc784-firmware-h--from-a-rom-dump-id-9g)) with the packet protocol added, the step before the NET's ([§1](#1-lineage-of-the-stock-firmware-m--from-the-four-roms-their-labels-and-the-boards)), for the ten-channel sign on the `CC784-3A` board ([hardware notes §11](hardware.md#11-the-cc784-3a-board-cc710-h)): 16 KB with code to `307A`, 4 MHz, the 1302 Hz ISR doing everything per interrupt, keypad input through the 10-pin header. Source: [src/stock/cc710.asm](src/stock/cc710.asm); 2959 of 5419 instructions are the NIR's, and the NIR names apply.

| | CC710 | CC784 (NET/NIR) |
|---|---|---|
| ROM ID | `710` at `0050` and `09l` at `0060`; query `0` returns the six bytes `71009l` | 16 characters at `0048` |
| RAM | 2 KB, `4000–47FF`: stack from `403F` down, frame buffer `4040` (a 120-byte ring, 60 columns per row), variables from `40B8`, store from `423C` | 8 KB |
| Channels | 10, one-byte markers `D0`–`D9`, `DA` ends the store, demo = channel 10 | 100, two-byte markers |
| Sequence list | 32 entries, default `0..9` | 104 entries |
| Panel | 60 bytes per row for 59 columns (one falls off the chain) | 86 for 84 |
| Attributes | PAUSE `06` (the CC784's HALT), BEEP, CRAWL `18` (LEFT), JUMP `19` (PAUSE), UP, DOWN, BCRAWL `0F` (RIGHT), BIG/NORM/BOLD/ITALIC/FLASH, FORE `15`/BACK `16`, SHIFT, GRAPH, MAGIC, REM, DRAW, THIN, WAIT; colors include AMBER `8E` | plus HOLD `BB`, RAINBOW `BC`, MAGIC OFF `BD`, TINY `BE`, the EURO layer |
| Input | keypad, serial terminal or packet, chosen at boot (below) | NET: keypad or packet; NIR: packet |

**Boot input mode** (`store_init`, `mode_test`) [H]. The NET's cable test in a three-way form: `mode_test` syncs to a tick with the `HALT` sentinel, then clocks the pattern `55` out on `CTRL_LATCH` bit 6 (SK1 pin 5, DB9 pin 7) with bit 5 (SK1 pin 4) as the clock, sampling `PORT_IN` bit 0 (SK1 pin 9, DB9 pin 2) sixteen times into `DE`. `INPUT_MODE` (`4127`) is set from `E`, the last eight samples: `00` → `FF`, serial **terminal** mode (the bit engines run, bytes are key codes: `01` opens the editor with TX echo, `7E` opens `menu_enter`, which blanks the panel and opens the editor if the next byte is `*` or the address, else resets [H], `20` releases WAIT [H]); `55` → `FE`, **packet** mode (the `B1` parser, editor unreachable); anything else → `00`, **keypad** mode. The NET cable's DB9 pin 2–5 short (SK1 pins 9 and 2) therefore gives terminal mode on a CC710, not packets [H: `01` opened the editor, typed bytes appeared at the cursor and each one came back on TX]. Packet mode then derives `MY_ADDRESS` [H]: `D` (the first eight samples) ≠ `55` → address `~D`; `D` = `55` → probe again with `AA`; `55` again → address `AA`; otherwise keep the stored address if `MY_ADDRESS_INV` is its complement, else fall back to `2A`. Both of those paths are wrong [H]: the store routine expects the probe byte and keeps its complement, so the keep path flips the address between X and ~X on every boot that takes it, and the `2A` fallback gives `MY_ADDRESS` `D5`, not `*` (the sign still accepts `*` frames but replies as `D5`). The keypad reaches the keep path (below), and the flip is verified [H]; the fallback is not tried. A plain wire from pin 7 to pin 2 reads `2A/AA` (keypad mode); an inverting echo reads `D5/55` (packet mode, address `*`). The probe's shape (a low pulse on SK1 pin 3, then 15 clocks for 16 samples, the first taken before any clock) fits an address plug of two chained 74HC165s: eight switches holding `~address`, the second byte wired to `55`. No such plug is known, but with no ADDRESS function on the keypad it is the only way to give the sign an address other than `*`. Packet mode caps the store at `46EF` (1204 bytes; query `1` reports `01204` [H]) and keeps `46F0–47FF` for `PKT_READY`, `PKT_BUF` and the parser; the other modes use `423C–47FF` (1476 bytes).

**Boot clear** (`boot_clear_check`) [H, verified on a CC100]: keypad mode only, `PORT_IN` bit 1 low at power-up calls `store_clear_all`. `mode_test` leaves keypad row 3 selected and only column bit 1 is read, so holding any row-3 key in column 0, 1, 4 or 5 while powering on wipes the store: `0`, SHIFT, `8` or `6`. By the same reasoning, a row-7 key in an even column (`08`, `1`, `7`, `U`) held at power-up reads `E` = `55` and puts the sign into packet mode, with address `*` (`D` reads `D5`) [H: `1`, `7` and `U` verified on a CC100]. That is a way into packet mode without an adapter. Holding a row-1 key in an even column as well (SPACE, `)`, `Z` or `Y`) makes the pre-clock sample low, so the `55` probe reads `55/55` and the `AA` probe `2A`: the keep path. After a `1` boot (stored pair `2A`/`D5`) the next `Z` + `1` boot gives address `D5`, the one after `*`, and so on [H: `Z` + `1`, ACK and NAK at `D5`, then `*` on the following boot].

**Store corruption** on mains power cycles, in any mode, is not a firmware bug: and the emulated firmware leaves an intact store unchanged boot after boot ([hardware notes §11](hardware.md#11-the-cc784-3a-board-cc710-h)).

**Serial handshake** [H], absent from the NIR: `tx_bit_engine` starts a byte only while `PORT_IN` bits 1 and 2 (SK1 pins 8 and 7) are both high; `rx_bit_engine` drives `CTRL_LATCH` bit 5 (SK1 pin 4) high as "ready", drops it while `RX_FIFO` holds 8 bytes, and samples only while bit 1 is high. Same 300-baud bit timing.

**Parser and commands.** The NIR's `pkt_st_*` states with the state cells at `47F1–47FB`; a `B1` inside the payload aborts the frame. With `PKT_FLAG` `80` the immediate path rewrites the interrupted return address so the ISR returns into `pkt_process` [M]. Query `2` is not a NOP here: `query_2_remarks` returns, for channels 0–9, the first `B0` remark of each (up to 20 bytes) followed by `19`, a message-title query [H]. `09 c` takes one byte (`0`–`9`, `D`/`d` demo) [H], `04` one byte per channel, `17 hhmm a` takes `A`/`a` for AM, `03` clears the ten channels [H]. `TEST_MESSAGE` is displayed straight from ROM with no checksum [M].

**FUNC** (`B7`, `editor_key_to_attr`) is SHIFT + the key at code `25` (SEQ unshifted); SHIFT + STOP/START stays `0D`, unlike the CC784. Its only second functions: GRAPH → `B8` DRAW, NORM → `B9` THIN, BOLD → `BA` WAIT, FLASH → `B0` REM. No HALT, RAINBOW, TINY, ADDRESS or `?`/`!`.

**Equate caveats.** The RAM layout differs enough that a few NIR names would have landed on other variables; the source drops or aliases them (`GEN_COUNTDOWN` → `MENU_MSG_PTR`, `SPARE_TIMER` → `KEY_TIMER`, which is live here and in the NET, `QUERIES_ENABLED` → `INPUT_MODE`).

## 16. The original CC784 firmware [H — from a ROM dump, ID `9g`]

The ancestor of the CC710 code base, read from the original keypad CC784 (a `CC784-3A` board, ROM labelled `CC784-9E-USA`, [hardware notes §13](hardware.md#13-the-original-cc784s-board-h)): 16 KB image with code to `234C`, everything after it `FF`. Source: [src/stock/cc784.asm](src/stock/cc784.asm). 2673 of its 2800 instructions line up with the CC710's in order (2310 with the NIR's). The CC710 names apply, and where they differ the source uses this ROM's meaning.

| | Original CC784 | CC710 |
|---|---|---|
| ROM ID | `9g` at `0060`; nothing reads it | `710` at `0050`, `09l` at `0060`, returned by query `0` |
| RAM | 2 KB: stack from `403F` down, frame buffer `4040` (172-byte ring, 86 columns per row), variables from `40EC`, store `4262–47FF` (1438 bytes) | the same map with a 120-byte ring, variables from `40B8`, store from `423C` |
| Channels | 10, one-byte markers `D0`–`D9`, `DA` ends the store, demo = channel 10 | same |
| Input | keypad or serial, from `PORT_IN` bit 0 at boot | keypad, serial terminal or packet, from the `mode_test` probe |
| Packet protocol | none: no `B1` parser, no queries, no ACK | the NIR's, with query `2` returning remarks |
| Attributes | PAUSE `06`, BEEP `07`, END `03`, CRAWL `18`, JUMP `19`, UP, DOWN, BCRAWL `0F`, BIG/NORM/BOLD/ITALIC/FLASH, FORE `15`/BACK `16`, SPEED `F0`–`F7`, GRAPH, MAGIC, clock `5F` | plus REM `B0`, DRAW `B8`, THIN `B9`, WAIT `BA` |
| Color names in the editor | only BLACK, GREEN, LIME, RED, ORANGE, YELLOW; the other ten show `<?>` | all sixteen, AMBER for `8E` |
| Demo | "THIS IS A DEMONSTRATION OF THE NEW COLOR CELLS DYNAMIC DISPLAY SYSTEM. SIX EXCITING COLORS ..." | "... NEW COLOR CELLS 700 SERIES ..." |

**Boot input mode** (`store_init`). One pin decides: `PORT_IN` bit 0 low at boot sets `INPUT_MODE` `FF` (serial), high sets `00` (keypad). There is no probe pattern, sentinel `HALT` or address derivation, and the timer ISR has no `(IX)=AA`/`(IY)=55` check. `boot_clear_check` is the CC710's: keypad mode with `PORT_IN` bit 1 low at power-up clears the store and the sequence. Which keys do that depends on the keypad row selected at reset, which this ROM does not set first; not tried.

**Serial mode** is the CC710's terminal mode with the same bit engines (300 baud at a 1302 Hz tick, so a 4 MHz crystal as in the CC710 [M]), the same handshake (`PORT_IN` bits 1 and 2 gate the transmitter; `CTRL_LATCH` bit 5 is "ready", dropped while the 8-byte FIFO is full) and the same key translation outside the editor: `01` opens the editor with echo, `7E` opens `menu_enter`. Two differences: a received `00` jumps to `RESET` at once, and `menu_enter` has no `*`: it opens the editor only if the next byte equals `MY_ADDRESS`, a RAM byte that nothing initialises and only the editor key `5E` sets (`menu_address`: the next key becomes the address, with no prompt). In the editor, bytes are keys, raw ASCII, echoed on TX.

**Editor** [M]. The CC710's editor without CLR ALL (`03`), FUNC (`B7`), the `B3` end key or the magic-message dialogue. Keys: `05` top of message, `7F` delete, `1D` shift, `0A`/`08` and `0C`/`0B` cursor, `0E` clear the message (or the list inside SEQ?), `1C` caps, `1E` GRAPH, `15` FORE, `16` BACK, `02` SPEED, `17` TIME?, `09` PROG MSG?, `04` SEQ MSG?, `0D` exit, `5E` address. The prompts are the NIR's long wordings (`TOP OF MSG  n`, `PROG MSG?`, `MEMORY FULL`, `100 KEYS LEFT`, `SEQUENCE FULL`), drawn on the 84-column panel. `redraw_show_label` indexes `ATTR_LABEL_TABLE` with the whole byte, so the tables after it are laid out to serve as entries `80`–`9F` (color names), `D0`–`DF` (`MSG_TOP_TABLE`, so a marker shows its channel's title) and `F0`–`F7` (speed names).

**MAGIC** [M] is simpler than the CC710's: no random fonts, word counting or punctuation rule. At a word boundary (a space or font attribute after a space, followed by text) it steps `MAGIC_COLOR_IDX` through the 64-entry `MAGIC_COLOR_CYCLE` (foreground in bits 0–3, background in bits 5–6) and draws a space in the new color. A color byte or the end of the channel ends MAGIC.

**Equate caveats.** The variables keep the CC710 order up to `ROW_OUT_PENDING` (offset `+0x34` for the bigger ring, `+0x1A` more after `TXBUF`); the few after it are packed differently and were named from their use (`MY_ADDRESS`, `SPEED_PENDING`, `SCROLL_SPEED`, `BLANK_TIMER`, `KEY_ECHO_TX`). `IR_KEY_CHAR` keeps the NIR name but holds the keypad or serial key being read.

