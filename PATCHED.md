# CC784NIR patched firmware

`src/patched/cc784nir.asm`, on the `wip` branch, is the stock reconstruction ([src/stock/cc784nir_9o.asm](src/stock/cc784nir_9o.asm)) plus the patches below. The patch list records what differs from stock and why. At the tag `patched-v39`, `diff src/stock/cc784nir.asm src/patched/cc784nir.asm` (the stock source's name at that tag) shows exactly patches 1–39; from there the source is organized for size and the git history is the changelog. The source is fully relocatable (every ROM address is a label); the addresses quoted in the stock notes apply to the stock build only.

What the stock firmware does, and the bugs these patches fix, are in [FIRMWARE.md](FIRMWARE.md); the over-the-air update mechanism the patched build carries is in [OTA.md](OTA.md); fitting the chips it needs is in [UPGRADES.md](UPGRADES.md).

---

## 1. Memory map

RAM, with the chip-size detection of patch 13:

| Range | Use |
|---|---|
| `4000–40BF` | `FRAMEBUF` — 192-byte column ring (stock: 344 from `4040`); also where the OTA RAM library runs |
| `40C0–42C3` | `TXBUF`; `IMAGE`, the variables with a non-zero boot value (one `LDIR` from `INIT_DATA`); `BOOT_ZERO`, cleared at every boot; scratch buffers; then what survives a reset: `SEQ_LIST`, the boot count (patch 40), the clock, the store limits and the configuration block at `42BD–42C2` (patch 35) |
| `42C4`–`STORE_TOP` | `MSG_STORE`: about 15 K with a 62256, about 7 K with the stock 6264 (`STORE_TOP_8K`); `B4 '1'` reports the exact size |
| `7E0D–7EAC` | **stack**, `STACK_SIZE` bytes, the lowest `STACK_CANARY` of them laid with a `0x55` canary at boot (patch 40); `5Exx` on the 6264, which mirrors `6000–7FFF` onto `4000–5FFF` |
| `STREAM_AREA`–`7EEF` | reply stream and packet state (patch 21), display divider and service marks (patch 26), the IR gate's sample and state (patch 35), the keypad's mode and state (patch 36), the health counters (patch 40), the status report being sent (patch 41) |
| `7EF0–7FFB` | packet flag, buffer and parser state |
| `7FF0` | `NMI_SEEN`: FF once a mains NMI has fired since reset |
| `7FFC–7FFF` | boot stub: `NMI_VEC`, `NMI_MAGIC`, `ROM_BANK` |
| `C000` | `BANK_REG`, the added '273 (write-only; bit 0 = EEPROM A14) |

ROM, per 16 K bank ([OTA.md §2](OTA.md#2-rom-layout-each-bank)):

| Range | Use |
|---|---|
| `0000–023F` | boot stub: reset, `0038`, `0066`, bank choice, trial marking, the RAM library. Programmer only |
| `0240–0248` | jump table: `JP app_start`, `JP int_timer`, `JP nmi_entry` |
| `0249–3FBF` | application (`ROM_ID` among its data, stock `0048`), then free space (`FF`) up to the trailer |
| `3FC0–3FFF` | trailer page: magic, sequence number, state, CRCs |

## 2. Patches

### 1. Relocate the stack

*fixes B1*

The stack is carved off the top of the message store instead of the 64 bytes below `4000`: `STACK_SIZE` bytes (sized in patch 35; the stock measurements are in [FIRMWARE.md §3](FIRMWARE.md#3-execution-architecture-h)). Every `LD SP` uses the symbol. The store's ceiling and the constants `store_init` derives from it move down together, and `store_init` writes the `0xDA` store terminator through `STORE_LIMIT` before zeroing the packet page, since the terminator does not sit inside that page.

### 2. Restore the clock

*fixes B2*

`pkt_process_done` sets `CLK_RUN=FF` inline. This covers every early exit, not just `cmd_17_set_time`'s. `cmd_17_set_time` itself cannot be fixed in place: `pkt_next_byte` reads the caller's stack frame (`POP IX/DE/IY`), so no helper can be interposed.

### 3. Fix the cursor store

*fixes B6*

`LD (STORE_CURSOR),A` → `LD (STORE_CURSOR),HL` in `pkt_insert_text`.

### 4. Default address 1 + valid complement

*fixes B5 and B7*

`LD A,0 / LD (MY_ADDRESS),A / LD (…INV),A` → `LD HL,FE01 / LD (MY_ADDRESS),HL / NOP / NOP`. `MY_ADDRESS_INV` is `MY_ADDRESS+1`, so one 16-bit store writes both, and `FE` is a genuine complement of `01`.

### 5. Shift only the live store

*fixes B8*

`LD HL,(STORE_LIMIT)` → `LD HL,(STORE_END)` in `pkt_insert_text`, a two-byte operand change.

### 6. Sane defaults after RAM loss: clock at 12:00 AM, empty store, demo

`init_vars` copies its RAM image from `CLK_RUN` up, so `CLK_H10`…`CLK_PM` (4200–4205) are left alone on purpose, to survive a battery-backed power cycle. Without a battery they are SRAM noise: `clock_tick` only tests for equality, so a garbage second count runs through 255 before wrapping, and `render_clock` shows digits 10–15 as `: ; < = > ?`. The message store is noise too, and `store_repair` faithfully tidies it into 100 channels of garbage that the default sequence then plays. The fix sits in the branch patch 4 already owns — the `MY_ADDRESS`/complement check fails exactly when RAM is fresh — and writes `1 2 0 0 0 0` to the six clock bytes (12:00, seconds 0, AM) and calls `store_clear_all`, so `init_sequence` sees every channel empty and runs the demo, exactly as after a CLR ALL. With a battery and valid RAM the branch is skipped, as before. The clock runs from midnight rather than waiting to be set.

### 7. RAM re-layout

Three changes, each a constant:

- The stack is `STACK_SIZE` bytes above the store instead of stock's 64 below `4000` (see patch 35 for its size).
- `FRAMEBUF_SIZE` 344 → 192. The column ring only ever holds the 86 visible columns plus the glyph being written (at most 32 more, plus the 8-column lead of patch 42) — the four-rows-of-86 size is not needed. TINY mode's output frame lives in `TXBUF`, which is idle while TINY text is displayed (effects are off, and a packet resets everything anyway); the TINY line buffer (`FRAMEBUF_TINY`, 189 bytes from the ring start) fits in the ring.
- `FRAMEBUF` `4040` → `4000`: the stock stack slot is free once the stack has moved.

### 8. Compact the variable block

*+72 bytes of store*

Every byte of the block that nothing reads is gone: ten write-only variables together with the code that fed them, and the unnamed bytes between variables, including `INIT_DATA`'s misaligned second copies of `RX_TIMING` and `rx_st_wait_start`. `MSG_STORE-1` looks dead and is kept: it takes a space from `store_repair` on every boot (`STORE_GUARD`). Stock's `tiny_scroll_off` scans the four bytes after `FB_COL` through a typo'd pointer and always finds a `0x95` constant, so TINY always pushes the display off first; the scan is gone and that behavior kept. Verified by an emulator census (every RAM byte read or written across the suite, attributed to its symbol), and `compare`/`stack`.

### 9. Remove the unreachable code

A static reachability walk over the assembled listing (roots: the three vectors plus every label loaded as a vector or stored as data) leaves five islands nothing can jump to: `keypad_scan` (47 bytes, not referenced at all), `menu_enter` (48 bytes — an "enter your address or `*`" gate that nothing enters; serial `01` goes to `key_handler`), and three orphans behind unconditional jumps (an extra `LD A,0x20` after `clock_emit`, a digit-decrement stub after `editor_key_bgrnd`, a stray `DJNZ/JP` after `cursor_left_8`). Also gone: the raw bytes the disassembly kept as `db` (an unreachable `JP render_loop`, a `RET`, a `JP`, the `AA 55` pair), the five `NOP`s (two of them patch 4's size padding), and `tick6_service`'s re-entrancy guard, which tested `(IX)==AA && (IY)==55` against registers nothing ever points there. About 140 bytes of ROM, zero behavior (`compare` clean).

### 10. Boot stub, bank register and A/B layout

*[OTA.md](OTA.md)*

`0000–023F` is a stub that picks a bank by trailer and CRC and runs its app through a jump table at `0240` (`STUB_END`); the `0066` NMI goes through a RAM vector guarded by `NMI_MAGIC`. `ROM_ID` sits in the app, and `pq_romid` uses the label rather than a raw `0048`. Boot is ~1 s slower: the CRC pass.

### 11. OTA command set

*`CMD_OTA` = `B5`, `cmd_B5_ota`, [OTA.md §4](OTA.md#4-the-ota-command)*

info, page CRCs, begin, write 1–3 pages, finish, reset. Runs the stub's RAM library from `FRAMEBUF`; pages inside the stub refused. ≈ 540 bytes of ROM.

### 12. `tx_try_queue` reports busy with carry

*fixes B10*

### 13. RAM at the top of the 16 K window; chip size detected at boot

The board decodes RAM for all of `4000–7FFF`; the 6264 mirrors the upper half. Everything at a fixed address (packet buffer, stream area, stack, the stub's bytes) sits under `RAM_TOP` = `8000`, which the 6264 aliases to `5Exx/5Fxx` for free, and `ram_probe` writes a marker through the mirror at boot to pick `STORE_TOP` or `STORE_TOP_8K` (store sizes in §1); it puts back the byte it wrote, which on the larger chip is in the store. `B4 '1'` appends the longest payload a frame may carry (`PKT_MAX`, 254: the byte after is `NMI_SEEN`); a longer frame is parsed, kept nowhere and not answered. One build for both chips; a 62256 is two wires ([UPGRADES.md](UPGRADES.md)).

### 14. Payload bytes are not keys

*fixes B12*

`rx_consume` clears `RX_BYTE` after `pkt_feed_byte`. The OTA handler also blanks the panel before each reply (its RAM library sits in `FRAMEBUF`) and shows a parked update message (`>FW ↑<`) from `B5 'B'` to the reboot through the factory test mode.

### 15. APPEND seats like DELETE_TEXT

*fixes B11*

the extra step back onto an empty channel's marker is gone.

### 16. DONE handshake

Immediate mode is "flag bit 7 set"; with bit 0 set as well (`81`) `pkt_process_done` queues a `04` byte, which leaves once the packet is processed and its reply sent, so the sender waits for it instead of guessing at the deaf window of B4. Addressed frames only; NETCC's `80` is unchanged. `B5 'I'` gains a features byte (bit 0) so the host can tell. `cc784.py --done` and `cc784_ota.py` use it; chunked messages and OTA pages then follow each other at wire speed.

### 17. Label strings parked in the index-space gaps

*+237 bytes*

Stock's label lookup is `ATTR_LABEL_TABLE + 2·attr`, so the color-name table must sit 256 bytes after it and the speed labels 128 bytes after the `B0` table; the slots in between (`20–7F`, `D0–EF`) are never indexed. Stock filled the first gap with eleven "TOP OF MSG n" strings that nothing can display (the redraw treats `D0`-class bytes as characters; the real banner is built by `show_top_of_msg`) and the second with zeros. The tables and their gaps are gone: the labels are one keyed list, `LABELS` (§6).

### 18. Trial and confirm

`F` writes a new image's trailer as TRIAL; the stub rewrites a TRIAL trailer as TRIED before booting it and treats TRIED as invalid, so an image that crashes, hangs or cannot talk is skipped at the next reset. `B5 'K' state seq` rewrites the running bank's trailer: the host confirms (GOOD) once the image answers, or lowers the sequence number to roll back. `NMI_SEEN` (`7FF0`), set by every mains NMI, lets the page writer skip its NMI sync on a DC supply instead of waiting forever; `I` reports it. The stub occupies `0000–023F`.

### 19. RAINBOW starts on a random color

`BC` set the cycle index to 1 and the per-character step advances before it looks up, so every rainbow began on orange. The index now starts at 1–5 from a running 8-bit generator (MAGIC's `RND_SEED`, stirred with the mains and tick counters), so each display cycle begins on a different one of the five colors, on AC and DC alike. Patch 28 adds the direction: bit 7 of `RAINBOW_IDX` (`RAINBOW_REVERSE`), taken from the generator's top bit at the same moment, makes `rainbow_step` count down instead of up, so half the cycles run red, green, lime, yellow, orange.

### 20. Clock digits next to the store

The stub copies its 322-byte library to `4000` at every boot, which runs 130 bytes into the variable block (`RAM_VARS+00..81`). At stock's `+62..67` the clock digits are overwritten at every power cycle ("0=:39 PM"). They now live at `+1F3..1F8`, swapped with six scratch bytes; `CLK_RUN` stays, since the init image rewrites it on every boot. An `ASSERT` keeps the library below `SEQ_LIST`, and `ram` in the emulator checks that a set clock survives a reset.

### 21. Packets are processed by the render loop

Nothing in the interrupt context reads the message store, so `pkt_process` now runs as a subroutine of the render loop (`pkt_poll`, called at every render step and inside every frame wait) with interrupts on: no `DI`, no stack reset, no restart unless the text being played changed. Its effects:

- The display keeps scrolling through text loads into other channels, sequence changes, time setting and queries. A restart happens only for an edit of the playing channel, a clear-all, or the first text into an empty sign (the demo stops). The renderer's cursor is saved at entry and put back, shifted by the size change when a lower channel grew or shrank.
- The sign never goes deaf: the receiver keeps running. A frame that arrives before DONE is parsed in discard mode (`PKT_DISCARD`) and never answered, so its bytes cannot reach the editor as keys.
- Replies and DONE leave through a background transmitter: two segments with an optional appended sum (`TX_SEG0/1`, sent by `tx_stream_next`), so a store dump stalls nothing. The `B4` query frames are built over `PKT_BUF`; a query ends its packet.
- Text goes into the store in one move per run of plain bytes instead of one per byte (`pkt_insert_run`), and DELETE_TEXT moves the store up to its end instead of up to the RAM ceiling: a 240-byte load into a small store is now ~20 ms of processing instead of ~130.
- `cmd_B5_ota` waits for TX idle and does its own `DI`; OTA packets still park and restart the display.

The state lives in the stream area carved off the store top (`STREAM_AREA`, §1). The demo message is one line. Gate: `quiet` in the emulator; `compare` against a tree without this patch reports differences by design.

### 22. Typed queries removed

*−270 bytes*

The editor hooked `B4` plus a digit typed as keys and answered with its own copies of the three query replies on the serial line, which only a terminal driving the menus could ever see. `editor_query_hook`, `query_dispatch` and the three handlers are gone; packets keep theirs. `QUERIES_ENABLED` is gone with them.

### 23. Set-time starts the minute at :00

`17 hhmm a` carries no seconds and left `CLK_SEC` and the mains-tick count as they were, so the clock came up anywhere inside the minute. Both are zeroed now, and the host tool's `time` command waits for the top of the PC's minute and sends the frame 0.3 s early, which is its wire time.

### 24. Text without a channel goes to channel 0

*fixes B13*

The insertion point is derived from the renderer's cursor; while the demo plays that cursor is in ROM and the demo channel's lock (`CHAN_LOCK`) makes every insert a no-op, so the text was ACKed and dropped. A cursor below `MSG_STORE` now clears the lock and seats on channel 0 as `09 30 30 0E` would.

### 25. Restarts stop scanning at the store's end

`store_repair` runs on every restart and made three passes over the store's whole capacity, 15 K on a 62256, about a second with the panel dark. The passes now stop at the first `DA`; a store that has lost its `DA` still gets the full scan and the repair. Boot is now the CRC pass alone, and a restart after an edit of the playing channel is back on the panel in milliseconds.

### 26. Scroll speed by longer rows, not dark ticks

Stock paces the plain crawl by appending `SCROLL_SPEED` blanked ticks to every 21-tick frame, so the slow settings are also the dim ones: at speed 7 a quarter of every frame is dark. The display now runs on its own divider in `int_timer`: a display tick is 6 interrupts plus `DISP_STRETCH` sevenths of one, carried in `DISP_ACC`, and `frame_speed` sets the stretch to twice the speed for the plain crawl and to zero for effects, TINY and the editor. The 21 ticks of a frame then total the same `126 + 6 × speed` interrupts as stock's frame plus its blank ticks, so every column rate and the FLASH and HOLD timings are stock's, but the rows stay lit the whole time and the two intensity passes keep their 1:2 ratio. The carry pattern is rotated a seventh per frame, since 21 is a multiple of 7, so every row averages the same dwell to within one interrupt. Slower speeds cannot avoid the panel's limits: a 62 Hz column sampling rate means the refresh drops with the column rate, to 46 Hz at speed 7, and single-color text lights every other column, so it blinks at half the column rate. Both dividers only mark `SVC_DUE`; `tick6_service` runs when it is not already running and drains the marks itself, so the engines and the display never nest, which they must not: both read-modify-write the latch shadow and share the RX FIFO. `TICK1_COUNT`, a divider by one, is gone and its byte is the display divider. The TINY frame wait now polls for packets, since a TINY line is seconds of such waits. Gate: `speed` in the emulator, which checks every speed's refresh and column rate, that nothing goes dark and that the seven rows' dwells match. LITE keeps stock's dark ticks (patch 51).

### 27. Packets while the demo plays leave the renderer alone

The renderer's channel lock is saved with the cursor when a packet's processing starts (`PKT_SAVE_LOCK`) and put back with it, so the demo keeps its lock through a time-set, a query or a SEQ command; without it STOP would open the editor on the ROM cursor, and the first typed key would shift all of RAM down by one (`insert_shift` moves everything from the cursor to the store ceiling). A SEQ command (`PKT_SEQ_CHANGED`), or any packet while the demo plays, recounts the empty channels on the way out and restarts only if the answer flips between the demo and real text, so a sequence that lists a channel with text replaces the demo at once and a sequence of empty channels brings the demo back. `is_plain_byte` counts every printable character as plain, so a run of text goes in with one move of the store's tail, and the background transmitter starts only once a reply's segments are handed over (`TX_ACTIVE`). Gate: `quiet`.

### 28. RAINBOW runs in a random direction

See patch 19.

### 29. Factory test mode removed

*−137 bytes*

SEQ, then MAGIC, then C in the editor copied a "CURRENT TEST" pattern into `TEST_MSG_BUF`, summed the ROM into four hex digits after it and displayed that until the next key ([FIRMWARE.md §10](FIRMWARE.md#10-on-sign-editor--menu-19ca2a67-m)). On a bank-switched ROM the sum means nothing, and the OTA image carries a CRC. The prompt, the summing loop, the hex formatter and the pattern are gone; MAGIC in the SEQ menu now closes the menu like any other non-digit. `TEST_MODE`, `TEST_MSG_BUF` and the display path stay, because the OTA handler parks its `>FW ↑<` message (the `^` byte is the up-arrow glyph) through them.

### 30. Serial at 300 to 1200 baud, chosen by the host

*+220 bytes*

The bit engines move from the 1302 Hz tick into the interrupt handler itself, so a bit can be a few interrupts long. After a second of silence (`BAUD_IDLE_FRAMES`) the receiver times the next start bit: a frame's `B1` has a one-bit start pulse, 25.6 interrupts at 300, 12.8 at 600 and 6.4 at 1200, and that sets the rate for the frame and the session; the transmitter follows, so replies and DONE come back at the host's rate. Every session starts at 300 and falls back to it, so NETCC never sees a difference. The rate is read on the assumption that bit 0 of the first byte is 1, which holds for `B1` and for the bare `01` and `0D`.

Timing is in fifths of an interrupt. One value, `BAUD_T`, is the 300-baud bit, and the faster rates step the same accumulator 10 or 20 fifths per interrupt (`BAUD_STEP`). An interrupt is 128 µs plus the acknowledge latency, which varies with load, so `BAUD_T` is calibrated rather than assumed: `baud_calibrate` runs from the NMI once a second and takes the low byte of that second's tick6 count, 1280 + s, giving `(1280 + s) / 10`; the count is taken in the ISR where the tick6 mark is made (patch 35), not in the service that handles it, because a service running late merges marks, and the shrunken count would pull `BAUD_T` down a few percent (bit-7 errors in 1200-baud replies on a dimmed sign). A second is accepted only when it agrees with the one before within three ticks and lies within 5 percent of nominal, because a second that lost interrupts to a long DI stretch (an OTA page write, a restart) disagrees with its neighbors; `NMI_COUNT` starts at 0 rather than stock's 176 so whole seconds run from boot. The mains gives the second on AC; the add-in board's 64 Hz gives it on DC once the clock-source patch sets `NMI_PER_SEC`. With no NMI at all the default `BAUD_T` stays, which 1200 tolerates. `B4 '4'` (`cc784.py --unsafe stats`) reports `BAUD_T`, `BAUD_STEP`, the last second's count and whether an NMI has been seen, followed by patch 40's counters.

Because the engines now run inside the interrupt, the latch read-modify-writes in the display and the editor are closed to it (`latch_blank`, `latch_row`) and so is the FIFO reader, and the consumer drains the FIFO once per frame instead of taking one byte, since 62 bytes a second was enough for 300 baud only. The receiver can only look at the line once per interrupt, so a start edge is seen up to one interrupt late and every sample lands on an interrupt boundary: together up to a sixth of a 1200 bit, and long frames pass every time. 2400 is not offered: the same errors are a third of its bit, and on the board, with the period calibrated exactly, most 220-byte frames at 2400 were rejected while short ones passed. Patch 52 adds 2560, whose bit is a whole number of interrupts. Idle cost is a line poll per interrupt, about 6 percent of the CPU. Gate: `baud`, which runs every rate from cold, rate changes after a pause, 1200 over interrupt periods from 126 to 134 µs, 1200 on a DC supply and a 300-baud terminal session; `update` and `push` take a rate.

### 31. The clock source follows the add-in board

*+50 bytes*

The board puts a 74HC151 in the NMI line, selecting the mains zero-cross or its own 64 Hz from a 32 kHz crystal by the bank register's top bit, Q7 ([HARDWARE.md](HARDWARE.md)); bits 0 to 2 stay free for a larger EEPROM. At boot the app waits 75 ms, four mains cycles, for an NMI; none means no mains, so it sets the bit (`BANK_CLOCK_XTAL`) and counts 64 a second (`NMI_PER_SEC_XTAL`). From then on the clock runs on DC, the page writer's NMI sync works and the serial bit time is calibrated, all as on AC. The OTA library in the stub writes the bank register with the bank alone, which drops the bit for the duration of a library call, so `clock_bank` puts it back at every frame end and before each page write, whose sync would otherwise wait on a source that is off. A DC sign without the board sets the bit to no effect and behaves as before: the clock stands and the page writer skips its sync. Gate: `clock`, which runs AC, DC with the board and DC without it, through time setting, rollovers, an OTA page write and a 1200-baud frame.

### 32. 24-hour clock

*+50 bytes*

The set-time command's fifth byte takes `H` besides `Y` or `A` (AM; `A` is the stock NET's and the CC710's byte) and anything else (PM): hours are then 00 to 23, the display keeps the leading zero and drops the AM or PM, and the hours wrap at 24 instead of flipping at 12. The mode lives in bit 1 of `CLK_PM` (`CLK_24H`), next to the digits, so it survives a power cycle with them. The on-sign TIME? prompt still enters 12-hour time and sets 12-hour mode; its AM? Y/N question also takes `A` and `P`. `cc784.py time24` sets it from the PC.

### 33. Short jumps

*−217 bytes*

The assembler never shortens a `JP` to a `JR`, so the 217 absolute jumps in the app that reach their targets within short range are written as `JR`; the three jump-table entries at `0240` stay `JP`, since the stub enters them at a three-byte stride. A taken `JR` costs two cycles more than a `JP` and a skipped one three fewer, and nothing in the app keeps time by cycle counts: the tick, the scan, the serial engines and the seconds are all hardware-paced, and the bit-time calibration absorbs the slightly longer average acknowledge latency. Verified by every gate and by `compare` against a build without this patch, which matches in every serial and display phase; the editor and MAGIC phases differ as they do between any two builds of different size, because the remote's frames land on a different interrupt phase and the random seed reads the ROM.

### 34. Peephole

*−46 bytes*

Thirteen conditional jumps whose target is a lone `RET` become `RET cc`; three `CALL` immediately followed by `RET` become `JP`; three jumps to the very next instruction and one conditional jump that could only ever be taken (a `JR z` right after `JR nz` to the loop) are gone; and nineteen `LD A,0` whose flags nothing reads become `XOR A`, each checked by walking forward to the next flag-setting instruction for a flag consumer. The remaining six `LD A,0` have a consumer in that window and stay.

### 35. Configuration block

*+163 bytes, 7 of RAM*

Six bytes just below the message store, battery-backed like the clock beside them: a signature, the address, a flags byte, hold time, flash rate and an 8-bit sum. The signature and sum are the RAM-validity test at boot, in place of `MY_ADDRESS` against its complement; a failed test applies the defaults (address 1, full brightness, hold 80, flash 13, beeper on, nothing else set) and clears the store and the clock as before, so the first boot of this build starts clean, like a battery change. `B6 index mask value` writes the bits of one byte that `mask` selects (the signature, the address and the sum are refused; the flags byte keeps its live bit), `B4 '5'` returns the block and `B4 '6'` the sequence list; the address is still set only by the editor's ADDRESS? dialog, which reseals the block. Brightness is lit time, not passes (LITE has off and full only, patch 51): the two intensity passes carry bit 0 and bit 1 of every color channel, so dropping a pass would drop a bit from every color (lime turns red). Instead, when dimmed, `latch_row_dim` leaves the row select to the ISR, which lights the row on its next interrupt and parks the rows after 1 or 2 interrupts of the single-tick pass and 3 or 6 of the double-tick pass (a row is lit for 3 and 9 interrupts of those passes, the rest going to the next pass's 86-byte output), so every pixel loses the same share: low is one third, medium two thirds, with no color shift. Lighting on the interrupt grid matters: lit straight from the latch, the row carries a 0 to 128 µs remainder that drifts and pulses at a few hertz. Off and mute keep the row dark, at once or at the next message boundary; TINY rows last two ticks and are timed like the double-tick pass. Hold time replaces the `HOLD_FRAMES` constant at every site and flash rate the `FLASH_HALF_PERIOD` compare; the beeper gate sits in `beep_start`; a locked sign drops remote keys in `ir_frame_done` before either consumer sees them. The flags byte: bits 0–1 brightness, 2 muted, 3 mute pending, 4 beeper off, 5 remote locked, 6 wrapped, 7 status reports (patch 41); bit 6 is live state left out of the sum, set by a sequence wrap until the next message clears it. Each flags setting is its own mask (brightness `03`, mute `0C`, beeper `10`, lock `20`, status `80`; hold and flash take `FF`), so a host changes one without reading the block first or disturbing what another host set. A `B6` is taken while the editor is open too, where other frames are answered BUSY (patch 45): packets wait for the render loop, which the editor stops, so the receiver applies it on the spot (`pkt_in_editor`, through the same `cfg_write`) and answers ACK, never DONE. The brightness clock costs the ISR one load and branch per interrupt and the row output a check per pass: about ten percent more time to process a packet into a nearly full store (1.07 s to 1.17 s at 15 K; 0.1 s either way when the store is small), so the `ram` gate waits for DONE, as a real host does. The OTA commands that read the idle bank (`I`, `C`, `F`) hold the NMI vector off around the copy (`ota_copy`): the stub vectors the NMI through the jump table of whichever bank is mapped, so an NMI during the copy would run the other image's `nmi_entry` and `clock_tick` against this image's RAM map; the emulator reports such an NMI as a fault, and `push --all` avoids `C` on a sign running a build without `ota_copy`. The stack is 160 bytes. Measured on the signs: 84–88 bytes during playback, 86 in the editor, 112 during a push's page-CRC commands and 130 while 57 channels of text load into a nearly full store; normal running leaves 56–72 bytes untouched. 160 leaves 30 over the deepest measurement and about 10 over the constructed worst case of an NMI at the deepest interrupt moment; an overrun runs into the top of the message store. A parked row costs the ISR nothing (`LIT_LIMIT` is cleared at the park and re-armed by the next `latch_row_dim`). The dimmed interrupt costs about 5 percent of the CPU, more than the renderer can spare with a message loaded (it pauses visibly at low brightness), so the IR decoder's per-interrupt handler, about 90 cycles or 6 percent of the CPU even on a sign with no receiver, is skipped while the decoder is waiting for the line to move (`IR_QUIET` holds the line level the decoder sleeps through: 0 from `ir_st_leader` on a low line, `PORT_IR` from `ir_st_idle` or `ir_st_leader2` on a high one; the ISR sets it to FF, awake, when its port sample shows the other level). The third case covers an unplugged receiver, whose floating line can walk the decoder into `ir_st_leader2` to wait for a fall that never comes. A row code left pending goes with the row when `latch_blank` parks it; otherwise a service running late, which starts the next pass at once, would have the ISR light the old code while the next row's 86 bytes are mid-shift, and the panel shows the chain's contents as noise. The host's OTA tool waits 8 s for a reply, since every OTA command restarts the display and a sign with an empty store then scans its channels for over 2 s without reading packets. Verified by the `config` gate.

### 36. Wired keypad; IR moves to bit 4

*+129 bytes, 3 of RAM*

Needs the second '244 of [UPGRADES.md §8](UPGRADES.md#8-ir-off-the-db9): the decoder reads the receiver on `PORT_IN` bit 4 (`IR_BIT`), leaving bits 0–3 to the keypad, so a sign without that mod has no remote on this build. The decoder's tests and masks change in place. The keypad takes all seven DB9 signals as on the NET (row select on latch bits 4–6, column code on bits 0–2, key pressed on bit 3 = RX), so serial and keypad never run together. The NET's boot test (a cable with pin 2 shorted to pin 5 means a PC) is not used, because a sign booted without that cable goes deaf to serial and to OTA. Instead, at each frame end (`kp_poll`): in serial mode, 256 frames in a row of the RX line at space, which is a keypad's idle and also an empty socket, switch to keypad mode (4.2 s at the full frame rate; frames stretch at slow scroll speeds); in keypad mode the eight rows are scanned, one row per `DI` so the IR decoder's ticks stay on time, and all eight reading a key is a host's TX idling at mark, which switches back to serial within one frame. `rx_start` ignores the line in keypad mode. A key's code (row × 8 + column) is turned into the remote's key number by a reverse search of `IR_KEY_TABLE` (`CPIR`) and written to `IR_CODE` as the decoder would, so the editor, debounce, repeat, STOP/START and SPACE treat both inputs alike; the release code follows two empty scans (33 ms), which absorbs contact bounce. The table's entry for key 1D, SHIFT, is never read, since SHIFT is caught before the table; it now holds the keypad's SHIFT code, 19. K has two matrix positions, 00 and 1E, and 1E is mapped to 00; 1F is the matrix's empty position. Keypad keys ignore the remote lock. A key pressed while the demo runs an effect waits like the remote's STOP does, since effects pause the frame end. `ir_init`, called when the editor opens, also sets `IR_QUIET` awake, so a gate left set by the leader wait cannot cost the next key its first frame. Gate: `keypad`, at 16-cycle emulator slices, since at the default 128 a `DI` holds an interrupt up to 16 µs and costs the remote frames the hardware would not lose.

### 37. CC710 build

*`-DCC710`*

The CC710's panel is 59 columns of 74HC595s latched by the port `80` strobe ([HARDWARE.md §4](HARDWARE.md#4-the-cc784-3a-board-original-cc784-and-cc710-h)), on a `CC784-3A` board converted per [§5](HARDWARE.md#5-converting-a-cc784-3a-board-to-a-cc784-4). With `CC710` defined, `FRAME_COLS` is 60 instead of 86 and the output is `cc710_patched.bin`. Everything that depended on the width derives from it: the second frame-buffer row (`FRAMEBUF_ROW1`), the TINY line (`FRAMEBUF_TINY` and its scroll, twice `FRAME_COLS`, pushed out by 20 spaces instead of 28), the push-off before TINY (`FRAME_COLS/6` spaces), the end of the staging frame (`STAGE_END`, which is `FB_COLPTR` itself on the CC784), the empty-stage test (`FRAME_COLS/2`) and the initial `FB_OUT_LEN`. The strobe needs nothing: every row and the chain clear already end with `OUT (PORT_STROBE)`, which the '595s latch on and the '164 panel ignores. The rest, the 100 channels and the CC784's ROM ID included, is the CC784 build's, except the editor's prompts and messages. Those are shortened so that each prompt, with the digits typed after it, fits 59 columns: `MSG nn`, `ADDR? nnn`, `FULL? nn`, `CLR? Y/N`, `TIME? HHMM`, `PROG? nn`, `SEQ? nn` and `MAGIC nn`. The right-aligned messages `INVALID`, `MEM FULL`, `100 LEFT` and `SEQ FULL` are padded to the window as on the CC784. Where the factory CC710 ROM has a wording, the build uses it. Checked in the emulator with text, an UP wipe, TINY and every editor prompt on 60 columns.

### 38. Shared code

*−350 bytes*

Duplicated runs are folded into one copy each: `menu_prompt` starts a fresh frame and shows a prompt, and `menu_show_text` takes its string in HL, so `MENU_TEXT_PTR` is unused. `editor_reshow` and `editor_back_if_mark` replace five copies of the channel-marker check. SPEED, GRAPH, COLOR and BGRND set their flag through `editor_set_pending`. Four effects end at `fx_hold_done`. `glyph_addr`, `char_flags` and `glyph_put_next` replace the glyph-address, `CHAR_FLAGS` and digit-drawing sequences. MAGIC's push-off before an effect calls `tiny_scroll_off`, so it pushes `FRAME_COLS/6` spaces: 14 on the CC784 as before, 10 on the CC710. Behavior is unchanged: the full emulator gate set, the CC710 editor prompts and the MAGIC announcement give the same results as before.

### 39. The sequence skips empty channels quickly

*+39 bytes, no RAM: `CHAN_HINT` reuses the unused `MENU_TEXT_PTR`*

`chan_select` found a channel by scanning the store from its start, and built the marker by counting up to the channel number, so each step of the sequence cost time in proportion to the channel number. With the default sequence 0–99 and one message loaded, the 99 empty channels took about 1.05 s per loop, during which no packet was processed. Markers sit in the store in channel order, so a channel at or above the one at `CHAN_HINT` is now scanned for from there. The hint needs no updating when the store changes: two marker bytes in a row are always one marker, since every channel ends in `03`, so if the hint no longer points at a marker, or points past the store's `DA` where a shrunken store leaves stale copies, the scan starts from the beginning. The marker is built by dividing by ten. The 99 empty channels now take about 50 ms, and a short message's loop drops from 2.6 s to 1.6 s.

### 40. Health counters in the `B4 '4'` reply

*+154 bytes, 13 of RAM*

The timing reply keeps its four bytes and appends fourteen, so a host can poll a sign's health through its dongle: the NMIs per second (60 mains, 64 the add-in board's crystal); a boot count in the free byte beside the clock, which survives a reset and restarts at 1 after RAM loss; stack headroom, the bytes left of a 128-byte `0x55` canary laid at the stack's bottom at every boot; display ticks merged because the last one was still due, for the last second and the worst second; uptime in seconds (3 bytes); renderer stalls, counted when the frame end finds that `pkt_poll` has not run for 3 frames, with the longest gap in frames (the editor, which does not poll, is skipped); frames with a good and a bad checksum; remote frames decoded, and dropped after their leader. Every counter except the boot count lives in the stream area, cleared at boot, so the store's ceiling drops by 13 bytes. Counters wrap at 256. The sequence's step over empty channels (about 50 ms for 99 of them) calls `pkt_poll` for each, so it neither holds up a packet nor counts as a stall. `cc784.py --unsafe stats` prints them (`timing` stays as an alias). Gate: `stats`.

### 41. Status reports

*+97 bytes, 6 of RAM*

With `config set status on` (flags bit 7; off by default, so a host that does not expect them never sees one), the sign sends `B1 addr 03 'S' channel flags sum` at every channel start, and with channel `FF` when the editor opens; the flags byte is `CFG_FLAGS` as patch 35 lays it out, bit 6 meaning the sequence wrapped to this channel. A report goes out only while no reply is streaming and no frame is arriving, and is dropped otherwise. A frame can still begin while one is on the wire, and a minimal frame is as long as a report, so two guards keep the replies whole: the ACK or NAK of a frame that ends during a report waits in the transmitter's trailing-byte slot (`TX_DONE_PENDING` holds the byte to send: `DONE`, or a deferred ACK or NAK), and `pkt_process` waits for the report to finish before it builds a reply. `cc784.py` takes reports out of the byte stream before its readers see it, so every command works with reports on; `cc784.py watch [SECONDS]` prints them. Gate: `status`.

### 42. The crawl keeps columns in hand

*+69 bytes*

Stock's LEFT crawl draws a character and then waits until the scroll has caught up completely, so right after every catch-up the renderer has nothing in reserve, and a packet processed at that moment (50 to 65 ms for a 250-byte frame, most of it the interrupt and panel load around a few milliseconds of store work) stops the scroll. The render loop's wait (`crawl_step`) lets the next character be drawn while `CRAWL_LEAD` (8) columns or fewer are still to scroll in, about 130 ms of cover at full speed. A character qualifies, in MAGIC too, also behind the bytes that only change state: colors (`80`–`93`), which go into the next glyph's column in the same render step, the fonts and FLASH (`BIG`–`FLASH`), MAGIC, MAGIC OFF and THIN; the clock's `5F` counts as text. Any other attribute, the end of the message and every effect still wait for the full catch-up, as do the push-off loops before TINY and the editor (`effect_step`, unchanged), so effects, HALT and TINY see the scroll as stock does. A styled crawl (colors, FLASH, BIG, ITALIC, graphics, the clock, UP, HOLD, HALT) sends the panel the same frames as without the lead, and during a load no panel step takes longer than the normal 16–18 ms. The renderer still pauses while a packet is processed, so patch 40's stall count includes those pauses, which the lead hides. The end of a channel turns MAGIC off before its push-off (`fx_end_of_channel`), whose spaces in MAGIC's fonts paused the crawl at 4 MHz.

### 43. No editor during an update

*+12 bytes*

STOP on the remote or the wired keypad opens the editor from display mode, and stock's bare `01` on the serial line did too. During an OTA update that would reset the stack, clear `TEST_MODE` (dropping the update message) and echo keys on the serial line, where the host reads them as broken replies and abandons the push with the idle bank half written. The STOP key's path into the editor passes one jump (`key_handler_jr1`), which uses the key up and returns while `TEST_MODE` is set, from `B5 'B'` to the reboot. A push that dies without its reboot therefore leaves the editor shut until the next power cycle; the panel says so meanwhile. Gate: `update`, which presses STOP and sends `01` after `B`.

### 44. Remote decoder clocked by the line's edges

*+171 bytes, 6 of RAM*

Stock counts ticks from the end of the leader burst and samples every cell at two fixed points, so the whole frame rides on the interrupt period being 128 µs. The board's period is 128 µs plus the acknowledge latency, 130.2 µs as the baud calibration measures it, and over the 72 ticks of a frame that error reaches 144 µs of a 244 µs budget shared with the tick phase and the receiver's burst stretch, so stock drops about half the remote's frames on this board; the two-frame debounce and the 90 ms repeat turn the losses into keys that need a second press. The decoder trusts rising edges only, the one edge the receiver reports on time (it stretches every burst's end by about 250 µs, so the bursts of a 0 and a following 1 merge). After the leader falls, the start burst must rise 10–23 ticks later; a rise within two ticks of the fall is the leader resuming after a dropout and is waited out again, and any other early rise is a stray burst and is ignored. From the start rise on, every cell is timed from its own edge: a rise in a cell's first three ticks is a 1 and restarts the count, one at ticks 4–2 is a 0, and a cell without a rise is a 1 merged with the 0 before it. Biphase gives the checks in place of the complement sample: a cell without a rise must follow a 0; a cell opening with a rise must follow a 1; and the line must be low through the first two ticks after a 1, since a burst there is either a gap bridged by noise or a 0 faked into a 1 by a burst at its start that ran on into the real one. Rises inside a cell that already has its burst, and rises where neither position fits, are strays and are ignored. A leader counts after 1 ms of quiet instead of 16, since no gap inside a frame but the leader's own exceeds 0.8 ms, so a stray burst shortly before a frame does not cost it. On the consumer side, a key whose second frame was lost registers when its release frame arrives within 0.3 s of the first (`IR_DEBOUNCE_WINDOW`), and two different keys inside one window cancel each other: a frame the decoder rejects costs nothing unless its partner is lost as well, while a mis-decoded frame still cannot type. The same rule covers keys lost to the editor's longer redraws, which would otherwise overwrite an unread code with the release. A seen key is stored with bit 6 set (`IR_KEY`, `IR_DEBOUNCE`), so the idle value 0 is never mistaken for key 0, which in stock types on a single frame. `B4 '4'` grows by four bytes, remote frames by fate (no start after the leader, which is what a stray burst taken for a leader comes to; stray rises ignored; a rise missing after a 1; a burst in a gap), which `cc784.py --unsafe stats` prints. Emulator: every key decodes at interrupt periods from 128 to 132 µs and stretches from 0 to 350 µs with no wrong codes; through random bursts every 20–120 ms, 24 of 27 frames decode (stock's decoder: 8) with none wrong; bursts every 6–9 ms block either decoder. Gates: `keypad`, `config` and the full set, plus the editor session A/B of §6.

### 45. Frames only on the serial port

*+168 bytes, 2 of RAM; fixes B9*

Stock reads the line two ways: in display mode a byte outside a frame is a keystroke (a bare `01` opens the editor), and in the editor every byte is a key, frames included. So stock types a frame sent while the editor is open into the message, and a frame that loses a byte opens the editor: the parser trusts the length byte, so a short frame swallows the head of the host's retry, the rest of the retry arrives as loose bytes, and its address byte (`01` at address 1) is the editor key. In this build no byte outside a frame is a key unless the host asks for that, and the parser finds its way back on its own. `rx_consume` parses frames in the editor too. A second of silence (`BAUD_IDLE_FRAMES`, the gap after which `rx_start` times the next byte as a frame's `B1`) ends any frame, so a byte lost mid-frame costs that frame and not the retry, which comes seconds later. A flag byte other than `80` or `81` means the `B1` was no header: the parser looks for the next `B1`, starting with the flag byte itself. While the editor is open, a good frame to the sign's address is answered `18` (BUSY) and dropped (a `B6` excepted, patch 35), so a host learns why its load was refused instead of seeing it typed. `B7` frames are the exception, in both modes: `B7 '1'` opens the editor as a serial terminal (`TERM_MODE`), or makes an open editor one; in that mode bytes outside frames are keys and are echoed as before, while a `B1` and everything after it go to the parser (`rx_key_ready` leaves a key at the FIFO's head for `editor_getkey`). A terminal's keys come seconds apart, so in that mode `rx_start` keeps the rate the `B7 '1'` frame set instead of timing the first byte after a second of silence as a `B1`: a key whose bit 0 is 0 has a two-bit start pulse and would be read at half the rate (at 1200 baud, `B` came back as `80`). `B7 '0'` closes the editor as STOP does, from any prompt (`EDIT_CLOSE`, checked in `menu_getchar`): the channel joins the sequence as on STOP, and the clock runs again if TIME? was half typed. Both are answered with an ACK only, never a DONE; `B7 '1'` during an update opens nothing (patch 43). The editor opened by the remote or the keypad takes no serial keys and, unlike stock, sends no stray `01` when it opens. A loose `20` still releases a WAIT. `cc784.py stop` and `start` send `B7 '1'` and `B7 '0'`, and every command reports BUSY. Gates: `term`, plus `baud`, `config` and `update`, which send `B7`.

### 46. RANDBOW, and `B2` for variants

*+191 bytes, 2 of RAM*

Only `B2` and `BF` were left without a meaning in the store's code space, so `B2` (`ATTR_ALT`) becomes a prefix: the variant of the attribute after it. Stock's `CHAR_FLAGS` marks `B2` invalid, and `store_repair` turns it into '?' at every boot; it is an attribute now. The first variant is `B2 BC`, RANDBOW: each character takes one of RAINBOW's five colors (red, orange, yellow, lime, green) dealt from a shuffled deck, all five once before the deck is dealt again, and a new deck never starts with the color that ended the last, so no color shows twice in a row (`randbow_deal`, `RANDBOW_DECK`; the full-period `RND_SEED` step guarantees every color turns up). `attr_rainbow` looks at the byte after a `B2`: `BC` starts RANDBOW, anything else leaves the `B2` skipped. A color attribute ends RANDBOW as it ends RAINBOW. In the editor, SHIFT after FUNC gives FUNC2 (the status line says `FUNC2`; the shift itself is undone), and FUNC2 looks the next key up in `FUNC2_TABLE`: COLOR inserts `B2 BC`, the second byte from `ALT_NEXT` on the next pass of the editor loop. The editor labels a variant by its own text, keyed by the attribute XOR `40` in `LABELS` (`RANDBOW`), and shows nothing for the `B2`; LEFT and RIGHT pass over the `B2`, so the cursor stops once on a variant and never rests on its prefix, and DEL of the attribute takes its `B2` along. On the remote: SHIFT, STOP/START (FUNC), SHIFT (FUNC2), COLOR; the wired keypads and the serial terminal (`B7`, `1D`, `15`) take the same path. `cc784.py` writes it as `@{randbow}`. FUNC + C types a comma, which the remote has no key for (as FUNC + Q and FUNC + X type `?` and `!`). Gate: `randbow`.

### 47. A cancelled FUNC keeps the stack

*-1 byte*

FUNC followed by a key with no second function cancels through `func_cancel`, which drops return addresses before it jumps back into the editor. Stock reaches `editor_key_to_attr` by a CALL from `editor_translate_key`, so two return addresses are there to drop; the peephole pass of patch 34 made that CALL a jump, so one is, and every cancel lifted the editor's stack two bytes above `STACK_TOP`, onto `PKT_READY` and into `PKT_BUF`. The editor's own pushes then left a packet flagged as ready, made of return addresses, which the renderer processed when the editor closed: stray characters at the start of the message being edited. `func_cancel` drops one. Gate: `randbow`, which cancels FUNC three times and checks the editor's stack and `PKT_READY`.

### 48. SCROLL UP and SCROLL DOWN

*+206 bytes, 1 of RAM*

`B2 1A` and `B2 1B` are the variants of the UP and DOWN wipes: the staged page pushes the page on the panel out one row a step, six steps of three frames, then rests and holds as the wipes do. Text that does not move sideways shows no colors (a column lights red or green LEDs, which blend only while the text crawls), so as in the stock wipes the moving frames carry pixels only, in a yellow row color that `fxv_scroll` sets itself (patch 53: it had kept whatever color the last crawl left, so a scroll after a RANDBOW crawl moved in a random color); the resting page keeps its color bytes, as the wipes' last pass does. `fxv_scroll` unrolls the panel's window from the ring into `GLYPH_BUF`, which nothing uses while an effect runs, stages the new page in the ring's spare bytes 96 up, and for step k forms each column from the two pages as one 14-bit value shifted by k (`scroll_pixels` gives a color byte no pixels). `attr_rainbow`'s look past a `B2` sets `ALT_FX` when a `1A` or `1B` follows, and `fx_up`/`fx_down` take effect 6 or 7 instead of the wipe; plain `1A`/`1B` wipe as before. In the editor: FUNC2 + UP, and FUNC2 + SHIFT + UP for DOWN (a SHIFT in FUNC2 shifts the next key; only the first SHIFT after FUNC makes FUNC2); labels `S-UP` and `S-DOWN`, and the wipes' labels become `W-UP` and `W-DOWN` to tell them apart. `cc784.py`: `@{scroll up}`, `@{scroll down}`. Gate: `scroll`.

### 49. TWINKLE

*+246 bytes, 3 of RAM*

`B2 19` modifies the hold that ends PAUSE, the UP, DOWN and RIGHT wipes, HOLD and the scrolls (patch 48). Put after the effect's attribute (`@{up}@{twinkle}`), it turns that page's hold into a twinkle: the page holds as long as a plain hold (`CFG_HOLD` frames), and every `TWINKLE_TICK` frames `TWINKLE_DOTS` random spots in the text go dark until the next tick, which puts the page back whole and picks new spots. A spot on an unlit pixel or a color byte changes nothing, so the number of dark pixels follows how much of the text is lit. Stationary text shows no colors. `attr_rainbow`'s look past a `B2` takes `B2 19` whole and sets `SPARKLE` to 1, with no flush and no change of effect; `fx_set` and `fx_left` clear it, so the modifier applies only to the page of the effect it follows: alone, in a crawl or before its effect it does nothing. `fx_hold_done`, where every staged effect ends with its page up, takes `SPARKLE` and runs `fxv_twinkle` in place of the plain hold. The frames are double-buffered: the column ring holds two panels, so each tick is built in the half not shown (`fb_back`; `page_back` copies the page from `TXBUF`, which is cleared only after the hold) and `fb_flip` points `FB_OUT_PTR` at it just after a frame end, between row passes, so the panel never shows a half-built frame. It sets `FB_COL` too, which the frame end would otherwise copy back. `sparkle_init` first copies the effect's last frame into the hidden half, so the columns around the text (HOLD's fill) match. `twinkle_pick` draws from a 16-bit xorshift (7, 9, 8) in `SPARKLE_RND`, seeded once per hold from `R` and `RND_SEED` (`twinkle_seed`); an 8-bit generator would fix each spot by the one before and reach only 256 spots, fewer after scaling. It scales to the text's width (it is centered, so `FRAME_COLS` less twice `STAGE_OFFSET`) and to the seven rows. A tick counts its frames from its start, since picking the spots takes a good part of a frame, and waits for no row, since `FRAME_DELAY` runs out just after row 6 and waiting for it would add a frame per tick. In the editor: FUNC2 + PAUSE (JUMP on the remote), label `TWINKLE`. `cc784.py`: `@{twinkle}`. Gate: `twinkle`.

### 50. GLIMMER

*+115 bytes*

`B2 BB` is the second hold modifier, used as TWINKLE is (`@{pause}@{glimmer}`, `@{up}@{glimmer}`, …): the page holds `CFG_HOLD` frames while dark diagonal stripes roll through it, up or down, slanting down or up to the right, both picked at random each time. The stripe is a byte of `GLIMMER_BAND` dark rows rotated one bit per panel column, so it sits a row lower (or higher) in each column to the right; a pixel byte has seven rows and an unused bit 7, so the rotation's period of 8 leaves a gap between stripes and puts one every eight columns across the page. Color bytes have no pixels but take a column on the panel, so they are left unmasked and still rotate the band, keeping the diagonal straight. Every `GLIMMER_TICK` frames `fxv_glimmer` builds the next frame in the hidden half (the page from `page_back`, the band masked in) and rolls the band one row: one left rotation a tick rolls it down, seven roll it up; the roll and the slant (bit 7 of the roll count in `E`) are chosen once per hold by `twinkle_pick`. It sets `SPARKLE` to 2 and shares patch 49's hook, buffers and generator. In the editor: FUNC2 + SHIFT + SEQ (HOLD is SHIFT + SEQ on the remote), label `GLIMMER`. `cc784.py`: `@{glimmer}`. Gate: `glimmer`.

### 51. LITE build

*`-DLITE`, alone or with `-DCC710`*

For an unmodified `CC784-3A` board ([HARDWARE.md §4](HARDWARE.md#4-the-cc784-3a-board-original-cc784-and-cc710-h)): 4 MHz, a 2 K 6116, a 27128 EPROM, no IR receiver. The output is `cc784lite.bin` or `cc710lite.bin`, a 16 K image burned as it is: with no valid trailer the boot stub runs bank 0, and its bank-register writes reach nothing on that board. RAM: there are ten channels (`CHANNELS`; `CHAN_DEMO` and `SEQ_LIST_LEN` follow it, and the variables after `SEQ_LIST` are addressed from its end, so the shorter list gives its bytes to the store). The variables only the full build uses, the IR decoder's state and counters, the OTA test message (`TEST_MODE`, `TEST_MSG_BUF`), the dimming state, the interrupt dividers and the start-pulse width, sit at the ends of their groups and are left out, so the store gains those bytes as well; the stats query sends zeros from ROM for the remote's counters. `ram_probe` also tests the mirror at `4800`, so the build runs on the 3A's 2 K, a 6264 or a 62256 (patch 13; on a 3A board a larger chip needs the socket work of [HARDWARE.md §5](HARDWARE.md#5-converting-a-cc784-3a-board-to-a-cc784-4) step 1); the full build assumes 8 K or more. On 2 K the packet buffer takes payloads up to `PKT_MAX_2K` (128) and the stack (`STACK_SIZE`) moves into its top half, under the parser state, so the store runs up to the stream area (`STORE_TOP_2K`); on the larger chips the buffer and stack are as in the full build. `ram_probe` leaves its choices in `STACK_INIT` and `PKT_MAX`, and every reset of SP loads `STACK_INIT`. `B4 '1'` reports the store and the frame limit, and the store's framing is `CHANNELS`×3+1 bytes. Timebase: the board interrupts 1302 times a second, so `TICK6_DIV` is 1 (the tick service runs on every interrupt), a display tick is one interrupt, the handler sets both marks with no dividers to count, and the IR decoder is left out. Serial is 300 baud only: `BAUD_STEP` is 30, so `BAUD_T` keeps its units (fifths of a sixth of an interrupt), and a frame's `B1` is not timed for its rate (the receiver's pulse-timing phase and the rate arithmetic are left out). Speed: patch 26's stretch would land in whole interrupts on some rows and not others, so slower speeds add `SCROLL_SPEED` dark ticks after each frame, held frames included, as stock does (`row_output`); every row keeps its speed-0 lit times and the two passes their ratio, at about a quarter less light at speed 7. Brightness is off or full: the single pass is lit for less than one interrupt and cannot be cut, and leaving it dark loses the dim shades and turns orange red and lime green, so low and medium show full and the dimming code (`latch_dim`, the ISR's lit count) is left out. `TWINKLE_DOTS` is 24, what a four-frame tick has time for at 4 MHz with the display output taking a large share of the CPU. `B5` ends the frame unprocessed. `09` takes a channel as one digit or two, in both builds: the second digit is taken only if it is a digit and the pair is a channel. In LITE `04` takes one digit per channel, and the editor asks again for a number past the last channel. Everything else carries over: the wired keypad and its editor, packets, status reports, the configuration block, the effects and the mains clock. Gone: the IR remote, the DC clock board, 600 and 1200 baud, and OTA. The 3A's weak power-fail deselect is not addressed; `store_repair` re-sequences the markers at boot as on every build. `cc784.py --lite` sends one-digit channels and splits long messages to the frame limit `B4 '1'` reports. Gate: `lite`, which re-runs itself with `CC784_LITE=1`; besides the board checks it measures speed as dark interrupts (crawled and held frames, every row lit the same at any speed) and brightness as off or full only; `ram` under it covers 2 K, 8 K and 16 K. The variable runs any gate on a 4 MHz, 1302 Hz, 2 K model, where `eeprom` passes and the others fail in checks written for the full build: its timing, the remote, 1200 baud, the DC board and the higher channels.

### 52. 2560 baud: three interrupts a bit

*+35 bytes*

Patch 30's rates divide the 300-baud bit by a step, so a bit lasts a fractional number of interrupts (6.4 at 1200, 3.2 at 2400) and each sample snaps to the nearest interrupt. At 2560 the bit is exactly three interrupts: `BAUD_STEP_2560` is 40 and `baud_bit` returns 120 in place of `BAUD_T` for the receiver and the transmitter, so every sample of a byte falls at the same point of its bit, within a sixth of a bit of its middle. A first start pulse of 1 to 4 interrupts after a second of silence selects it. The rate ignores the calibration and needs no NMI: it holds while the interrupt period is within about 0.5 percent of 130.2 µs, which the boards measured so far meet. Three interrupts leave a third of a bit of margin, so the rate depends on the interrupt running on time: a build with a longer interrupt, whose remote decoder ran during bytes, lost about 6 percent of 220-byte frames on the signs to samples that came one to three interrupts late in the middle of a byte, something the emulator does not reproduce.

Three changes to the receiver apply to every rate. It reads the line from the sample `int_timer` takes on entry (kept in E), not from an `IN` of its own some 300 cycles later, which put every sample 0.2 interrupt late against the start edge's timing. `rx_rate` rounds the first pulse from its estimated end, half an interrupt before the measuring interrupt, so a start pulse the line has stretched no longer counts as two bits (a `B1` read as `B0`). A middle exactly half an interrupt away is sampled at once rather than an interrupt later, since late interrupts would only add to that delay. The remote decoder does not run while serial bytes arrive (`IR_MASK` 0, from a start bit to the next frame end): on the board it costs the receiver late samples. A remote key pressed during a transfer is lost. Gate: `baud`, with 2560 from cold, at interrupt periods 0.5 percent either side, on a DC supply, and on a line whose spaces run 60 µs long or short with 20 µs of jitter (the emulator's `rx_skew_us` and `rx_jitter_us`); `update 2560` and `push 2560`. `cc784.py` and `cc784_ota.py` take `-b 2560`.

### 53. SCROLL RIGHT

*+246 bytes*

`B2 0F` is the variant of the RIGHT wipe: the staged page slides in from the left one column a frame, pushing the panel's page off to the right, then rests and holds as the wipes do; TWINKLE and GLIMMER may follow it. `fx_right` takes the same `ALT_FX` switch as UP and DOWN (effect 4 + 4 = 8), and `attr_rainbow`'s look past a `B2` sets `ALT_FX` for a `0F` too. `scroll_right` shares `fxv_scroll`'s first steps (the panel's page unrolled into `GLYPH_BUF`), widens `TXBUF` in place to the whole incoming frame, and builds step k from the new page's last k columns and the old page's first `FRAME_COLS`−k. Each step is built in the hidden half of the column ring and flipped in just after a frame end, with its row color, so all seven rows move together: built in the shown half after row 6 came up, the top row, which goes out last, ran a step ahead of the rest. Text moving sideways can show its colors, so `glyph_stage` stages this effect's page in them (a space with only its background, as the crawl draws it), and the page it pushes out may be a crawl in its colors. The last step is the page at rest: it is built yellow, row color too (`fb_colors_range`, HALT's loop), as every page that stands still, and the staged copy the holds use turns yellow with it. Both pages start in the row color the panel had: it waits just below `TXBUF`, goes into the unlit column where the two pages meet, so the old page keeps its starting color, and ends the backward scan that finds the color in force at the new page's left edge, which each step puts in `ROW_COLOR`. At the end the page goes back to the front half and `TXBUF` back to its staged form, so the holds and the next crawl find what they expect. In the editor: FUNC2 + SHIFT + BEEP (SHIFT + BEEP is RIGHT); labels `S-RIGHT`, and the wipe's becomes `W-RIGHT`. `cc784.py`: `@{scroll right}`. Gate: `scroll`, which checks every step against the two pages after a colored crawl, the colored slide and the yellow rest, and that no page or row color changes while a frame goes out.

### 54. Fields: one channel shown inside another

*+308 bytes, 5 of RAM; not in LITE*

`B2 '0'`–`B2 '9'` in a message renders channel 90–99 where it stands, in the font in force, so a value such as a temperature changes with a load of that channel and the message around it stays put. `attr_rainbow`'s look past a `B2` sends a digit to `field_open`, which saves the position after the digit in `FIELD_RET`, finds the channel's marker by scanning back from `STORE_END` (90–99 sit at the store's end) into `FIELD_MARK`, and moves the cursor to its text. The field's `03` dispatches to `field_close`, which puts the cursor back on `FIELD_RET` and goes on; with no field open it is the channel's end as before, so a field's end sends no status report and steps no sequence. A `B2` digit inside a field renders nothing, so a field cannot reach itself. A packet processed while a field is drawn sees the parent's position: `field_park` swaps it into `STORE_CURSOR` at entry, so the usual keep, shift or restart applies to the parent, and `field_resume` brings the field back at the end: as it was for an edit past its position, moved for an edit below its channel, and closed, the parent going on, for a load into the field itself. `init_render` clears `FIELD_RET`. `04 'M'` is a sequence of the message channels, 00–89: `cmd_04_sequence` lays the default list and ends it after 89; `04 'A'` stays 00–99. In the editor, `M` at SEQ MSG does the same as `A` with that list (`seq_list_messages`, code `9B` from `menu_ask_chan`). FUNC + PROG then a digit inserts a field the way SPEED takes its digit: FUNC turns PROG into `KEY_FIELD` (`D1`, a marker byte no key produces), which sets `FIELD_PENDING` and shows `FIELD` on the status line; `apply_field_prefix` turns the next digit into `B2` and the digit through `ALT_NEXT`, and any other key cancels. The editor shows a field as `<F0>`–`<F9>`, as it shows a speed as `<S0>`–`<S7>`. Stock and older patched firmware skip a `B2` they don't know and render the digit. `cc784.py`: `@{field 3}`, `field 3 TEXT` (a load into channel 93 with no display command), `seq m`; `cc784_lint.py --field 3=TEXT` measures pages with a field's value. The dongle config's `set_field` action loads a field from Home Assistant. Gate: `field`.

### 55. A degree sign

*+2 bytes*

`9F` draws glyph 175, which was a one-column placeholder: no key types `9F` and `char_to_glyph` gives the same glyph to `D0`, a store marker that never reaches the renderer. It is now a 3-column ring in the top rows, and `CHAR_FLAGS` marks `9F` printable: as an invalid byte, `store_repair` turned it into `?` at every display restart. `cc784.py` sends `°` as `9F` (`@{degree}` too), and the dongle's `set_field` turns UTF-8 `°` into it, so Home Assistant can send `72°F`. Gate: `field`.

### 56. FUNC + D types the degree sign

*+4 bytes*

`FUNC_TABLE` turns D into `9F`. The editor had used `9F` as the code of a second SHIFT press, which it discards, so that code is now `KEY_UNSHIFT` (`D2`, a marker byte no key produces), and `redraw_high` classes `9F` as a character, so the editor shows the glyph. Gate: `field`.

### 57. FLUSH

*+48 bytes; LITE +60, its editor gaining the `B2` check*

`B2 20` pushes the crawl's text off the panel where it stands, as the end of a message does, so the next text starts on an empty panel without a run of spaces. `attr_rainbow`'s look past a `B2` sends a space to `rainbow_alt_flush`, which runs `scroll_off_text` (14 spaces in the normal font) and puts the font in force back after it. On a staged page it does nothing: the page is shown whole. In the editor: FUNC + SPACE (`func_store` makes a FUNC space `B2 20`), label `FLUSH`. Older patched firmware skips the `B2` and shows one space. `cc784.py`: `@{flush}`; `cc784_lint.py` flags spaces before it, one on a staged page or at the end, and suggests it for six spaces or more in the crawl. The built-in demo starts with `COLOR` in italic, one color per letter, then MAGIC `CELLS` and the model name in a twinkling SCROLL UP. Gate: `flush`.

## 3. Rejected

- **Always defer processing** (proposed for B3) — *regression on the stock structure*; patch 21 polls from the render loop instead. `main_loop` tests `PKT_READY` only on entry; the `render_loop` render loop never falls back to it. Re-entry happens only via `fx_end_of_channel` or the `BA` wait-for-key spin (`wait_poll`), so a deferred packet waits for the current channel to finish — potentially many seconds after its ACK, during which `rx_idle_byte` refuses every further `B1`. Immediate mode is what makes NETCC responsive. Patch 21 removes the hazard: packets are processed from the render loop, not inside `tick6_service`.
- **Send ACK after processing** (proposed for B4) — *regression*. Zero-length frames are ACKed in `pkt_st_cksum` but never set `PKT_READY`, so they would lose their ACK entirely; and a valid ACK would be delayed by the whole insert, which is exactly the interval the sender is trying to measure. B8 shrinks the window a sender must pad after each ACK by one to three orders of magnitude, and patch 16's DONE byte replaces the padding with a real handshake.

## 4. Verified on the sign

| Patch | Seen on the sign |
|---|---|
| 1 | ten immediate-mode `B4 '0'` queries in a row, all byte-identical, and a following `B4 '1'` unchanged; stock garbles the replies and corrupts `SEQ_LIST` |
| 2 | the clock keeps running after `raw 17 32` (the hour tens digit changes to 2, which is the command's doing, not the patch's) |
| 3 | emulation only: the cursor case needs a hand-built store state |
| 4 | the sign ACKs at address 1 from cold with no battery |
| 5 | messages into channels 0, 42 and 99, then `B4 '3'`: all intact |
| 6 | cold boot shows the demo at address 1 with an empty store |
| 7, 8 | `B4 '1'` reports the 6264's store size (§1); the store filled to the last byte in 250-byte chunks dumps back intact; a message alternating BOLD, TINY (45 characters), NORMAL, TINY, ITALIC, BIG and TINY (30 characters) renders cleanly |
| 9 | nothing to see: dead code removed, behavior unchanged by `compare` |
| 10, 11 | OTA pushes over the ESPHome bridge: identical image, one-page, ~100-page and interrupted-then-resumed updates, all booted and confirmed; the store survives every reboot |
| 12 | OTA replies carrying `00` bytes arrive complete |
| 13 | `B4 '1'` reports the 62256's store size (§1) |
| 14 | the update display stays put while pages carrying `20` arrive |
| 15 | APPEND `"XYZW"` into an empty channel stores all four bytes |
| 16 | the host tools run frame after frame on the DONE byte |
| 17 | emulation only (`compare`): the editor's labels are a repack, not a change |
| 18 | a `--trial` push boots the new bank as TRIED and leaves it unconfirmed; a power cycle comes back on the GOOD bank with the trial skipped; `confirm` makes a trial GOOD; `rollback` reboots into the other bank with nothing transferred |
| 19 | a RAINBOW message starts on a different color each cycle |
| 20 | the clock set from the PC survives a power cycle |
| 21 | messages into other channels, queries and a store dump mid-scroll: the text keeps scrolling with a pause of a few frames, no blank, no restart; a DONE follows each addressed frame's reply |
| 22 | nothing to see: the typed-query path had no effect on the display |
| 23 | `time` from the PC: the sign's minute changes within a second of the PC's |
| 24 | after a bare CLEAR_ALL, text sent with no CHANNEL command lands in channel 0 and plays |
| 25 | replacing the playing channel restarts the display visibly faster; the dark second is gone |
| 26 | red, orange, yellow, lime and green at speeds 1 to 7: the same brightness and hue at every speed, motion as stock |
| 57 | on all four signs: FLUSH after `COLOR CELLS` pushes the crawl off before the SCROLL UP; FUNC + SPACE inserts it in the editor, labeled `FLUSH`; the built-in demo plays with every channel empty |
| 56 | on all four signs: FUNC + D types the degree sign in the editor, shown as the ring; SHIFT pressed twice still turns it on and off |
| 55 | on all four signs: `72°F` set from Home Assistant through `set_field` and `68°F` typed in a message show the degree ring in a crawl and an UP wipe, and survive a load into the playing channel (a display restart) |
| 54 | on all four signs: a message showing channels 90 and 91 in a crawl, a SCROLL RIGHT and an UP wipe; the fields set from Home Assistant with the dongle's `set_field` action and shown in the next pass; in the editor, fields shown as `<F0>`/`<F1>`, FUNC PROG and a digit inserting one, DEL removing it whole, SEQ then M giving 00–89 |
| 53 | on all four signs: SCROLL RIGHT slides the page in from the left with every row in step, in the colors set after `B2 0F`, turns yellow as it stops, and TWINKLE and GLIMMER hold it in yellow; a colored crawl pushed out keeps its colors |
| 52 | on all four signs at 2560: fifty 220-byte loads and thirty stats queries each, none rejected and every reply whole, then five loads at 1200; 280 more loads on one sign with none rejected; on two signs, forty loads each at full brightness and at low brightness with status reports on, and forty more on one sign with the remote pressed throughout, none rejected; a 10 K store loaded in 40 frames and dumped back whole at the line's 231 bytes a second; an OTA push of all 246 pages in 96 s |
| 50 | on all four signs: GLIMMER after PAUSE, the three wipes, HOLD and both scrolls; stripes roll and slant both ways, 3 frames a step, a 3-row band after trying 2 rows on the NET |
| 49 | on all four signs: TWINKLE after PAUSE, the three wipes, HOLD and both scrolls; 80 spots at 4 frames a tick, spread over the whole page, no stray lit rows |
| 48 | on all four signs: SCROLL UP and SCROLL DOWN push the page out row by row, as smooth as the wipes; the editor's `S-UP`/`S-DOWN` and `W-UP`/`W-DOWN` labels |
| 47 | on all four signs: cancelled FUNCs leave no stray characters; FUNC + C types a comma |
| 46 | on all four signs: RANDBOW in the editor (SHIFT, FUNC, SHIFT, COLOR), its label, LEFT and RIGHT passing it in one step |
| 45 | on the NET at 1200 baud: `stop` opens the editor, keys typed two seconds apart echo intact, a load meanwhile is answered BUSY, `start` closes the editor and the next load is ACKed |
| 44 | on the NIR, room quiet: twenty keys in the editor, 129 frames decoded, 0 dropped, no key needed a second press; with a television on in the room the set's bursts cost one frame in five and up to forty leader-like bursts a round, and the keys still registered first time; an hour of direct sunlight on all four signs, remote untouched: two to seven bursts per sign taken for a leader and dropped at the start check, nothing decoded |
| 43 | emulation (`update`); OTA pushes to all four signs complete with it |
| 42 | on the NET, a 3.7 K load (15 frames at 1200 baud) during a crawl: three barely visible bumps in 40 s |
| 41 | on the NET: reports for channel 0 (flagged as the wrap) and channel 1, then channel 2 after a load; `stats` queries and a message load work with reports on |
| 40 | on all four signs: clock source (mains on AC, the crystal confirmed on DC by the running clock), boot count 2 after an OTA reboot, stack headroom 96–104 of 128, no merged ticks, three stalls per boot and none per sequence loop; the remote's noise frames count from 0 to over 100 in a few minutes depending on the room |
| 39 | on all signs: the sequence plays as before; the step over 99 empty channels measures about 50 ms (patch 40's stall counter) |
| 38 | on all three signs: the MAGIC announcement, the effects and the editor prompts as before; the tour message, ending in the sixteen built-in graphics, plays through; the remote works |
| 37 | on the CC710's converted board: a message scrolls on the 59-column panel; `id`, `mem`, `timing` (128 fifths, NMI seen) and `config` answer at 1200 baud; OTA `info` reads both trailers and a page comparison of the idle bank finds nothing to send; the shortened editor prompts show whole with their digits, `INVALID` included, and `MAGIC nn` announces a new message |
| 36 | on both signs with the '244 mod: the remote on bit 4 opens the editor and types; OTA and 1200-baud queries as before; a CC100 keypad on an IDC-to-DB9 adapter types every key, and the sign hot-swaps between it and the serial dongle |
| 35 | on both signs: low and medium brightness steady, with no color shift; OTA `I` and `C` while dimmed |
| 34 | nothing to see: both signs boot and run as before |
| 33 | nothing to see: both signs boot and run as before, OTA pushes, queries, clocks and scrolling unchanged |
| 32 | `time24` on one sign and `time` on the other: "17:21 TODAY" against "5:22 PM TODAY", one space each |
| 31 | on both signs with the add-in board: on AC the mains passes through its selector and the calibration matches a sign without the board (300-baud bit 128, count low byte within 3, NMI seen); on 12 V DC the crystal takes over with the same calibration, 1200-baud serial works, and a full OTA push (33 pages, verify, trial reboot, confirm) ran on the crystal NMI on both signs |
| 30 | `timing` reports the calibrated 300-baud bit as 128 fifths, a 130.2 µs interrupt, on both signs; `mem` at 300 and 1200 in any order; five 220-byte loads at 1200 all accepted; a 542-byte dump at 1200 intact; OTA pushes at 1200 in 3 minutes against 12 at 300, on both signs. At 2400 queries and dumps pass, but three or four of five 220-byte loads are rejected |
| 29 | nothing to see once booted; OTA pushes park the display on the update message through the kept test-mode path |
| 28 | rainbow messages run forward on some cycles and in reverse on others |
| 27 | with the demo playing: `time`, then STOP and typed keys on the remote: nothing inserted, no crash, the demo resumes on the second STOP; text into channel 5 stops the demo; `seq 2` (empty) brings the demo back at once and `seq 5` the text; `mem` replies intact; a 240-byte load ACKs and DONEs at wire speed |


## 5. Rebuilding and testing

```
(cd src/patched && sjasmplus cc784nir.asm) # -> cc784nir_patched.bin
uv run tools/cc784_ota.py pack src/patched/cc784nir_patched.bin \
    -o src/patched/cc784nir_bank.bin --t48 src/patched/cc784nir_chip.bin
```

Or the `Build patched ROM` and `Pack OTA image` tasks. The LITE builds are `sjasmplus -DLITE cc784nir.asm` and `sjasmplus -DLITE -DCC710 cc784nir.asm` (`cc784lite.bin`, `cc710lite.bin`): 16 K images for a 27128, burned as they are, never packed; a 27C256 in a `CC784-3A` socket reads its upper half, so it takes the image twice (task `Build LITE ROM (27C256)`). The CC710 build is `sjasmplus -DCC710 cc784nir.asm` (`cc710_patched.bin`, packed to `cc710_bank.bin` and `cc710_chip.bin`), or the tasks of the same names with `(CC710)` appended. The raw build has empty trailers and must not be burned: `cc784nir_chip.bin` is what the T48 burns (task `AT28C256-15PU -- program`) and `cc784nir_bank.bin` what `cc784_ota.py push` sends.

Before any push, run the emulator regression set in [OTA.md §6](OTA.md#6-testing), plus `fuzz` for changes to the stub or the page writer. The emulator itself is described in [FIRMWARE.md §12](FIRMWARE.md#12-rebuilding).

## 6. Size refactor after `patched-v39`

From the tag `patched-v39` on, the source is organized for size rather than for a small diff against stock. What a reader of the source needs to know:

- **Font:** glyphs are stored at their own widths. `FONT_WIDTH` holds each glyph's width and `FONT_BLOCK` the address of every eighth glyph; `glyph_addr` adds up to seven widths and sets `GLYPH_WIDTH`. `glyph_lookup` always copies the glyph into a buffer before styling, since bold and BIG read one column past the end.
- **Character classes:** `CHAR_FLAGS` is two bits per character (64 bytes) behind `char_flags`, which returns Z for printable text and CY for an invalid byte.
- **Keys and labels:** the two upper-case charset tables are gone; `getkey_lookup` folds a–z up when exactly one of SHIFT and CAPS is on. The editor's labels are one keyed list, `LABELS`, searched by `redraw_show_label`; the closing bracket is drawn after any of them from `STR_CLOSE`.
- **Dispatch:** `CALL dispatch` followed by a table of `DKEY key, target` entries replaces the CP/JP ladders in the editor, the packet loop, the effects and the channel prompt. sjasmplus substitutes macro parameter names inside identifiers, hence the parameter names `zk`/`zt`.
- **RAM:** see the map in §1. Every byte below `MSG_STORE` or in the stream area is a byte of store on a 2 K chip, so a few variables do double duty: `ROW_PORT` is 0 once a row has had both passes, `SPARKLE_RND` shares the channel prompt's two digits (a hold seeds it when it starts; the prompt writes both digits before reading them, and the editor ends any hold), and the clock digit drawn comes from `CLK_RENDER_STEP`. A variable that must survive a reset sits outside `BOOT_ZERO`. Moving one of those (`SEQ_LIST`, the clock, the store limits, the configuration block) means the first boot after an OTA update reads it from its old address: the boot checks put defaults back where they can, otherwise the value is lost.
- **Short jumps:** beyond patch 33, far jumps reach their targets through an existing unconditional `JP` to the same target within range, labelled `<target>_jrN`.
- **Interrupt handler:** the idle path of `int_timer` falls straight through, about 200 cycles of the 1024 between interrupts; the serial engines and the display-tick arithmetic sit out of line (`int_rx_start`, `int_rx_active`, `int_disp_due`). In LITE every interrupt is both a display tick and a tick6 mark, so that path has no dividers: it sets both marks and starts the service. One test opens it: `ISR_WORK` has a bit for a byte arriving, a byte going out, a dimmed row waiting or lit, and keypad mode, and the port sample's RX bit is XORed into it, so with the line at its idle level and no bit set the receiver, transmitter and brightness tests are skipped. The bits are set where the work starts (`rx_start`, `tx_try_queue`, `tx_start_byte`, `lit_arm`) and cleared where it ends, in the ISR; the tests behind it are unchanged, so a bit left set costs time only. A dimmed row alone goes straight to the brightness count (`int_lit_only`). Keypad mode's bit makes space the idle level, and entering keypad mode stops the receiver timing the start pulse that never ends, so a sign with a keypad or nothing on the port takes the short path too. `TICK6_COUNT` counts down, and only an interrupt that marks a tick looks whether the service has to be started, since a mark is otherwise only ever pending while the service runs. The remote's gate is one AND and XOR: `IR_MASK` is `PORT_IR`, and `rx_start` zeroes it and `IR_QUIET` until the next frame end, which is patch 52's pause while serial bytes arrive. The handler ends in `RET`: no Z80 peripheral watches for `RETI`.
- **Flags through the effects:** `render_loop` tests the zero flag `crawl_step` returns, which comes out of `fx_done` through `fx_reset_stage` and `clear_txbuf`. Every path there returns Z, and nothing on it may disturb the flags: a page too wide for the panel otherwise starts another page with the leftover text instead of crawling it.
- **The column ring** lies in one page with a low byte of 0 at its start (both asserted), so `fb_ptr_inc`, `frame_scroll`, `frame_set_window` and the crawl's lead work on the low byte alone, and the window's two lengths are bytes; `fb_rewind_window` takes one 16-bit add. `fb_rewind_window` stores `FB_COL` once: a frame end between two stores would read the window color from an address outside the ring.
- **Shared pieces:** `mem_fill` behind the three clears and HOLD's fill; `glyph_widen` for bold and BIG; `copy_cols` for every staged-page copy (it sits under `twinkle_page` because the emulator's sparkle gates tell the page copy from the hold's writes by code address); `store_fill` for the empty channels of CLR ALL and the store repair; `fx_show`, `menu_msg`, `mark_digit`, `prefix_apply` and the status line's `STATUS_FLAGS` table. Index registers remain only in `pkt_next_byte` with `cmd_09_channel`, `fxv_scroll` and `ota_crc`.
- **Rejected:** a single-entry IR decoder (63 bytes smaller) took about 235 cycles per interrupt against about 90, so the next interrupt nested inside it and keys were lost. Per-interrupt handlers stay short.

Verification for changes of this kind: the full emulator set ([OTA.md §6](OTA.md#6-testing)); `compare` is only meaningful in its boot and `B4` phases, because the effects, editor and MAGIC phases diverge between any two builds of different speed. For the editor, compare the steady panel frame after each remote key between the two builds instead; `tools/cc784_ab.py` does that, and compares rendered messages by frame, serial replies and the store repair, on builds whose RAM map and store size may differ. Two things it cannot tell apart from a change: a message that loops is matched by longest run, so one torn frame can pair a pass with the next one and report the rest as differences (compare the two streams' sets of frames before believing it), and a wipe's or scroll's torn frames fall where the main loop's speed puts them. A timing check that samples the latch (`lite`'s row times, `baud`, `keypad`) runs the emulator at 16-cycle slices: at the default 128 an interrupt waits for the slice's end, and a handler shorter by a slice shifts what is sampled.
