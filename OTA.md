# CC784NIR — over-the-air ROM updates

The patched firmware can be replaced over the sign's own serial link. The ROM is an AT28C256 EEPROM split into two 16 K banks; an update is written into the bank that is not running, verified there, and booted on the next reset, so a failed or interrupted update never touches the running code. Only the 64-byte pages that differ are sent.

What you need:

- the AT28C256 and the bank register fitted per [UPGRADES.md](UPGRADES.md)
- the patched firmware from `src/patched/`
- `tools/cc784_ota.py`
- a serial path to the sign: a USB adapter, or an [ESPHome serial proxy](https://esphome.io/components/serial_proxy/)

---

## 1. Hardware

The ROM is an AT28C256 with three pins rewired: `/WE` to the Z80's `/WR` (with a pull-up), `/OE` to `/RD` because the socket ties `/OE` to `/CE` and that inhibits writes, and A14 to a bank register. The register is an added 74LS273 piggybacked on U5, written at `0xC000`: bit 0 is the EEPROM's A14, bits 1–2 are reserved for A15/A16 of a larger chip, bit 7 selects the clock source (`BANK_CLOCK_XTAL`, patch 31), the rest spare. Wiring, continuity checks and the first power-up are in [UPGRADES.md §2](UPGRADES.md#2-eeprom-and-bank-register).

The register is separate from U5 because U5 is cleared by the board's watchdog whenever interrupts stop for 512 µs, which happens during every OTA command; a bank bit there would swap the ROM under the running code. The register's `/MR` is on the Z80's `/RESET`, so every reset, power-on included, starts in bank 0.

ROM `/CE` is gated by `/MREQ`, so only memory accesses to `0x0000–0x3FFF` reach the chip; I/O and refresh cycles never do.

## 2. ROM layout (each bank)

| Range | Content | Written by |
|---|---|---|
| `0000–023F` | boot stub: reset, `0038`, `0066`, bank choice, trial marking, `stub_lib` | T48 only |
| `0240–0248` | jump table: `JP app_start`, `JP int_timer`, `JP nmi_entry` | OTA |
| `0249–3FBF` | application | OTA |
| `3FC0–3FFF` | trailer page | OTA, written last |

**Trailer:** `+0` `"OTA1"`, `+4` sequence number, `+5` state (1 TRIAL, 2 TRIED, 3 GOOD), `+6` CRC-16 of `0240–3FBF`, `+8` CRC-16 of bytes `+0..+7`, rest `FF`. CRC-16/XMODEM (poly `1021`, init 0), little-endian words.

**Trial and confirm:** `F` writes a new image's trailer as TRIAL. The stub boots a TRIAL bank once, rewriting its trailer as TRIED first, and treats a TRIED trailer as invalid ever after. So a new image gets exactly one chance: if it answers, the host confirms it (`K`) and the trailer becomes GOOD; if it crashes, hangs or cannot talk, the next reset boots the other bank. A hung sign needs a power cycle to get there, since nothing on the board resets the CPU.

**Stub rule:** the stub never changes over the air. The `W` command refuses pages 0–8, `push` refuses an image whose stub pages differ from the sign's, and the stub references nothing in the application except the jump table, so application changes never alter its bytes. A stub change needs the T48.

**RAM used:** `7FFC–7FFF` (`NMI_VEC`, `NMI_MAGIC`, `ROM_BANK`) and `7FF0` (`NMI_SEEN`, set by every mains NMI since reset), which the stock 6264 mirrors from `5Fxx`. The page writer and the bank-touching routines run from `FRAMEBUF` (`4000`), which is idle while a packet is processed. The boot copy of the whole library is longer than `FRAMEBUF` and overwrites `RAM_VARS+00..81`, so nothing that must survive a reset may live there; an `ASSERT` in the source holds the line at `SEQ_LIST`. No message-store space is used.

## 3. Boot

1. `DI`, clear `NMI_MAGIC` (a mains NMI before the vector is set is ignored), `SP` = `7EF0`, copy `stub_lib` to `4000`. Everything that writes the bank register runs from that RAM copy, so the other bank's contents never execute during boot, whatever they are.
2. Validate both trailers (magic and trailer CRC).
3. Candidate order: newer sequence number first (signed 8-bit difference, ties to bank 0); if only one is valid, that one; if none, bank 0 without further checks (the state after a T48 burn of a raw build).
4. CRC the candidate's `0240–3FBF`; on mismatch try the other. About 1 s per pass at 8 MHz.
5. Select the bank and record it in `ROM_BANK`. If its trailer says TRIAL, rewrite it as TRIED (one page write). Point `NMI_VEC` at the jump table, jump to `0240`.

## 4. The OTA command

Sent inside the normal packet frame (`B1 addr 81 len payload cksum`), addressed; the OTA command byte (`B5`, `CMD_OTA`) must be the first payload byte and the command ends the packet. Replies are reply frames (`B1 addr len data cksum`) and go out after the work. With flag `81` a `04` DONE byte follows the reply; until then the sign parses any new frame but keeps nothing of it and never answers it, so the host waits for DONE, with a 1 s pause as the fallback for firmware that doesn't send one. OTA commands are the one kind of packet that still parks the display and restarts it afterwards: the page writer needs interrupts off.

| Payload | Reply |
|---|---|
| `B5 'I'` | `ROM_BANK`, the first 10 trailer bytes of bank 0 and of bank 1, then a features byte: bit 0 DONE handshake, bit 1 the mains NMI has fired since reset, bit 2 trial/confirm |
| `B5 'C' page n` | `n` CRC-16s of idle-bank pages starting at `page`, n ≤ 42 |
| `B5 'B'` | status; erases the idle bank's trailer and parks the display on `>FW ↑<` (`^` is the up-arrow glyph; it fits both panels) until the reboot |
| `B5 'W' page crc16 data` | status; writes 1–3 consecutive pages, `crc16` over the data, pages 0–8 (the stub) refused |
| `B5 'F' seq crc16` | status; CRCs the idle bank's `0240–3FBF`, and if it matches writes the trailer (TRIAL, `seq`) |
| `B5 'K' state seq` | status; rewrites the running bank's trailer with that state and sequence number: `K 3 seq` confirms, `K 3 other−1` makes the other bank boot next |
| `B5 'R'` | no reply; resets, which boots the newest valid bank |

**Status byte:**

| Value | Meaning |
|---|---|
| 0 | ok |
| 1 | verify failed: the page read back differs from what was written |
| 2 | chip timeout: the write cycle never finished |
| 3 | page out of range, or inside the stub |
| 4 | CRC mismatch on the data or the image |
| 5 | bad arguments |

**Page writes** (`lib_page_writer`, from RAM, interrupts off): wait for the mains NMI if one has ever fired (`NMI_SEEN`; on a DC supply there is nothing to collide with and the wait is skipped), send the SDP unlock sequence, select the target bank, load the 64 bytes, let the chip's 10 ms write cycle finish, read the page back. The NMI wait exists because the chip is unreadable, vectors included, during its write cycle, and the mains NMI cannot be masked; writing right after one guarantees the next is ~16 ms away. SDP (software data protection) is armed by the first write and stays armed, so stray writes to `0000–3FFF` are ignored by the chip.

## 5. Using it

**Build and pack** (`Build patched ROM` then `Pack OTA image`, or):

```
(cd src/patched && sjasmplus cc784nir.asm)
uv run tools/cc784_ota.py pack src/patched/cc784nir_patched.bin \
    -o src/patched/cc784nir_bank.bin --t48 src/patched/cc784nir_chip.bin
```

`cc784nir_bank.bin` is what `push` sends. `cc784nir_chip.bin` is what the T48 burns: the same application in both banks, sequence 1 and 0, so a fallback exists from the first power-up.

> [!WARNING]
> Never burn the raw build `cc784nir_patched.bin`: its trailers are empty, so the stub boots bank 0 unchecked with no fallback, and the first `push` finds no valid bank to compare against.

**Push:**

```
uv run tools/cc784_ota.py push src/patched/cc784nir_bank.bin -H <bridge> -k <key>   # ESPHome; -i N picks the serial_proxy instance when the bridge has several
uv run tools/cc784_ota.py push src/patched/cc784nir_bank.bin -H <bridge> -k <key> -b 1200   # a sign already on patch 30: 3 min instead of 12
uv run tools/cc784_ota.py push src/patched/cc784nir_bank.bin -p <port>              # serial
```

`push` reads both trailers (`I`, which also switches on the DONE handshake when the firmware offers it), CRCs every page of the idle bank (`C`, about 25 s), sends only the pages that differ (`B`, then `W` in runs of up to three pages, ~7 s per run), verifies the whole image on the sign and writes the trailer with the next sequence number (`F`), reboots (`R`), waits 8 s, checks that the new bank is running (`I`) and confirms it (`K`). `--trial` skips the confirmation: the new image runs, and a power cycle reverts it until you run `confirm`. `-n` stops after the comparison and reports the page count; `-s` forces a sequence number. If it fails after `B` it sends `R`, which boots the old bank because the idle trailer is erased.

**`confirm`** marks the running image GOOD. **`rollback`** gives the running bank a lower sequence number than the other and reboots: the previous image is back in ten seconds with nothing transferred, as long as the next push hasn't overwritten it yet. **`info`** shows both banks.

`--all` skips `C` and sends every page (about 12 min at 300 baud). Use it when the sign runs a build older than the `ota_copy` fix of patch 35: on those, a mains NMI during `C` runs the idle image's NMI handler (§8), which is harmless only while the two images agree on `nmi_entry` and the clock variables.

**What a push costs:** the diff is against the idle bank, which holds the image from *two* pushes ago, so a push carries the union of the last two changes. An inserted byte shifts everything after it, so a code edit early in the file is typically a 100-page push (~5 min); an edit in the data at the end of the bank is one page. An interrupted push can simply be run again: `C` finds the pages already written.

**`diff OLD.bin NEW.bin`** prints the pages two images differ in and the transfer time.

## 6. Testing

Everything above is modeled in `tools/cc784_sim.py` (AT28C256 with banks, page timing, SDP and the watchdog). Before pushing a firmware change, run:

| Command | Proves |
|---|---|
| `uv run tools/cc784_sim.py stack patched` | replies unchanged, no stack growth, no EEPROM faults |
| `uv run tools/cc784_sim.py compare OLD_TREE src/patched` | same panel frames and replies as the previous source tree |
| `uv run tools/cc784_sim.py eeprom` | the chip model against the datasheet rules |
| `uv run tools/cc784_sim.py ota` | the stub's bank choice in every trailer scenario, and the page writer |
| `uv run tools/cc784_sim.py update` | a whole OTA update over the fake serial line, including refusals; STOP, a serial `01` and `B7 '1'` mid-update open no editor (patches 43 and 45) |
| `uv run tools/cc784_sim.py push` | the real `push()` against the emulator |
| `uv run tools/cc784_sim.py ram` | the build on the 6264 and on a 62256: sizes, fill, dump; a set clock survives a reset |
| `uv run tools/cc784_sim.py quiet` | packets arriving mid-scroll: no restart, no watchdog clear, replies and DONE in the background, early frames dropped whole, cursor fix-up; the demo's lock survives a packet and a SEQ change is acted on |
| `uv run tools/cc784_sim.py speed` | each scroll speed steps columns at stock's rate with no dark frames, and the seven rows get the same dwell |
| `uv run tools/cc784_sim.py config` | the configuration block (patch 35): defaults after a RAM loss, kept across a reset, defaults again on a bad sum; the protected bytes refuse writes and the flags byte keeps its live bit; brightness is lit time (duty one third and two thirds with both passes still sent), mute darkens now or at the next message, hold and flash follow their bytes, the beeper and the remote switch off, the editor's address dialog reseals |
| `uv run tools/cc784_sim.py clock` | the NMI source: mains on AC, the add-in board's 64 Hz on DC, neither on a bare DC supply, with the clock, the calibration and an OTA page write in each; 12 and 24-hour rollovers |
| `uv run tools/cc784_sim.py keypad` | the wired keypad (patch 36): serial at boot, keypad mode once the line reads space, keys with contact bounce editing exactly as the same keys on the remote, a held key repeating, the remote working alongside, serial again as soon as a host idles on the line |
| `uv run tools/cc784_sim.py seq` | the sequence (patch 39): with one message under the default 0–99 sequence the empty channels take under 100 ms per loop; channels 0, 7, 50 and 99 play in order, also after a lower channel grows and after one is emptied; a hint planted past the `DA` on a stale marker is ignored |
| `uv run tools/cc784_sim.py stats` | the health counters (patch 40): clock source on AC and on DC with the board, a boot count of 1 after fresh RAM and 2 after a reset with RAM kept, uptime against the emulator's clock, stack headroom, good and bad frames, remote frames |
| `uv run tools/cc784_sim.py status` | status reports (patch 41): none while off; one per channel start when on, the wrap flagged; `FF` when the editor opens; `stats` queries and a long load through `cc784.py` with reports flowing |
| `uv run tools/cc784_sim.py baud` | a cold sign follows the host at 300, 600, 1200 and 2560; replies come back at that rate; a rate change after a pause is followed; 1200 holds over interrupt periods from 126 to 134 µs thanks to the calibration and on a DC supply; 2560 holds within 0.5 % of the period, on a DC supply and on a skewed, jittered line; 300-baud bare bytes still work. `update 1200` and `push 1200` run those gates at a rate |
| `uv run tools/cc784_sim.py fuzz [N]` | N power cuts at random instants of an update; every reboot must land in a verified bank |

The `OTA: emulator regression` task runs `eeprom`, `ota`, `update`, `push`, `ram`, `quiet`, `speed`, `baud`, `clock`, `config`, `keypad` and `seq`.

## 7. Not built

- **Layout pinning** (`ALIGN 64` slack between modules, fixed `ORG`s for the tables) so that small code edits stay small pushes. The free space is the `FF` run before the trailer ([patched notes §1](PATCHED.md#1-memory-map)).

## 8. Gotchas

### Fitting and using

- **RAM A13 (62256 pin 26) must be wired.** Floating, the boot hangs within a millisecond: the stub runs from RAM.
- **The '273 stack's ground joint.** A weak one leaves Q0 floating; the EEPROM reads garbage and the sign never boots. Symptom: it boots with EEPROM pin 1 strapped to ground.
- **Burn with `-u -P`.** `-u` only disables protection before writing; `-P` re-enables it. The task does both. With `/WE` on `/WR`, an unprotected chip can be written by a crashed program.
- **DC supply.** The clock cannot run without the mains NMI, but updates work: the page writer only syncs to the NMI if one has ever fired.
- **The sign's RX is DB9 pin 8**, not pin 2; the factory cable crosses 3→2, 8→3 and ties 2 to 5.
- **Both banks identical hides bank-register faults.** A register that is stuck, unclocked or random still boots, because either bank runs. The dry run's two trailers are the test: the same sequence number for both means pin 1 never moved.

### Changing the firmware or writing a host

- **Never load `I` with `C0` or above, never read `C000–FFFF`.** Refresh cycles and reads clock the bank register with whatever is on the bus. The emulator reports both as faults.
- **The NMI follows the mapped bank.** `NMI_VECTOR` jumps through the jump table at `0246` of whichever bank is in the window, so an NMI that lands while `lib_copy` has the idle bank mapped (`I`, `C`, `F`) runs the *other* image's `nmi_entry` and `clock_tick` against this image's RAM map. The app holds `NMI_MAGIC` off around those copies (`ota_copy`, patch 35); the emulator reports an NMI taken with the idle bank mapped as a fault. The page writer is different: it syncs to the NMI and finishes before the next one.
- **The RAM library overruns `FRAMEBUF`** (192 bytes) at boot. The application copies only `STUB_LIB_APP_SIZE` bytes; the stub copies all of it, over the first 130 bytes of variables. Nothing that must survive a reset lives there (patch 20).
- **A reply is not "ready for the next frame".** Replies and DONE leave in the background while the display runs, and a frame that arrives before DONE is parsed and thrown away unanswered. Use flag `81` and wait for the `04`; without it, allow the reply's wire time plus 1 s.
- **Binary replies rely on two stock-bug fixes** in the patched build: a `00` byte offered to a busy transmitter was dropped (B10), and a `20` byte inside a packet counted as the SPACE key and released a WAIT (B12).
