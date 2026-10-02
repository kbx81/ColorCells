# CC784NIR patched firmware

`src/patched/cc784nir.asm`, on the `wip` branch, is the stock reconstruction
plus the patches below. `diff src/stock/cc784nir.asm src/patched/cc784nir.asm`
is the authoritative changelog: everything outside the patches is kept
identical on purpose. The source is fully relocatable (every ROM address is a
label), so code is inserted freely and patched addresses differ from stock
above `144A`.

What the stock firmware does, and the bugs these patches fix, are in
`CC784_firmware.md`; the over-the-air update mechanism the patched build
carries is in `CC784_ota.md`; fitting the chips it needs is in `AT28C256.md`.

---

## 1. Memory map

RAM, with the chip-size detection of patch 13:

| Range | Use |
|---|---|
| `4000–40BF` | `FRAMEBUF` — 192-byte column ring (stock: 344 from `4040`); also where the OTA RAM library runs |
| `40C0–42C1` | pointers, `TXBUF`, variables — stock order, 72 dead bytes removed |
| `42C2–7E6F` | `MSG_STORE`, **15278 bytes** with a 62256; `42C2–5E6F`, **7086**, with the stock 6264 |
| `7E70–7EEF` | **stack**, 128 bytes (`STACK_SIZE`); `5E70` on the 6264, which mirrors `6000–7FFF` onto `4000–5FFF` |
| `7EF0–7FFB` | packet flag, buffer and parser state |
| `7FFC–7FFF` | boot stub: `NMI_VEC`, `NMI_MAGIC`, `ROM_BANK` |
| `C000` | `BANK_REG`, the added '273 (write-only; bit 0 = EEPROM A14) |

ROM: `0000–01FF` boot stub, `0200` jump table, `0209` `ROM_ID` (stock `0048`),
application to `3FBF`, trailer page at `3FC0` (`CC784_ota.md` §2). About 260
bytes of the bank are free.

## 2. Patches

1. **Relocate the stack** (fixes B1). The stack is carved off the top of the
   message store instead of the 64 bytes below `4000`: 128 bytes
   (`STACK_SIZE`; the measurements are in `CC784_firmware.md` §2).
   All seven `LD SP` sites use the symbol (reset, `fx_end_of_channel`,
   `menu_enter`, `key_handler`, the editor, `pkt_process`,
   `pkt_process_done`). The store's ceiling and the constants `store_init`
   derives from it move down together, and `store_init` writes the `0xDA`
   store terminator through `STORE_LIMIT` before zeroing the packet page,
   since the terminator does not sit inside that page.
2. **Restore the clock** (fixes B2). `pkt_process_done` sets `CLK_RUN=FF`
   inline, just before its `CALL shift_chain_clear`. This covers every early
   exit, not just `cmd_17`'s.
   `cmd_17_set_time` itself cannot be fixed in place: `pkt_next_byte` reads the
   caller's stack frame (`POP IX/DE/IY`), so no helper can be interposed.
3. **Fix the cursor store** (fixes B6). `32` → `22` at `2B1F`.
4. **Default address 1 + valid complement** (fixes B5 and B7).
   `LD A,0 / LD (MY_ADDRESS),A / LD (…INV),A` → `LD HL,FE01 /
   LD (MY_ADDRESS),HL / NOP / NOP`. `MY_ADDRESS_INV` is `MY_ADDRESS+1`, so one
   16-bit store writes both, and `FE` is a genuine complement of `01`.
5. **Shift only the live store** (fixes B8). `LD HL,(STORE_LIMIT)` →
   `LD HL,(STORE_END)` at `2B3D` — a two-byte operand change.
6. **Sane defaults after RAM loss: clock at 12:00 AM, empty store, demo.**
   `init_vars` copies its RAM image from `CLK_RUN` up, so `CLK_H10`…`CLK_PM`
   (4200–4205) are left alone on purpose, to survive a battery-backed power
   cycle. Without a battery they are SRAM noise: `clock_tick` only tests for
   equality, so a garbage second count runs through 255 before wrapping, and
   `render_clock` shows digits 10–15 as `: ; < = > ?`. The message store is
   noise too, and `store_repair` faithfully tidies it into 100 channels of
   garbage that the default sequence then plays. The fix sits in the branch
   patch 4 already owns — the `MY_ADDRESS`/complement check fails exactly when
   RAM is fresh — and writes `1 2 0 0 0 0` to the six clock bytes (12:00,
   seconds 0, AM) and calls `store_clear_all`, so `init_sequence` sees every
   channel empty and runs the demo, exactly as after a CLR ALL. With a battery
   and valid RAM the branch is skipped, as before. The clock runs from midnight
   rather than waiting to be set.
7. **RAM re-layout: 7014-byte store** (+344 over patch 1's layout, +88 over
   stock). Three changes, each a constant:
   - `STACK_SIZE` 128, sized from the measured 70-byte high-water mark and
     the ~108-byte constructed worst case.
   - `FRAMEBUF_SIZE` 344 → 192. The column ring only ever holds the 86
     visible columns plus the glyph being written (at most 32 more; the
     renderer waits for the scroll to catch up before the next one) — the
     four-rows-of-86 size is not needed. TINY mode's output frame lives in
     `TXBUF`, which is idle while TINY text is displayed (effects are off,
     and a packet resets everything anyway); the TINY line buffer
     (`FRAMEBUF_TINY`, 189 bytes from the ring start) fits in the ring.
   - `FRAMEBUF` `4040` → `4000`: the stock stack slot is free once the stack
     has moved.
   `cc784_sim.py compare` shows the same frames and replies as the previous
   layout for every effect, the clock, TINY and the editor.
8. **Compact the variable block: 7086-byte store** (+72). Every byte of the
   block that nothing reads is gone: ten write-only variables together with
   the code that fed them, and the unnamed bytes between variables, including
   `INIT_DATA`'s misaligned second copies of `RX_TIMING` and
   `rx_st_wait_start`. The order is unchanged and `INIT_DATA` is regenerated
   as four runs matching the new positions. Three bytes that look dead are
   not and are kept: `NMI_COUNT+1` is the high byte of a pointer
   `magic_short_word` reads through, `MSG_STORE-1` takes a space from
   `store_repair` on every boot (`STORE_GUARD`), and the four bytes after
   `FB_COL` were what `tiny_scroll_off` scanned through a typo'd pointer,
   always finding a `0x95` constant, so TINY always pushed the display off
   first; the scan is gone and that behaviour kept. Verified by an emulator
   census (every RAM byte read or written across the suite, attributed to its
   symbol), a lockstep diff of every variable against patch 7, and
   `compare`/`stack`.
9. **Remove the unreachable code.** A static reachability walk over the
   assembled listing (roots: the three vectors plus every label loaded as a
   vector or stored as data) leaves five islands nothing can jump to:
   `keypad_scan` (47 bytes, not referenced at all), `menu_enter` (48 bytes —
   an "enter your address or
   `*`" gate that nothing enters; serial `01` goes to `key_handler`), and
   three orphans behind unconditional jumps (an extra `LD A,0x20` after
   `clock_emit`, a digit-decrement stub after `editor_key_bgrnd`, a stray
   `DJNZ/JP` after `cursor_left_8`). Also gone: the raw bytes the disassembly
   kept as `db` (an unreachable `JP render_loop`, a `RET`, a `JP`, the `AA 55`
   pair), the five `NOP`s (two of them patch 4's size padding), and
   `tick6_service`'s re-entrancy guard, which tested `(IX)==AA && (IY)==55`
   against registers nothing ever points there. About 140 bytes of ROM, zero
   behaviour: `compare` against patch 8 is clean. The walk also exposed the
   last raw code address in the source, `LD HL,0xC4` for `tick6_service` in
   `int_timer`, fixed in both trees.

10. **Boot stub, bank register and A/B layout** (`CC784_ota.md`). `0000–01FF`
    is a stub that picks a bank by trailer and CRC and runs its app through a
    jump table at `0200`; the `0066` NMI goes through a RAM vector guarded by
    `NMI_MAGIC`. `ROM_ID` sits in the app, and `query_0_romid` uses the
    label rather than a raw `0048`. Boot is ~1 s slower: the CRC pass.
11. **`B5` OTA command set** (`cmd_B5_ota`, `CC784_ota.md` §6): info, page
    CRCs, begin, write 1–3 pages, finish, reset. Runs the stub's RAM library
    from `FRAMEBUF`; pages below `0200` refused. ≈ 540 bytes of ROM.
12. **`tx_try_queue` reports busy with carry** (fixes B10).
13. **RAM at the top of the 16 K window; chip size detected at boot.** The
    board decodes RAM for all of `4000–7FFF`; the 6264 mirrors the upper half.
    Everything at a fixed address (stack, packet buffers, the stub's bytes)
    sits under `RAM_TOP` = `8000`, which the 6264 aliases to `5Exx/5Fxx`
    for free, and `store_init` writes a marker through the mirror to pick
    `STORE_TOP` (15278 bytes) or `STORE_TOP_8K` (7086). One build for both
    chips; a 62256 is two wires (`AT28C256.md`).

14. **Payload bytes are not keys** (fixes B12): `rx_consume` clears `RX_BYTE`
    after `pkt_feed_byte`. The OTA handler also blanks the panel before each
    reply (its RAM library sits in `FRAMEBUF`) and shows a parked UPDATING
    message from `B5 'B'` to the reboot through the factory test mode.
15. **`B3` seats like `0E`** (fixes B11): the extra step back onto an empty
    channel's marker is gone.

## 3. Rejected

- **Always defer processing** (proposed for B3) — *regression*. `main_loop`
  tests `PKT_READY` only on entry at `009A`; the `render_loop` render loop never
  falls back to it. Re-entry happens only via `fx_end_of_channel` (`0F5E`) or
  the `BA` wait-for-key spin (`0A49`), so a deferred packet waits for the
  current channel to finish — potentially many seconds after its ACK, during
  which `02DD` refuses every further `B1`. Immediate mode is what makes NETCC
  responsive. B3 stands as documented, but patch 1 removes its only known
  trigger: `pkt_process` resets SP on entry and `pkt_process_done` resets it
  again before jumping to `restart_display`, so the abandoned interrupt frame is
  harmless as long as the stack is large enough.
- **Send ACK after processing** (proposed for B4) — *regression*. Zero-length
  frames are ACKed in `pkt_st_cksum` but never set `PKT_READY`, so they would
  lose their ACK entirely; and a valid ACK would be delayed by the whole
  insert, which is exactly the interval the sender is trying to measure.
  Padding after each ACK remains the right mitigation. B8 shrinks the window
  it has to cover by one to three orders of magnitude — but see the
  completion byte below, which replaces the padding with a real handshake.

## 4. Proposed: a completion byte

Keep the ACK where it is and add a second reply, DONE, when processing has
finished: ACK = "received, processing", DONE = "you may send again". This is
the handshake B4 has always needed — the deaf window varies from 0.25 s to
0.75 s with the store and sequence, and today `cc784.py` guesses at it with a
fixed 1 s pause.

- **Where:** `pkt_process_done`, the single exit of every processed packet.
  TX is idle there (the ACK finished before `DI`; query replies finish inside
  their handlers), so a non-blocking `tx_try_queue` of the byte is enough —
  about ten bytes of ROM. The byte leaves on `restart_display`'s `EI`, i.e.
  the instant the sign is receptive again, and reaches the sender ~40 ms
  later regardless of how long the window was.
- **Opt-in, so NETCC is untouched:** the parser tests `PKT_FLAG == 80` for
  immediate mode; make it "bit 7 set" and let bit 0 request DONE. NETCC's
  `80` behaves exactly as today; `81` gets ACK, processing, DONE. NETCC's
  reader would otherwise find a stray byte after each ACK.
- **Rules:** DONE follows only an ACK that led to processing, i.e. addressed
  frames with `len > 0` (zero-length frames are ACKed and finished; broadcast
  frames get neither, so a multi-sign bus never has two talkers). NAK, or a
  parser error that resets, means no DONE — the sender times out and retries
  as now. A deferred frame (`01`) still gets its DONE when `main_loop` gets
  round to it, which makes the B9 wait visible instead of silent.
- **Value:** anything the sign never sends today — not `06`, `15` or `B1`.
  `04` (EOT) reads naturally.
- **Sender side:** `cc784.py` waits for DONE instead of sleeping; chunked
  messages then pipeline at wire speed with no guessed gaps.

## 5. Verified on the sign

- **B1** — ten immediate-mode `B4 '0'` queries in a row, all byte-identical,
  and a following `B4 '1'` unchanged. Stock garbles the replies and corrupts
  `SEQ_LIST`.
- **B2** — the clock keeps running after `raw 17 32`. (The hour tens digit
  does change: `cmd_17` stores `0x32 & 0x0F` before discovering the packet
  ended; a full `17` puts it right. That is the command, not the patch.)
- **B5/B7** — the sign ACKs at address 1 from cold with no battery.
- **B8** — messages into channels 0, 42 and 99, then `B4 '3'`: all intact.
- **Patches 7–8** — `B4 '1'` reports 7086 on the 6264; the store filled to
  the last byte in 250-byte chunks dumps back intact.
- **Patch 7** — a message alternating BOLD, TINY (45 characters), NORMAL,
  TINY, ITALIC, BIG and TINY (30 characters) renders cleanly; TINY's frame in
  `TXBUF` and its line buffer in the 192-byte ring hold up on the panel.
- **Patch 13** — `B4 '1'` reports 15278 on a 62256.
- **Patches 10–11** — OTA pushes over the ESPHome bridge: identical image,
  one-page, ~100-page and interrupted-then-resumed updates, all booted and
  confirmed; the store survives every reboot.
- **B11/B12** — `B3 "XYZW"` into an empty channel stores all four bytes;
  the update display stays put while pages carrying `20` arrive.
- **FLASH clock** — `FLASH_HALF_PERIOD` 13 → 7 blinks visibly faster (~5 Hz
  against ~2.4 Hz), which is what identified latch bit 7.

## 6. Rebuilding and testing

```
cd src/patched && sjasmplus cc784nir.asm   # -> cc784nir_patched.bin
uv run tools/cc784_ota.py pack src/patched/cc784nir_patched.bin \
    -o src/patched/cc784nir_bank.bin --t48 src/patched/cc784nir_chip.bin
```

Or the `Build patched ROM` and `Pack OTA image` tasks. The raw build has empty
trailers and must not be burned: `cc784nir_chip.bin` is what the T48 burns
(task `AT28C256-15PU -- program`) and `cc784nir_bank.bin` what
`cc784_ota.py push` sends.

Before any push, run the emulator regression set in `CC784_ota.md` §6, plus
`fuzz` for changes to the stub or the page writer. The emulator itself is
described in `CC784_firmware.md` §11.
