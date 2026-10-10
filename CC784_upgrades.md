# CC784 — upgrades and modifications

Three changes to the `CC784-4` controller board, each independent of the others:

| Upgrade | Gives | Parts |
|---|---|---|
| **EEPROM and bank register** (§2) | firmware writable in circuit: over-the-air updates with an A/B fallback ([CC784_ota.md](CC784_ota.md)) | AT28C256-15PU, 74LS273 or 74HCT273, 10 k resistor for R32 |
| **RAM** (§3) | a 15246-byte message store instead of 7054 | AS6C62256-55 |
| **NET to NIR** (§4) | a CC784NET runs the NIR firmware: 8 MHz timebase, and the remote if a receiver is fitted | 8.000 MHz crystal, IR receiver module, optionally a Z84C0008 |

All three run the patched firmware from `src/patched/` ([CC784_patched.md](CC784_patched.md)). The images and tasks are on the **`wip`** branch.

**Method.** Nothing here needs an IC leg bent or soldered to; with some effort, you can replace the 24-pin RAM socket with a 28-pin one and wire its four overhanging pins in Kynar. Every other connection can be made by cutting a track or by moving or removing the factory wire at a socket or pad. Every chip stays swappable, and the original M27C256B goes back in at any point as the fallback. The KiCad schematic ([hardware/CC784NIR/](hardware/CC784NIR/)) carries notes on where each track is cut and where the wires land.

---

## 1. Before you start

- **Programmer.** The T48 needs firmware `00.1.34` or later; any minipro command prints it. The factory `00.1.03` drives D6 and D7 low during the program pulse, so writes come back with two zero bits per byte while reads, ID and blank check all look right (verify fails at the first byte needing bit 7 or 6 high, such as `File=0xF0, Device=0x30`). `minipro -F UpdateT48.dat` with the file from an XGpro installer (V12.90 ships `00.1.34`) fixes it; minipro's "newer than expected" warning is harmless.
- **Program before wiring.** Nothing on the chips needs changing, and a socketed chip goes in and out of the T48 freely.
- **Keep the M27C256B un-erased** until the EEPROM is proven in the sign.
- **Meter** for the continuity checks.

---

## 2. EEPROM and bank register

How the banking works is in [CC784_ota.md](CC784_ota.md); this is the bench view. The chip must be writable in circuit, which the 27C256 socket does not provide, and it becomes two 16 K banks selected by a register the board does not have.

### Wiring

| EEPROM pin | Socket supplies | Needed | Wire to |
|---|---|---|---|
| 27 | A14 (factory wire from Z80 pin 4 on the NIR; nothing on the NET, whose 27128 has `/PGM` here) | `/WE` | **Z80 pin 22 (`/WR`)**, with 10 k to 5 V in **R32**, the footprint that already sits on this pin's net (empty on a NIR; a NET has the 27128's 3.3 k `/PGM` pull-up there, which can stay) |
| 22 | `/CE` (LS139 pin 12, same net as pin 20) | `/OE` | **Z80 pin 21 (`/RD`)**, unconnected on the board |
| 1 | VPP, hard-wired to 5 V | A14 | **the added '273, pin 2 (Q0)** |

Pin 22 is the one that is easy to miss: the AT28C256 refuses every write while `/OE` is low, and the socket holds it low whenever the chip is selected.

The bank register is a second 74LS273 piggybacked on U5, the `8000` control latch: same pinout, so D0–D7, VCC and GND come from the stack.

| '273 pin | Lift? | Wire to |
|---|---|---|
| 3, 4, 7, 8, 13, 14, 17, 18 (D0–D7), 10, 20 | no, soldered to U5's pins | — |
| 11 (clock) | yes | **U4 pin 9** (LS139 `2Y3`, `C000–FFFF`, unused) |
| 1 (`/MR`) | yes | **Z80 pin 26 (`/RESET`)**: bank 0 at every power-up |
| 2 (Q0) | yes | EEPROM pin 1 |
| 5, 6, 9, 12, 15, 16, 19 (Q1–Q7) | yes, leave free and insulated | spare (Q1/Q2 reserved for A15/A16 of a bigger chip; Q7 is the IR and clock add-in board's clock-source select) |

### Program the chip — 5 min

- [ ] Seat the chip in the T48 ZIF, **ensuring pin 1 is oriented as shown on the programmer.** Close the lever.
- [ ] Run task **`AT28C256-15PU -- program`** (`⇧⌘P → Tasks: Run Task`). It builds, runs **`Pack OTA image`** (trailers for both banks) and burns `cc784nir_chip.bin`, 32 K, then verifies. Repeat this step whenever the boot stub changes ([CC784_ota.md §2](CC784_ota.md#2-rom-layout-each-bank)): `push` refuses an image whose stub differs from the sign's.
- [ ] minipro reports **Verification OK** and no ID mismatch. On a contact error, `minipro -p AT28C256 -z` does a pin check.

### Wire — 30 min

**EEPROM socket**

- [ ] Pin 1 (A14) → Bank register ('273 added below) pin 2 (Q0).
- [ ] Pin 22 (`/OE`) → Z80 pin 21 (`/RD`).
- [ ] Pin 27 (`/WE`) → Z80 pin 22 (`/WR`), plus 10 k to 5 V in R32 (on a NET the fitted 3.3 k serves).

**Bank register ('273 stacked on U5)**

- [ ] Pin 1 (`/MR`) → Z80 pin 26 (`/RESET`).
- [ ] Pin 11 (clock) → U4 pin 9.
- [ ] Pin 2 (Q0) → EEPROM socket pin 1, the wire above.
- [ ] Pins 5, 6, 9, 12, 15, 16, 19 (Q1–Q7): free, insulated (Kapton) or at least bent well clear of the IC is sits on.

**All**

- [ ] Sleeve or dress every wire; the enclosure is metal.

### Check before power — 5 min

EEPROM out of its socket for its three checks.

**EEPROM socket** (chip out)

- [ ] Pin 1 ↔ '273 pin 2: beep.
- [ ] Pin 22 ↔ Z80 pin 21: beep.
- [ ] Pin 27 ↔ Z80 pin 22: beep.
- [ ] Pin 27 ↔ 5 V: the pull-up, ~10 k (3.3 k on a NET), not a short.
- [ ] Pins 1, 22 and 27 ↔ their original nets (5 V, `/CE`, Z80 pin 4): must **not** beep.
- [ ] **Chip notch matches the socket notch when it goes back in.**

**Bank register ('273 on U5)**

- [ ] Pin 1 ↔ Z80 pin 26: beep.
- [ ] Pin 11 ↔ U4 pin 9: beep.
- [ ] Pin 11 ↔ U5 pin 11: must **not** beep (it would clock with the control latch).
- [ ] Pins 5, 6, 9, 12, 15, 16, 19 (Q1–Q7) touch nothing.
- [ ] Pin 10 ↔ ground is a solid joint: a weak one leaves Q0 floating and the sign never boots.

### Power on — 5 min

With no battery, RAM comes up invalid and the patched firmware re-initializes: empty store, default sequence, address 1.

- [ ] Sign powers up, no heat, no smell.
- [ ] About a second of dark before anything shows: the stub CRCs the bank before running it.
- [ ] Touch the EEPROM after ~30 s. **Warm means `/WE` is being driven**: power off and recheck the pin 27 wire.
- [ ] The built-in demo scrolls ("COLOR CELLS CC784 MULTI-COLOR DISPLAY ...").

### First OTA — 10 min

Do the dry run even if you only ever intend to run the image from this repo: with the same application in both banks the sign boots whether or not the bank register works, and the dry run is the only test that pin 1 actually moves. The two pushes after it are optional until there is something new to push; both banks already hold the same application, so they write nothing but a trailer and the proof is in the tool's output.

- [ ] Dry run, which proves the bank bit flips and both trailers read back (~30 s: the tool CRCs all 256 idle-bank pages):
      ```
      uv run tools/cc784_ota.py push src/patched/cc784nir_bank.bin -p <port> -n
      ```
      Expect `running bank 0: {'seq': 1, 'state': 3, …}`, `idle bank 1: {'seq': 0, …}` and `0 pages to send`. The same seq for both banks means pin 1 never moved: both reads landed in bank 0.
- [ ] The same command without `-n`: no error from `finish`, a pause, then `OK: running bank 1, {'seq': 2, …}`. The demo keeps playing.
- [ ] Push again: `OK: running bank 0, {'seq': 3, …}`. Both banks have been written and booted.
- [ ] Power-cycle. The sign comes back on bank 0, the newest sequence.

ESPHome bridge: `-H <host> -k <key>` instead of `-p <port>`.

---

## 3. RAM

An AS6C62256 (32 K, 16 K reachable) in place of the HY6264. The firmware detects which chip is fitted at boot, so the same image runs on either.

- [ ] Replace the 24-pin socket with a 28-pin one; the 6264's pins 1, 2, 27 and 28 hang outside the 24-pin footprint.
- [ ] Remove the factory wire from U13 pin 8 to pin 26 (CS2 on the 6264, A13 on the 62256) and wire pin 26 to **Z80 pin 3**. Left floating, the boot hangs at once: the stub runs from RAM.
- [ ] Pin 1 (NC on the 6264, A14 on the 62256) to **Z80 pin 4**. A14 is always 1 while RAM is selected, so the chip's upper half is used; GND would use the lower half equally well.
- [ ] Check: pin 26 ↔ Z80 pin 3 and pin 1 ↔ Z80 pin 4 beep; pin 26 ↔ U13 pin 8 must **not** beep.
- [ ] The power-fail deselect still works: U13 gates the RAM's `/CE` with the same signal that drove CS2, so nothing is lost with pin 26 ([hardware notes §7](CC784_hardware.md#7-power-battery)).
- [ ] After power-up, `B4 '1'` reports `total 15246` (`total 07054` with the 6264). Anything else means an address line is not landing.

---

## 4. NET to NIR

The CC784NET is the same board with a 4 MHz crystal, the original interrupt gating, no IR parts and a keypad on the DB9 ([CC784_hardware.md §3](CC784_hardware.md#3-timebase-h) and §6). The NIR firmware, and the patched one, need the NIR timebase.

- [ ] Crystal Y1: 4 MHz out, **8.000 MHz** in.
- [ ] Cut the track from U14 pin 1 to U10 pin 12; bridge U10 pins 12 and 13. The interrupt is now Q11 of the HC4020 alone, the 7812.5 Hz tick.
- [ ] CPU: the NET's Z8400A is a 4 MHz grade. It runs at 8 MHz in practice; a **Z84C0008** is the in-spec replacement and drops straight in.
- [ ] Remote, if wanted: U18 (CD74HC14), the 3-pin receiver header near it, a **30 kHz** receiver module (TSOP4830/TSOP38230 class; the remote's carrier is 31.25 kHz), and the wire from U18 pin 6 to the DB9 pin 1 net.
- [ ] The NET firmware's cable detect is gone with it: no pin 2–5 short is needed on the serial cable, and the keypad is no longer scanned.

Then §2 and §3 as for a NIR board.

---

## 5. Checks after any upgrade — 5 min

The patched firmware answers at address **1** (stock: 0); use `-a 1`.

- [ ] **Serial**, ten times in a row, no stray bytes:
      ```
      uv run tools/cc784.py -p <port> -a 1 --unsafe id
      ```
      Expect a `B1 01 10 "78409O1702930205" …` frame each time.
- [ ] **Clock** survives a short `17`:
      ```
      uv run tools/cc784.py -p <port> -a 1 time
      uv run tools/cc784.py -p <port> -a 1 msg 0 "@{time}"
      uv run tools/cc784.py -p <port> -a 1 raw 17 32
      ```
      The displayed clock keeps advancing after the third command.
- [ ] **Dump**: `--unsafe dump` returns the store with a good checksum.
- [ ] **Append** into an empty channel: `raw 09 30 31 b3 58 59 5a 57`, then `--unsafe dump` shows channel 1 as `XYZW`.

---

## 6. Over-the-air updates

With §2 done, firmware goes in over the serial link: `push` sends only the 64-byte pages that differ, into the bank that is not running, and the sign boots it on the next reset with the old bank as the fallback. Commands, layout, boot stub, trial and rollback, and the emulator tests are in [CC784_ota.md](CC784_ota.md).

---

## If something is wrong

| Symptom | Look at |
|---|---|
| Display completely dead | EEPROM pin 27 still on the socket net, or pin 1 not connected |
| EEPROM warm | `/WE` driven: pin 27 wire open or shorted to A14 |
| Intermittent garbage, changes on reboot | pin 1 floating: A14 indeterminate |
| Boots only with EEPROM pin 1 strapped to ground | the '273 stack's ground joint |
| Boots but always blank or `FF` | pin 1 stuck high, reading the empty upper 16 K |
| Steady beep, never boots | RAM pin 26 (A13) floating |
| Demo plays, no serial reply | crossover or port, not the chip: try `sniff` |
| minipro ID mismatch | wrong device name, or chip not seated |
| `push -n` shows the same seq for both banks | pin 1 not on '273 pin 2, or '273 pin 11 not on U4 pin 9 |
| OTA status 2 (chip timeout) | `/WE` never reaches the chip: pin 27 |
| OTA status 1 (verify failed) | `/OE` still on the socket net: pin 22 |
| `NOT RUNNING THE NEW IMAGE` | the stub rejected the trailer or image CRC; power-cycle and push again |

Fallback at any point: refit the original M27C256B.

---

## Reference

- minipro device name: **`AT28C256`**, no `@DIP28` suffix.
- Image: `src/patched/cc784nir_chip.bin`, 32768 bytes, from the `Pack OTA image` task. The raw build `cc784nir_patched.bin` has empty trailers and boots without a bank check; never burn it.
- Stock image for comparison: `src/stock/cc784nir.bin`, md5 `c021af146a50b93a22d13535201b7eaa`.
- The chip's two halves are the two banks; the packed image carries the same application in both, sequence numbers 1 and 0, so the sign boots bank 0 and has a fallback from the first burn.
