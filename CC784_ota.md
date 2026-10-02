# CC784NIR — over-the-air ROM updates

The patched firmware can be replaced over the sign's own 300-baud serial link.
The ROM is an AT28C256 EEPROM split into two 16 K banks; an update is written
into the bank that is not running, verified there, and booted on the next
reset, so a failed or interrupted update never touches the running code. Only
the 64-byte pages that differ are sent.

What you need: the bodged AT28C256 and bank register (`AT28C256.md`), the
patched firmware from `src/patched/`, `tools/cc784_ota.py`, and a serial path
to the sign (a USB adapter or the ESPHome `serial_proxy` bridge). The sign
must be on its AC supply: page writes are timed off the mains interrupt.

---

## 1. Hardware

| Part | Change | Purpose |
|---|---|---|
| EEPROM pin 27 (`/WE`) | lifted, to Z80 `/WR` with a 10 k pull-up | writes |
| EEPROM pin 22 (`/OE`) | lifted, to Z80 `/RD` | the socket ties `/OE` to `/CE`, which inhibits writes |
| EEPROM pin 1 (A14) | lifted, to the bank register's Q0 | bank select |
| Bank register | a second '273 piggybacked on U5; clock from LS139 U4 pin 9 (`C000–FFFF`), `/MR` from Z80 `/RESET` | an 8-bit write-only register at `C000`; bit 0 = A14, bits 1–2 reserved for A15/A16 of a larger chip, the rest spare |
| RAM (optional) | AS6C62256 with pin 26 → A13 and pin 1 → A14 | 15278-byte message store instead of 7086; the firmware detects which chip is fitted |

The register is separate from U5 because U5 is cleared by the board's
watchdog whenever interrupts stop for 512 µs, which happens during every
packet; a bank bit there would swap the ROM under the running code. The
register resets to 0, so the sign always powers up in bank 0.

ROM `/CE` is gated by `/MREQ`, so only memory accesses to `0000–3FFF` reach
the chip; I/O and refresh cycles never do. Step-by-step wiring, continuity
checks and the first power-up are in `AT28C256.md`.

## 2. ROM layout (each bank)

| Range | Content | Written by |
|---|---|---|
| `0000–01FF` | boot stub: reset, `0038`, `0066`, bank choice, `stub_lib` | T48 only |
| `0200–0208` | jump table: `JP app_start`, `JP int_timer`, `JP nmi_entry` | OTA |
| `0209–3FBF` | application (`ROM_ID` directly after the table) | OTA |
| `3FC0–3FFF` | trailer page | OTA, written last |

**Trailer:** `+0` `"OTA1"`, `+4` sequence number, `+5` state (3 = GOOD; 1 and
2 are reserved for a trial/confirm scheme), `+6` CRC-16 of `0200–3FBF`,
`+8` CRC-16 of bytes `+0..+7`, rest `FF`. CRC-16/XMODEM (poly `1021`, init
0), little-endian words.

**Stub rule:** the stub never changes over the air. The `W` command refuses
pages 0–7, `push` refuses an image whose stub pages differ from the sign's,
and the stub references nothing in the application except the jump table, so
application changes never alter its bytes. A stub change needs the T48.

**RAM used:** `7FFC–7FFF` (`NMI_VEC`, `NMI_MAGIC`, `ROM_BANK`), which the
stock 6264 mirrors from `5FFC–5FFF`. The page writer and the bank-touching
routines run from `FRAMEBUF` (`4000`), which is idle while a packet is
processed. No message-store space is used.

## 3. Boot

1. `DI`, clear `NMI_MAGIC` (a mains NMI before the vector is set is ignored),
   `SP` = `7EF0`, copy `stub_lib` to `4000`. Everything that writes the bank
   register runs from that RAM copy, so the other bank's contents never
   execute during boot, whatever they are.
2. Validate both trailers (magic and trailer CRC).
3. Candidate order: newer sequence number first (signed 8-bit difference,
   ties to bank 0); if only one is valid, that one; if none, bank 0 without
   further checks (the state after a T48 burn of a raw build).
4. CRC the candidate's `0200–3FBF`; on mismatch try the other. About 1 s per
   pass at 8 MHz.
5. Select the bank, record it in `ROM_BANK`, point `NMI_VEC` at the jump
   table, jump to `0200`.

## 4. The OTA command

Sent inside the normal packet frame (`B1 addr 81 len payload cksum`),
addressed, immediate mode; the OTA command byte (`B5`, `CMD_OTA`) must be
the first payload byte and the command ends the packet. Replies are reply frames (`B1 addr len data cksum`)
and go out after the work. With flag `81` a `04` DONE byte follows the reply
once the sign can receive again (the display restarts with interrupts off
after every packet); the host waits for it, with a 1 s pause as the fallback
for firmware that doesn't send one.

| Payload | Reply |
|---|---|
| `B5 'I'` | `ROM_BANK`, the first 10 trailer bytes of bank 0 and of bank 1, then a features byte (bit 0: DONE supported) |
| `B5 'C' page n` | `n` CRC-16s of idle-bank pages starting at `page`, n ≤ 42 |
| `B5 'B'` | status; erases the idle bank's trailer and parks the display on "> FW UPDATE <" until the reboot |
| `B5 'W' page crc16 data` | status; writes 1–3 consecutive pages, `crc16` over the data, pages < 8 refused |
| `B5 'F' seq crc16` | status; CRCs the idle bank's `0200–3FBF`, and if it matches writes the trailer (GOOD, `seq`) |
| `B5 'R'` | no reply; resets, which boots the newest valid bank |

Status byte: 0 ok, 1 verify failed, 2 chip timeout, 3 page out of range,
4 CRC mismatch, 5 bad arguments.

**Page writes** (`lib_page_writer`, from RAM, interrupts off): wait for the
mains NMI, send the SDP unlock sequence, select the target bank, load the 64
bytes, let the chip's 10 ms write cycle finish, read the page back. The NMI
wait exists because the chip is unreadable, vectors included, during its
write cycle, and the mains NMI cannot be masked; writing right after one
guarantees the next is ~16 ms away. SDP (software data protection) is armed
by the first write and stays armed, so stray writes to `0000–3FFF` are
ignored by the chip.

## 5. Using it

**Build and pack** (`Build patched ROM` then `Pack OTA image`, or):

```
cd src/patched && sjasmplus cc784nir.asm
uv run tools/cc784_ota.py pack src/patched/cc784nir_patched.bin \
    -o src/patched/cc784nir_bank.bin --t48 src/patched/cc784nir_chip.bin
```

`cc784nir_bank.bin` is what `push` sends. `cc784nir_chip.bin` is what the T48
burns: the same application in both banks, sequence 1 and 0, so a fallback
exists from the first power-up. Never burn the raw build: its trailers are
empty.

**Push:**

```
uv run tools/cc784_ota.py push src/patched/cc784nir_bank.bin -H <bridge> -k <key>   # ESPHome
uv run tools/cc784_ota.py push src/patched/cc784nir_bank.bin -p <port>              # serial
```

`push` reads both trailers (`I`, which also switches on the DONE handshake
when the firmware offers it), CRCs every page of the idle bank (`C`, about
25 s), sends only the pages that differ (`B`, then `W` in runs of up to three
pages, ~7 s per run), verifies the whole image on the sign and writes
the trailer with the next sequence number (`F`), reboots (`R`), waits 6 s and
confirms the new bank is running (`I`). `-n` stops after the comparison and
reports the page count; `-s` forces a sequence number. If it fails after `B`
it sends `R`, which boots the old bank because the idle trailer is erased.

**What a push costs:** the diff is against the idle bank, which holds the
image from *two* pushes ago, so a push carries the union of the last two
changes. An inserted byte shifts everything after it, so a code edit early in
the file is typically a 100-page push (~5 min); an edit in the data at the
end of the bank is one page. An interrupted push can simply be run again:
`C` finds the pages already written.

**`diff OLD.bin NEW.bin`** prints the pages two images differ in and the
transfer time.

## 6. Testing

Everything above is modelled in `tools/cc784_sim.py` (AT28C256 with banks,
page timing, SDP and the watchdog). Before pushing a firmware change, run:

| Command | Proves |
|---|---|
| `uv run tools/cc784_sim.py stack patched` | replies unchanged, no stack growth, no EEPROM faults |
| `uv run tools/cc784_sim.py compare OLD_TREE src/patched` | same panel frames and replies as the previous source tree |
| `uv run tools/cc784_sim.py eeprom` | the chip model against the datasheet rules |
| `uv run tools/cc784_sim.py ota` | the stub's bank choice in every trailer scenario, and the page writer |
| `uv run tools/cc784_sim.py update` | a whole OTA update over the fake serial line, including refusals |
| `uv run tools/cc784_sim.py push` | the real `push()` against the emulator |
| `uv run tools/cc784_sim.py ram` | the build on the 6264 and on a 62256: sizes, fill, dump |
| `uv run tools/cc784_sim.py fuzz [N]` | N power cuts at random instants of an update; every reboot must land in a verified bank (1000/1000 when last run) |

The `OTA: emulator regression` task runs the five fast ones.

## 7. Not built

- **Trial/confirm rollback.** `F` would write state TRIAL; the stub would
  mark a TRIAL bank TRIED before booting it and treat TRIED as invalid; the
  host would confirm with a new command once the new firmware answers. This
  would recover from an image that boots but cannot talk, which today needs
  the T48. The trailer's state byte and ~60 spare stub bytes are reserved
  for it.
- **Layout pinning** (`ALIGN 64` slack between modules, fixed `ORG`s for the
  tables) so that small code edits stay small pushes. There are ~450 bytes
  of bank free, not enough yet.
- A table-driven CRC would halve the 1 s boot pass.

## 8. Gotchas

- **RAM A13 (62256 pin 26) must be wired.** Floating, the boot hangs within
  a millisecond: the stub runs from RAM.
- **The '273 stack's ground joint.** A weak one leaves Q0 floating; the
  EEPROM reads garbage and the sign never boots. Symptom: it boots with
  EEPROM pin 1 strapped to ground.
- **Burn with `-u -P`.** `-u` only disables protection before writing; `-P`
  re-enables it. The task does both. With `/WE` on `/WR`, an unprotected
  chip can be written by a crashed program.
- **AC power only for updates.** On a DC supply there is no mains NMI and
  the page writer waits forever.
- **Never load `I` with `C0` or above, never read `C000–FFFF`.** Refresh
  cycles and reads clock the bank register with whatever is on the bus. The
  emulator reports both as faults.
- **The RAM library must fit `FRAMEBUF`** (192 bytes). The application
  copies only `STUB_LIB_APP_SIZE` bytes; the variables start right after.
- **Binary replies exposed two stock serial bugs**, both fixed in the
  patched build: a `00` byte offered to a busy transmitter was dropped
  (B10), and a `20` byte inside a packet counted as the SPACE key and
  released a WAIT (B12).
- **A reply is not "ready for the next frame".** The sign restarts its
  display after every packet with interrupts off (B4). Use flag `81` and wait
  for the `04` DONE byte; without it, send the next frame no sooner than 1 s
  after a reply.
- **The sign's RX is DB9 pin 8**, not pin 2; the factory cable crosses
  3→2, 8→3 and ties 2 to 5.
- **Both banks identical hides bank-register faults.** A register that is
  stuck, unclocked or random still boots, because either bank runs. The
  dry run's two trailers are the test: the same sequence number for both
  means pin 1 never moved.
