# CC784NIR hardware — reference notes and open questions

Color Cells / Innovative Sign Technology **CC784NIR** ("NIR" = infrared remote variant). Controller board silk-screened `CC784-4` (rear: `COLOR CELLS CC784-4`), double-sided, through-hole only, factory bodge wires. Chip date codes 9235–9246 (late 1992); firmware dated 17-02-93. Photos on file: front, rear, backlit detail of the DB9/LS244 area.

Confidence key as in the firmware notes: **[H]** verified, **[M]** inferred, **[L]** hypothesis.

---

## 1. Parts list (from photos) [H unless noted]

| Ref | Part | Role |
|---|---|---|
| U1 | Zilog **Z0840008PSC** (Z80, 8 MHz grade) | CPU |
| U2 | ST **M27C256B-15F1** (32 K × 8, 150 ns) | firmware ROM; only lower 16 K used |
| U3 | Hyundai **HY6264ALP-10** (8 K × 8 SRAM) | RAM `0x4000–0x5FFF` |
| U4 | 74LS139 | U4B memory decode, U4A I/O decode ([§2](#2-memory-and-io-decoding-h--from-the-schematic)) |
| U5, U9 | 74LS273 ×2 | U5 = `CTRL_LATCH` (`0x8000`), U9 = color latch ([§5](#5-display-drive-h--from-the-schematic-and-the-firmware)) |
| U6 | **74LS145** (BCD→decimal, OC) | row select → TR1–TR7 |
| U7, U8 | 74LS151 ×2 | row-bit selector and color selector for the panel data ([§5](#5-display-drive-h--from-the-schematic-and-the-firmware)) |
| U10, U16, U17 | 74LS00 ×3 | glue |
| U11 | 74HC04 + 8.000 MHz crystal | oscillator |
| U12 | 74LS244 | serial outputs, and the input port read by `IN 0xC0` ([§4](#4-serial-port-h)) |
| U13 | 74HC132 | RAM `/CE` gating and the power-fail CS2, on the battery rail |
| U14 | **74HC4020** (14-stage ripple counter) | timebase divider ([§3](#3-timebase-h)) |
| U15 | LM340T-5 (7805) | 5 V regulator |
| U18 | CD74HC14 | IR receiver conditioning |
| U19 | 74HC164 | first stage of the column shift chain ([§5](#5-display-drive-h--from-the-schematic-and-the-firmware)) |
| TR1–TR7 | TIP125 (PNP Darlington) | LED row drivers |
| Q8, Q9 | BC548 | beeper driver; power-fail detector for CS2 ([§7](#7-power--battery)) |
| C1, C2 | 4700 µF 16 V | bulk filter |
| R4, D3 | 220 Ω, diode | battery charge/discharge path and the `+5VP` rail ([§7](#7-power--battery)) |
| SK2 | 14-pin connector | display panel ([§6](#6-connectors)) |
| J | DB9 male | serial ([§4](#4-serial-port-h)) |
| — | "NICAD BATTERY" footprint | RAM backup; **was fitted, removed (leaking)** |
| — | 3-pin header (right edge, glued) | IR receiver module (5 V; the remote's carrier is 31.4 kHz, [§6](#6-connectors)) |
| — | barrel jack | 9 V **AC** in (supplied PSU: 9 V AC, 4.2 A transformer) |
| — | piezo/speaker near SK2 | beeper (`0x07` command) |

## 2. Memory and I/O decoding [H — from the schematic]

U4 (74LS139) does both halves:

- **Memory (U4B, enabled by `/MREQ`, inputs A15/A14):** `2Y0` ROM `/CE` and `/OE` (`0x0000–0x3FFF`); `2Y1` → U13 → RAM `/CE` (`0x4000–0x7FFF`, gated by CS2, [§7](#7-power--battery)); `2Y2` clocks U5, the control latch (`0x8000`); `2Y3` (`0xC000–0xFFFF`) is unused on the stock board and now clocks the OTA bank register.
- **I/O (U4A, enabled by `IORQ·/M1` so interrupt acknowledges are excluded, inputs A7/A6):** `1Y0` (`0x00–0x3F`) unused; `1Y1` = the `0x40` group: clocks the on-board HC164 (U19) and the panel's column clock (J2 pin 11, through U18), and, gated with D7 in U10, clocks U9, the color latch; `1Y2` = `0x80`, the strobe (J2 pin 12); `1Y3` = `0xC0`, enables the '244's input half onto the bus. Within the `0x40` group the Z80's low address bits are used as data: A0–A2 select the row bit ([§5](#5-display-drive-h--from-the-schematic-and-the-firmware)), A3 the intensity pass, A5 the beeper, and A8 — the `B` register during `OTIR` — red or green.

### ROM socket wiring [H — traced on the board]

- **Pins 1 (VPP) and 28 (VCC) are both on the 5 V net**, joined by a visible trace. Nothing on the board can drive VPP, so any substitute that expects an address line on pin 1 has to have that pin lifted.
- **A14 reaches the EPROM on pin 27 through a factory bodge wire from Z80 pin 4.** The PCB does not route it. That fits a layout originally cut for a 2764/27128, where pin 27 is `/PGM` and gets tied high. On a 27C256 the same pin is A14 and must be low for the chip to read its lower half; A14 is always 0 whenever the ROM is selected, so the wire simply holds it low. The NET ships with a 27128 and has no such wire; instead R32, a footprint from pin 27 to 5 V that is empty on the NIR, carries a 3.3 k pull-up for the 27128's `/PGM`. The same footprint takes the `/WE` pull-up of the EEPROM upgrade. ROM `/CE` is only asserted when A14 = 0, so the chip is permanently confined to its lower 16 K — which is why the upper half of the dump is `0xFF`, and why the NIR firmware runs from a 27128 just as well. Only the EEPROM's two OTA banks use the upper half, through the bank register on its pin 1 ([CC784_upgrades.md §2](CC784_upgrades.md#2-eeprom-and-bank-register)).

Substitutes, given the above:
- **W27C512** — pin 1 is A15 and sits on 5 V, so the upper half runs; program the 32 K image twice.
- **AT28C256 / 28C64** — pin 1 is A14 and pin 27 is `/WE`, both swapped relative to the 27C256. Straight substitution is destructive: board A14 lands on `/WE` and goes low on every ROM fetch. Two bodges make it exact: lift **pin 27** and jumper it to VCC (writes permanently disabled), and lift **pin 1** and run it to A14 (Z80 pin 4). With both done the part is electrically a 27C256 and takes the ordinary 32 K image unchanged — `/CE` only asserts when A14 = 0, so nothing above the chip's own `0x3FFF` is ever addressed. Skipping the pin 1 bodge leaves A14 stuck high on the VPP net; that needs the low 16 K duplicated into both halves instead.

## 3. Timebase [H]

8.000 MHz crystal → HC04 oscillator → the Z80 clock and the HC4020 (U14). The counter is **reset by every interrupt acknowledge** (`M1·IORQ`, U17 → U11 → pin 11), and `/INT` is its Q11 output inverted: it asserts 1024 clocks = 128 µs after the last acknowledge, which is the 7812.5 Hz tick. Q13 goes high 4096 clocks = 512 µs after the last acknowledge and, inverted by U17, **clears U5**, the control latch, for the next 512 µs: a watchdog that blanks the rows and parks TX whenever the firmware stops servicing interrupts, for instance for the whole of `pkt_process`. It is why the OTA bank register is a separate chip ([CC784_ota.md §1](CC784_ota.md#1-hardware)). The Z80 runs at the full 8 MHz: the firmware's per-tick work does not fit 4 MHz ([firmware notes §3](CC784_firmware.md#3-execution-architecture-h)).

**As designed (the CC784NET board):** 4 MHz crystal, and U10 NANDs Q11 with Q12 (pin 1, the trace the NIR cuts), so `/INT` asserts 3072 clocks = 768 µs after the acknowledge: 1302 Hz, the rate the NET firmware runs its serial engines and row scan at directly. The NIR's 8 MHz crystal and the Q11-only bodge give the 7812.5 Hz tick its IR decoder needs; its firmware divides by 6 to get the same 1302 Hz for everything else. A NET board needs both the crystal and the bodge before it can run the NIR firmware. The converted board here runs the patched firmware on its original Z8400A, a 4 MHz grade part, at 8 MHz; that is one sample outside its rating, so expect to need a Z84C0008 if yours does not.

NMI: 60 Hz from the AC input via a zero-cross detector (`NMI_PER_SEC = 60`), U18 pin 4. With a DC supply the clock would not run; the supplied PSU is AC, so it does. The IR and clock add-in board ([hardware/CC784NIR_IR+Clock/](hardware/CC784NIR_IR+Clock/)) cuts that trace and puts a 74HC151 between U18 and the Z80: input 0 is the mains pulse, input 1 a 64 Hz square wave from an HC4060 on a 32.768 kHz crystal, and the select is the bank register '273's Q7 (pin 19), its top bit; Q1 and Q2 stay free for a larger EEPROM. The patched firmware picks the crystal when no mains cycle arrives at boot ([CC784_patched.md](CC784_patched.md#2-patches), patch 31). The board also carries the TSOP38230 receiver for both signs; its 7-pin connector is GND, AC_IN, CLOCK_OUT, +5 V, CLOCK_SEL, IR_RX, GND.

## 4. Serial port [H]

DB9 wiring, from the schematic:

| DB9 | Dir | Serial role | Keypad role ([§6](#6-connectors)) | Path |
|---|---|---|---|---|
| 1 | in | — | column code bit 1 | R8 pull-up → U12 → `PORT_IN` bit 1; shares the net with the IR receiver output (factory bodge, [§8](#8-factory-bodge-wires-h--from-the-schematic)) unless the receiver is moved to bit 4 ([CC784_upgrades.md §8](CC784_upgrades.md#8-ir-off-the-db9)) |
| 2 | in | PC detect on the NET firmware: the factory cable ties it to pin 5 ([§6](#6-connectors)) | column code bit 0 | R9 pull-up → U12 → `PORT_IN` bit 0 |
| 3 | out | **TX** (ACK/NAK, query replies) | row select bit 0 | U12 pin 18 (1Y1) ← `CTRL_LATCH` bit 4 |
| 4 | out | — | row select bit 1 | U12 pin 16 (1Y2) ← latch bit 5; the NIR firmware never drives it |
| 5 | — | GND | GND | — |
| 6 | in | — | column code bit 2 | R6 pull-up → U12 → `PORT_IN` bit 2; not read by the NIR firmware |
| 7 | out | — | row select bit 2 | U12 pin 14 (1Y3) ← latch bit 6; the NIR firmware never drives it |
| 8 | in | **RX** — the only real RS-232 receiver on the board | key pressed, active low | R30 270 Ω → D8/D9 clamp → R7 3.3 k pull-up → U12 → `PORT_IN` bit 3 |
| 9 | out | +5 V | +5 V | R31 10 Ω from +5 V |

The factory cable is the crossover: sign 3 → PC 2, **sign 8 → PC 3**, and sign 2 and 5 → PC 5. Levels: TTL out of the LS244 on the outputs; pin 8 is the one input with a proper RS-232 clamp (negative swing shunted by D9, so bit 3 reads 1 during space). Polarity as the firmware sees it: `PORT_IN` bit 3 = 1 during space; `CTRL_LATCH` bit 4 = 1 drives space. 300 baud, 8 data, no parity; sign checks 1 stop bit, sends ~2.

Working setups (both verified with live ACKs): USB-RS232 adapter + crossover; [ESPHome serial proxy](https://esphome.io/components/serial_proxy/) via `cc784_esphome.py` (aioesphomeapi 46.4.x). A MAX3232 is the faithful interface; direct 3.3 V TTL with software inversion would probably work through the 220 Ω but is unverified.

## 5. Display drive [H — from the schematic and the firmware]

- **Row select:** U5 Q0–Q3 → U6 (LS145) → TR1–TR7 → J2 pins 1–7. `ROW_INDEX` counts 0–6 once per frame, each row written twice (the two intensity passes) before it advances. Both the data-pass port and the latch code are `6 − ROW_INDEX`, except that the latch gets 7 instead of 0, so LS145 output n carries frame-buffer bit n for n = 1–6 and output 7 carries bit 0, the top of every glyph; the scan runs bottom to top. The panel's rows are in SK2 pin order, top row on pin 1 [H — checked on the panel], so output 7 feeds pin 1 and outputs 1–6 feed pins 2–7. Code 0's output is unconnected and `0x0F` decodes to nothing, so both blank. U5 Q4 is serial TX, Q5/Q6 go to DB9 pins 4/7 (unused), Q7 is the 2.4 Hz FLASH clock.
- **Column data:** one `OTIR` of 86 bytes per row, the same 86 column bytes for every row. U7 (LS151, data = D0–D7, select = A0–A2 = the row) picks the current row's bit out of each byte and feeds it to the on-board HC164 and to U16, whose output is J2 pin 10, the panel's serial data. Each row is written twice, to `0x40+row` then `0x48+row`, displayed for one and two ticks respectively ([firmware notes §8](CC784_firmware.md#8-rendering-h)): A3 selects intensity bit 0 or bit 1 of the color, giving four levels with 1:2 weights.
- **Color:** a byte with bit 7 set is latched by U9 instead of being shifted (U10 gates the `0x40`-group clock with D7). Bits 0–1 green and 2–3 red intensity, bit 4 FLASH, bits 5–6 background red/green (one bit each, so the four background names). U8 (LS151) takes U9's outputs: for a lit pixel it selects the foreground bit chosen by A3 (which intensity bit) and A8 (green or red, alternating per column because `B` counts down on A8–A15 during `OTIR`); for an unlit pixel it selects the background bit. The FLASH bit is ANDed with U5 Q7 in U10 to blank flashing columns on the off phase. U9 Q7 is latched from **A5**, not the data bus, and drives the beeper through Q8: `OUT (0x68+row)` beeps.
- **The panel** [H — inspected]: two PCBs of 7 × 42, red and green LEDs alternating per column (right-most green, left-most red), common anode per row from TR1–TR7 at +9 V, cathodes per column into ULN2003As (six per PCB) driven by 74LS164s (six per PCB) in one daisy chain. Each PCB's last '164 uses two outputs and passes the second on to the next PCB, so the six unused outputs are off the data path and the chain is exactly 84 stages with no latch. SK2 lands on the right-hand PCB and the data shifts right to left, so of the firmware's 86 bits per row the first two sent fall off the left edge, the third is the left-most (red) column and the last is the right-most (green): `FRAMEBUF` reads left to right with a two-column margin at its start. The 85 zeros of `shift_chain_clear` flush the chain; the row is blanked while shifting and selected after. Single-color text therefore lights every other column; yellow lights both.
- **Background codes** `0x94–0x9F` draw no background (watched on the sign); the two hardware background bits make only `0x90–0x93` useful.

## 6. Connectors

**SK2 (14-pin, to the LED panel)**, counted from the board's bottom corner (traced on the board): pins 1–7 LED rows (from TR1–TR7); 8–9 regulated +5 V for the panel logic (the '164s and ULN2003s); the LED current comes down the row pins from the unregulated rail; 10 column data, 11 column clock (port `0x40`); 12 is the port `0x80` strobe but is not connected on the panel; 13–14 GND.

**IR header**: 3 pins — 5 V, GND, signal — glued near U18, cabled to the receiver module on a small add-in board beside the display PCBs, behind a window in the front acrylic. Signal → HC14 → `PORT_IN` bit 1 (one inversion; active-low module output becomes 1 = burst). Verified by capture: module output idles high, bursts low, and lengthens each burst by ~250 µs relative to the transmitted half-bit (512 µs → ~780 µs).

**The IR carrier is 31.25 kHz nominal, 31.4 measured.** The remote is a Motorola MC14497P PCM transmitter on a 500 kHz ceramic resonator (board BP0300346B, 62 keys, two IR LEDs); the chip's carrier is the oscillator divided by 16 and its bit cell is 512 oscillator cycles, 1024 µs. Logic analyzer on its driver output: 31.88 µs period, 29 % duty, every burst 16 cycles = 510 µs, start burst 3.06 ms after the leader, frames every 89.8 ms. A 30 kHz receiver (TSOP4830/TSOP38230 class) is the closest replacement, 33 kHz the next; a 38 kHz part is 17 % off and chops the bursts.

**Keypad**: plugs into the DB9. The same `CC784-4` board ships as the CC784NET (keypad or PC, no IR), and that firmware scans a keypad over the seven DB9 signals [H — from the NET ROM, see [firmware notes §14](CC784_firmware.md#14-the-cc784net-firmware-h--from-a-rom-dump-78409n1401920145)]:

**The CC100 keypad (PCB `CC-KP1`) [H — photo]:** 63 keys, an MC74HC138 decoding the three row-select bits into eight row lines and an SN74LS148 priority encoder turning the eight column lines (pulled up by RN1) into the 3-bit column code, its GS output being the active-low key-pressed line. With no key pressed the '148 outputs are all high, so the column bits and the key-pressed line idle high: `PORT_IN` bit 0 reads 1 at boot (keypad mode) and bit 1 reads 1 (no boot clear). The '148 outputs are active low, so the column code the firmware reads is the inverted column number; `keypad_scan`'s key codes already include that.

| Signal | DB9 | Firmware side |
|---|---|---|
| row select, 3 bits (decoded to 8 rows in the keypad) | 3, 4, 7 | `CTRL_LATCH` bits 4–6 |
| column code, 3 bits (encoded from 8 columns in the keypad) | 2, 1, 6 | `PORT_IN` bits 0–2 |
| key pressed, active low | 8 | `PORT_IN` bit 3 |

Key code = row × 8 + column (`keypad_scan`, identical in both ROMs; key 0 is reported as `0x1E`, which is why the charsets hold `K` at both `0x00` and `0x1E`). The code indexes the `CHARSET_*` tables directly; the NIR's `IR_KEY_TABLE` converts a remote key number into this code, so the remote and the keypad share one editor. STOP/START is code `0x35` (row 6, column 5), SHIFT is `0x19` (row 3, column 1). The keypad's decoder and encoder ICs are inferred from the code, not seen.

**PC or keypad?** The NET firmware decides at boot: it clocks a pattern out on pins 4 and 7 and samples pin 2; pin 2 low (the factory cable's 2–5 short) means serial, anything else means keypad, and in keypad mode the serial engines never run. The NIR firmware skips the test and never calls `keypad_scan`; the patched build drops it.

## 7. Power / battery

9 V AC in → bridge D2 → C1/C2 → 7805 → 5 V logic; unregulated rail to the LED rows via SK2. Battery: 3-cell NiCd footprint. It charges **and** discharges through R4 (220 Ω) to `+5VP`, the rail behind D3 that feeds only the RAM and U13; Q9 watches the main 5 V through zener D1 (4.3 V, marked `4V3`) and R25 (220 Ω, with R10 1 k from base to ground) and, as it fails, turns off, letting R33 (100 k to `+5VP`) pull its collector high; U13 (an HC132 on `+5VP`) inverts that onto the `/CS2` net, which reaches the RAM twice: directly on the 6264's CS2 (pin 26), and through a second gate that NANDs it with the decoded RAM select to make `/CE` and `/OE`. Either path deselects the RAM. The 62256 upgrade turns pin 26 into A13 and removes the first path; the `/CE` path is untouched, so the deselect on power fail still happens, and the 62256 then sits in CMOS standby at about a microamp. The backed-up contents are the message store, address, sequence and clock digits — the clock does not *run* on battery, it only keeps its value.

**Filter capacitors C1/C2.** The originals are 4700 µF 16 V (Marcon on the CC710). They carry the LED rows' ripple current, so replace them with 105 °C parts rated for at least 2 A of ripple at 120 Hz, at 25 V for margin over the unloaded rail. The CC710 has a pair of Chemi-Con EKY-250ELL562MM40S (5600 µF 25 V, 18 × 40 mm) [H]; at that size they still hang off the board edge on their leads like the originals.

> [!WARNING]
> The factory 3-cell NiCd pack leaks with age and its electrolyte attacks the board around it. Every board seen here had leaked. Remove the pack and clean the area before doing anything else, even if the sign still works.

The replacement fitted on both boards is a **5 F 5.5 V supercapacitor (ADCM-S05R5SA505RB)** in the existing charge path through R4, which needs no other change. Other options: a same-chemistry pack off-board, or a CR2032 **with a series diode** (a lithium primary must not be charged). With nothing on `+5VP` the sign boots with an empty store and its default address: 0 on the stock firmware, 1 on the patched.

## 8. Factory bodge wires [H — from the schematic]

- Z80 pin 4 (A14) → ROM socket pin 27 (A14): the layout was cut for a 27128, which the NET still carries; on the NIR's 27C256 this pin must be low, and A14 is always 0 when the ROM is selected.
- The RAM footprint is a 24-pin socket. The 6264's pins 1, 2, 27 and 28 hang outside it, with the wires below soldered straight to the legs.
- Z80 pin 22 (`/WR`) → RAM pin 27 (`/WE`).
- U13 pin 8 (CS2) → RAM pin 26.
- The panel column clock is buffered: J2 pin 11 is cut from the U4 pin 5 net (U11 pin 11, U19 pin 8), that net is wired to U18 pin 11, pins 10 and 9 are bridged, and U18 pin 8 drives J2 pin 11. Two Schmitt inverters in series, so the clock keeps its polarity.
- U10 pin 12 cut from HC4020 pin 1 and bridged to pin 13: the `/INT` gate became an inverter on Q11.
- U18 pin 6 (IR, after the inverter) → the DB9 pin 1 net, which is how IR reaches `PORT_IN` bit 1.

## 9. Open questions

- **Direct 3.3 V TTL serial** without a MAX3232 ([§4](#4-serial-port-h)): probable, unverified.

## 10. Verified-on-hardware summary

The whole board is captured in KiCad ([hardware/CC784-4/](hardware/CC784-4/); the earlier revision in [hardware/CC784-3A/](hardware/CC784-3A/)); the netlist is the source for every [H] above that cites the schematic. Serial framing and checksum; ACK `0x06` on own address (0 after RAM loss); NAK on bad checksum implied by code; message load/display, sequence, clear, clock-set commands; `0xB4` queries crash/corrupt the stock firmware (see firmware notes B1); DB9 pin roles; AC supply; battery footprint; part numbers.

## 11. The CC784-3A board (CC710) [H]

From the photos and the KiCad capture in [hardware/CC784-3A/](hardware/CC784-3A/). The earlier revision of the same controller, silk `CC784-3` on the front and `COLOR CELLS CC784-3A` on the back, with no factory bodge wires. Same Z80 (ST Z8400AB1), same decoding (U4A for I/O with `IORQ·/M1`, U4B for memory, the control latch at `8000`), same display path. Differences from the `CC784-4`:

| | CC784-3A (CC710) | CC784-4 |
|---|---|---|
| ROM | 27128 (16 KB) labelled `CC710-9L-USA`, U2 | 27C256 (NIR) or 27128 (NET) |
| RAM | HM3-6116 2 KB in a 24-pin socket, U3 | 6264 8 KB (28-pin) in the 24-pin socket; its four overhanging pins are on factory bodge wires ([§8](#8-factory-bodge-wires-h--from-the-schematic)) |
| Crystal | 4 MHz; U10 NANDs Q11 and Q12 of the HC4020 (pins 15 and 1) for `/INT`, and Q13 (pin 2) clears the control latch: the NET's original design, 1302 Hz and a 1 ms watchdog. The serial bit tables match the NET's byte for byte, which confirms the rate | 4 MHz NET as designed; 8 MHz with the Q11 bodge on the NIR |
| Host connector | SK1, 2×5 header carrying the seven DB9 signals (below) | DB9 |
| Glue | 74LS164 at U19, plain 74145 at U6, 74HC132 at U13 | 74HC164, 74LS145, 74HC132 |
| Power fail | watches the **unregulated** rail: R25 1 k and zener D1 from the rail, R10 4.7 k to ground, zener D2 as a clamp, C20, straight into an HC132 Schmitt input that gates the RAM's `/CS`; no Q9/R33 | Q9 watches the regulated 5 V and drives CS2 as well as gating `/CE` ([§7](#7-power--battery)) |
| RAM pad 21 | Z80 `/WR` (the 6116's `/WE`) | A11 (a 6264's pin 23); `/WE` reaches pin 27 by a factory wire ([§8](#8-factory-bodge-wires-h--from-the-schematic)) |
| Pull-ups R6–R9 | 3.9 k | 3.3 k |
| IR | none, no header | NIR only |

**SK1 (2×5), traced on the board [H].** The same signals as the `CC784-4`'s DB9, so the DB9 numbers used elsewhere in these notes still apply. The CC710's roles are from [firmware notes §15](CC784_firmware.md#15-the-cc710-firmware-h--from-a-rom-dump-id-710).

| SK1 | DB9 | Firmware side | Keypad | CC710 serial and boot probe |
|---|---|---|---|---|
| 1 | 9 | +5 V through R31 | power | — |
| 2 | 5 | GND | GND | — |
| 3 | 3 | `CTRL_LATCH` bit 4 | row bit 0 | TX |
| 4 | 4 | `CTRL_LATCH` bit 5 | row bit 1 | probe clock; "ready" output in serial modes |
| 5 | 7 | `CTRL_LATCH` bit 6 | row bit 2 | probe data out |
| 6 | 8 | `PORT_IN` bit 3 | key pressed, active low | RX |
| 7 | 6 | `PORT_IN` bit 2 | column bit 2 | must be high for TX to start |
| 8 | 1 | `PORT_IN` bit 1 | column bit 1 | must be high for TX to start and for RX to sample; low at power-up in keypad mode clears the store |
| 9 | 2 | `PORT_IN` bit 0 | column bit 0 | probe sample |
| 10 | — | unused | — | — |

**Panel:** two PCBs, 7×42 and 7×21 with four unpopulated columns, 7×59 in all, ULN2003A column drivers as on the CC784 but a chain of 74HC595s latched by the port `80` strobe (SK2 pin 12, which the CC784's '164 panel ignores). The 7×42 PCB ends in one 74HC164 supplying the two stages a 42-column panel needs beyond five '595s, so the chain passes to the next PCB without extra bits. The firmware shifts 60 bits per row: 42 on the first PCB, 18 on the second, the last into an unpopulated position.

**Battery:** the "NICAD BATTERY" position (a small blue 3-cell can marked 060 on this board, replaced with a 5 F supercapacitor) charges and discharges through R4 220 Ω to `+5VP`, as on the `CC784-4`.

**Beeper:** the CC710 shipped with BZ1, its driver Q8 (BC548) and Q8's base resistor R27 (1 k) all unpopulated; BZ1's silk is for a 25 mm part, leads 12.5 mm apart. The firmware drives it as a plain on/off level, Q8 switching the low side from U9's Q7, so it needs an **internally driven** 5 V buzzer; a bare transducer would only click. Polarity: + on +5 V and − on Q8's collector, as the board's silk and the schematics show. This CC710 now has Q8 and R27 fitted and a VCC MI-TH12-0531-RK (12 mm, 5 V, 3.1 kHz, 30 mA) on BZ1, its leads bent out to the footprint's pads; it fits and sounds [H].

**Store corruption on mains power cycles [H — measured].** Switching the sign off sometimes corrupts the message store, in any input mode. A channel loses its `03` terminator or marker, and the display runs into the free store area, which the boot repair has filled with `?` and leftover characters. The firmware does not cause it (five emulated boots in a row leave an intact store unchanged); a capture of the 5 V rail, `/RESET`, the unregulated rail, U13 pin 5 and the RAM's `/CE` and `/WE` shows where it happens:

- **Switch-off:** the 7805 leaves regulation about 97 ms after the mains goes, with the unregulated rail near 6.3 V. RAM writes carry on at the normal rate as the 5 V rail falls through 4.5 V, then jump about fifteenfold between 3.9 V and 3.5 V: the CPU is running garbage. U13 only stops selecting the RAM when its input falls to about 1.3 V, which happens with the 5 V rail at 3.5 V and the unregulated rail near 4.9 V, some 75 ms after 5 V started to fall. About 3000 stray writes land in that window. `/RESET` stays above 4.5 V throughout, held up by C18: nothing stops the CPU.
- **Switch-on** (after 29 s off): C18 had fully discharged, `/RESET` rose cleanly from 0 V, and the first RAM writes are the firmware's own, about 35 ms in. The power-on reset is not the problem.

So the lockout trips far too late: it watches the unregulated rail, whose ripple under LED load (8.5–9.2 V here) forces a threshold low enough that 5 V is already collapsing when it trips. Whether a given switch-off does damage is chance: it depends on what the CPU is running as its supply leaves spec, and on how long the window lasts (about 27 ms from 3.9 V to 3.5 V here), which shrinks the more LEDs are lit and draining C1/C2 at that moment. The fix is the `CC784-4`'s lockout on the regulated 5 V ([§12](#12-converting-a-cc784-3a-board-to-a-cc784-4), step 2). Fitted on the CC710's board without a reset supervisor, the store survived dozens of power cycles in a row [H].

## 12. Converting a CC784-3A board to a CC784-4

What it takes for a `CC784-3A` board to run the CC784 firmware (stock NET, stock NIR or the patched build) the way a `CC784-4` does. Derived from comparing the two KiCad captures. Verified on the CC710's board [H]: steps 1–4 with the stock CC710 firmware in both banks (step 1 with an AS6C62256, step 2's lockout without a supervisor, step 4 with the AT28C256 and bank register, [CC784_upgrades.md §2](CC784_upgrades.md#2-eeprom-and-bank-register)), then step 5 with a Z84C0020 in place of the Z8400A, after which it runs the patched firmware's CC710 build ([CC784_patched.md](CC784_patched.md#2-patches), patch 37). The `CC784-3A` already has the NET's original timebase (4 MHz, `/INT` from Q11·Q12), so after this it is a `CC784NET` board and [CC784_upgrades.md](CC784_upgrades.md) applies from there.

| Step | Why | Parts | Time |
|---|---|---|---|
| 1. RAM | the CC784 firmware needs 8 KB at `4000` (32 KB for the patched build's larger store) | 6264, or AS6C62256 for the patched build; 28-pin socket | 30 min |
| 2. Power-fail detect and reset | the stock lockout releases the RAM to a CPU running garbage as 5 V collapses, corrupting the store ([§11](#11-the-cc784-3a-board-cc710-h)) | BC548 (or 2N3904, mind the pinout), 100 k, 1 k, 220 Ω, 4.3 V zener; optionally a reset supervisor (DS1233-5 or MCP120-450) | 45 min |
| 3. Host cable | SK1 carries the DB9 signals on a 10-pin header | 10-pin IDC socket, DB9 male, ribbon | 15 min |
| 4. ROM | only for the EEPROM and over-the-air updates; every firmware image fits the 27128 | AT28C256, optionally | 10 min |
| 5. Timebase and IR | only for the NIR or patched firmware | as in [CC784_upgrades.md §4](CC784_upgrades.md#4-net-to-nir) | 20 min |

### 1. RAM

The footprint is for a 24-pin 6116, at positions 3–26 of a 28-pin chip; pins 1, 2, 27 and 28 overhang, as on the `CC784-4` ([§8](#8-factory-bodge-wires-h--from-the-schematic)). Two pads carry different signals on this board, so cut their tracks before fitting the new socket. Pad numbers below are the 24-pin footprint's; RAM pin numbers are the 28-pin chip's:

- [ ] Cut the track at pad 21: `/WR` from Z80 pin 22, the only other part on that net. RAM pin 23 (A11) lands here.
- [ ] Cut the track at pad 24: `+5VP`. RAM pin 26 lands here: CS2 on a 6264, A13 on a 62256.
- [ ] Fit a 28-pin socket in place of the 24-pin one, as in [CC784_upgrades.md §3](CC784_upgrades.md#3-ram), and wire:

| RAM pin | 6264 | 62256 | Wire to |
|---|---|---|---|
| 1 | NC | A14 | nothing (6264); **Z80 pin 4** (62256) |
| 2 | A12 | A12 | **Z80 pin 2** |
| 23 (pad 21) | A11 | A11 | **Z80 pin 1** |
| 26 (pad 24) | CS2 | A13 | **U13 pin 8** (6264, step 2); **Z80 pin 3** (62256) |
| 27 | `/WE` | `/WE` | **Z80 pin 22** |
| 28 | VCC | VCC | **`+5VP`**: U13 pin 14 |

- [ ] Check: each wire beeps to its end; pad 21 ↔ Z80 pin 22 and pad 24 ↔ U13 pin 14 must **not** beep.

`/OE` stays on the '139 output as it is; the `CC784-4` also gates it with the power-fail signal, which changes nothing while `/CE` is gated.

### 2. Power-fail detect and reset

- [ ] Optional, belt and braces: a reset supervisor, a 3-pin open-drain part with a ~4.4–4.5 V threshold (DS1233-5, MCP120-450) from Z80 pin 26 (`/RESET`) to GND, powered from +5 V, in parallel with R3/C18. It halts the Z80 below the threshold, before the garbage phase measured in [§11](#11-the-cc784-3a-board-cc710-h), and holds it for 150–350 ms after power returns. Check: pin 26 low for a moment at every power-on, high while running.

The essential part is the `CC784-4`'s lockout, watching the regulated 5 V instead of the unregulated rail. It reuses this board's detect footprints: on the `CC784-3A` the chain is 9 V, R25 (1 k), D1 (cathode toward R25), then the detect node with R10 (4.7 k), C20 and D2 to ground and a track to U13 pin 5. The `CC784-4` feeds the same series pair from 5 V, with R25 at 220 Ω, R10 at 1 k and a 4.3 V zener, and sends the node to Q9's base instead. It also swaps R25 and D1 on the board, which makes no difference electrically: they are in series. U13's third gate (pins 8, 9, 10), unused here with its inputs on `+5VP`, becomes the inverter after Q9.

- [ ] Cut the track from the 9 V rail to R25 and wire that end of R25 to **+5 V** (the 7805 output, not `+5VP`).
- [ ] D1: replace with a **4.3 V** zener, 0.5 W glass (DO-35), e.g. 1N749A or BZX79-C4V3, cathode toward R25 as before. The `CC784-4`'s D1 is marked `4V3` [H].
- [ ] R10: replace 4.7 k with **1 k**. It sets the current Q9 needs before it turns on (about 0.65 mA), and with it the trip point.
- [ ] R25: replace 1 k with **220 Ω**, as on the `CC784-4`. At 0.65 mA a 1 k drops another 0.65 V, which puts the trip point above 5 V: Q9 would never turn on and the RAM would stay locked out.
- [ ] Remove C20 and D2, as on the `CC784-4`.
- [ ] Cut the track at U13 pin 5 (top side; it emerges from under the IC between pins 6 and 7), and the track to U13 pins 9 and 10 (`+5VP`, bottom side; between a leg of C5 and pin 9).
- [ ] 100 k (the `CC784-4`'s R33) across that second cut, from the `+5VP` track to U13 pins 9 and 10, on the bottom side where the two sit side by side. It pulls Q9's collector high when Q9 turns off on power fail; without it the gate input floats and the lockout is unreliable.
- [ ] Q9 (BC548, or a 2N3904, whose pinout is reversed: E-B-C instead of C-B-E): mount emitter lead into GND via by U17 pin 7; base to the detect node (D1's anode, the R10 end, whose track runs between U17 pins 5 and 6, next to the GND via); use Kynar wire to tie collector to U13 pins 9 and 10 (which will see `+5VP` through 100 k).
- [ ] U13 pin 8 to U13 pin 5, and to RAM pin 26 if a 6264 is fitted (step 1).
- [ ] The trip point: at this sub-milliamp current the zener conducts a few hundred millivolts below its rating, so Q9 releases somewhere around 4.6–4.8 V on the 5 V rail [M]: the RAM is locked out as soon as the supply sags. Check afterwards that the 5 V rail sits above that with the sign warm, or the store will refuse writes.
- [ ] Check before inserting chips: with power on, U13 pin 8 reads about 5 V; with the mains off and the 5 V rail below the trip point, it falls to 0 V while `+5VP` stays up.

### 3. Host cable

No board change: a 10-pin IDC socket on SK1 to a DB9 male, to match the `CC784-4`'s connector:

| SK1 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| DB9 | 9 | 5 | 3 | 4 | 7 | 8 | 6 | 1 | 2 | — |

With a CC784 serial cable on it (the factory crossover with its 2–5 short) the stock CC710 boots into terminal mode and talks both ways [H]. The same wiring in reverse, IDC socket to DB9 female, lets the CC100 keypad drive a CC784NET or a patched CC784NIR [H on the patched NIR].

### 4. ROM

Unmodified, the hardware can only read 16 KB of ROM ([§2](#2-memory-and-io-decoding-h--from-the-schematic)), so a 27128 holds any of the firmware images: the NET's as it is, the NIR's from the lower half of its 32 KB dump, and the patched build's 16 KB bank image (`cc784nir_bank.bin`; it should boot without the bank register, unverified on hardware). Over-the-air updates need the AT28C256's two banks:

- [ ] AT28C256: [CC784_upgrades.md §2](CC784_upgrades.md#2-eeprom-and-bank-register), which reuses R32's footprint for the `/WE` pull-up (10 k).
- [ ] A 27C256 instead of the 27128: remove R32 and wire **Z80 pin 4** to ROM pin 27, which must be low on a 27C256 ([§8](#8-factory-bodge-wires-h--from-the-schematic)).

### 5. Timebase and IR

Exactly as for a `CC784NET`: [CC784_upgrades.md §4](CC784_upgrades.md#4-net-to-nir). U18 (CD74HC14) is fitted with two gates in use; the IR path needs gate pins 5 and 6 and a receiver header. That includes buffering the panel column clock (SK2 pin 11) through U18's gates at pins 8–11, which are unused on this board.

- [ ] A board with the original CC784's `/M1` bodge ([§13](#13-the-original-cc784s-board-h)) has U18 pins 5 and 6 taken. Move it to pins 13 and 12 first, where the `CC784-4` has it: U17 pins 3 and 4 to **U18 pin 13**, U17 pin 9 to **U18 pin 12**. Check: U18 pin 5 ↔ U17 pin 3 and U18 pin 6 ↔ U17 pin 9 must **not** beep. 10 min.

### The panel

Converting the board does not convert the CC710's display. The CC784 firmware shifts 86 columns per row; on the CC710's 60-stage panel the first 26 fall off the far end, so only the right-hand part of each frame shows [M]. The patched firmware's CC710 build shifts 60 and strobes the '595s after each row ([CC784_patched.md](CC784_patched.md#2-patches), patch 37) [H].

### Checks after conversion — 10 min

- [ ] Power up with the NET firmware: the demo scrolls; [CC784_upgrades.md §5](CC784_upgrades.md#5-checks-after-any-upgrade--5-min) for the rest.
- [ ] Load a short message, then switch the mains off and on twenty times: the message must survive every cycle. The fault is intermittent, so more cycles make a pass more convincing. This is the test the stock lockout fails.

## 13. The original CC784's board [H]

From photos and inspection of the board, matched against the KiCad capture in [hardware/CC784-3A/](hardware/CC784-3A/). A second `CC784-3A` board, populated as the CC710's ([§11](#11-the-cc784-3a-board-cc710-h)): ST Z8400AB1, HM3-6116L-5 in the 24-pin socket, SK1 header, 1990 date codes. Differences:

- ROM labelled `CC784-9E-USA ©1990 COLOR CELLS INT'L`; the ID inside it is `9g` ([firmware notes §16](CC784_firmware.md#16-the-original-cc784-firmware-h--from-a-rom-dump-id-9g)).
- BZ1 is fitted: a round magnetic buzzer of the size the silk is drawn for.
- The sign arrived new and sealed in its box, never used, so everything on the board is as it left the factory.
- Its NiCd had leaked like the others ([§7](#7-power--battery)), in the sealed box, and is removed.
- C3, the 1 µF tantalum on the 7805's input, failed short at its first power-up. C3, C4 and the bulk caps C1/C2 are replaced with electrolytics; C18, the reset capacitor, is still the original, since R3 (10 k) limits any fault there to 0.5 mA [H].
- Three factory modifications the CC710's board does not have, below. No other wires or cut tracks found.

**Delayed `/M1` into the I/O decoder.** U17 pin 9 is cut from Z80 pin 27 (`/M1`) and wired to U18 pin 6; U17 pins 3 and 4 are wired to U18 pin 5.

- On the bare `CC784-3A`, U17's gate at pins 8–10 enables U4A with `/M1·IORQ`: `/M1` straight from the Z80 on pin 9, `IORQ` from U11 (HC04) on pin 10.
- With the bodge, pin 9 gets `/M1` through U17's first gate (pins 1–3, `M1`) and U18's pins 5 → 6: two inversions, the same polarity, two gate delays later.
- The `CC784-4` has the same circuit in copper on U18's other spare gate: U17 pins 3 and 4 to U18 pin 13, U18 pin 12 to U17 pin 9.
- Why [M]: at the end of an interrupt acknowledge `/M1` and `/IORQ` rise together, but `IORQ` comes through U11's inverter. With `/M1` direct, U4A is enabled for a few nanoseconds: a stray I/O strobe in whichever group A7/A6 select, a panel column clock, the port `80` strobe or a color latch write (whose Q7 is the beeper). Delaying `/M1` closes that window.

**100 µF on the beeper drive.** An electrolytic from U9 pin 19 (Q7, the beeper bit) to GND, soldered at R27 (Q8's base resistor) and U4 pin 8. Not on the `CC784-4`.

- Why [M]: it slows Q7's edges to milliseconds, so a microsecond pulse on Q7 never turns Q8 on, while the firmware's 115 ms beep still sounds. Probably the first fix for the same stray strobes, heard as beeper clicks. It loads U9's output heavily.
- For the conversion ([§12](#12-converting-a-cc784-3a-board-to-a-cc784-4)) it can stay; the `CC784-4` does without it. The `/M1` bodge must move to U18 pins 13 and 12 before the IR goes on 5 and 6 ([§12](#12-converting-a-cc784-3a-board-to-a-cc784-4), step 5).

## 14. The four boards side by side [H — from photos]

From photos of each board and its rating label. Chip dates are the usual YYWW codes.

| | Original CC784 | CC710 | CC784NET | CC784NIR |
|---|---|---|---|---|
| Board | `CC784-3A` | `CC784-3A` | `CC784-4` | `CC784-4` |
| Chip dates | 8844 (RAM), 9005–9026 | 8840 (RAM), 9009–9027 | 9119–9204; TIP125s 9214 | 9150 (RAM), 9235–9246 |
| ROM label | `CC784-9E-USA ©1990 COLOR CELLS INT'L` | `CC710-9L-USA COPYRIGHT 1990 COLOR CELLS INT'L` | `CC784NET#167`, `#6288` (the line between is unclear) | none; a windowed ST M27C256B |
| CPU | ST Z8400AB1, `29017` | ST Z8400AB1, `29017` | ST Z80 under a paper sticker | Zilog Z0840008PSC, `9246` |
| RAM | MHS HM3-6116L-5 | MHS HM3-6116L-5 | Hyundai HY6264ALP-10, `9144T` | Hyundai HY6264ALP-10, `9150A` |
| Battery | blue 3-cell, `060` | blue 3-cell, `060` | GP 3.6 V 60 mAh | Varta 3.6 V 70 mAh `3/V80H` |
| C1, C2 | Marcon CF-SE 4700 µF 16 V, `9014` | two axial 105 °C parts marked `8427` on bent leads | Orient 4700 µF 16 V | Orient 4700 µF 16 V |
| C3, C4, C18 | dipped tantalum | dipped tantalum | dipped tantalum | dipped tantalum |
| Beeper | BZ1 fitted | BZ1, Q8 and R27 empty as shipped (since fitted, [§11](#11-the-cc784-3a-board-cc710-h)) | BZ1 fitted | BZ1 fitted |
| Factory wires | `/M1` delay, 100 µF on U9 Q7 ([§13](#13-the-original-cc784s-board-h)) | none | the 6264 wires ([§8](#8-factory-bodge-wires-h--from-the-schematic)) | the 6264 wires, the column clock buffer, `/INT` and IR ([§8](#8-factory-bodge-wires-h--from-the-schematic)) |
| Rating label | `MODEL CC784`, "manufactured under licence from COLOUR CELLS INTERNATIONAL" | `MODEL CC710`, "… COLOR CELLS INTERNATIONAL LTD." | Color Cells "Innovative Sign Technology" logo, label part `784 NET-L01`, ©1992 | as the NET's, `784 NIR-L01`, ©1992 |
| Serial sticker | `CC784-9E-USA ©1990 COLOR CELLS INT'L`, `A23458` | `AB10235`, no other text | `©1992 COLOR CELLS INT'L`, `A00634` | `©1993 COLOR CELLS INT'L`, `A 09119` |
| Keyboard named | CC100 | CC100 | CC110 NET | CC110 NET |
| Patents listed | US 4162493, Australia 493435, pending PJ6641 | plus Japan 1136058 | plus Canada 1082825 | as the NET's |

- **The two `CC784-3A` boards are from one build period.** They share exact lots: the LS00s (`XXFU9013`), the LS273s (`XXEM9020`), the LS139 (`KKCG9020`), the 74145 (`9022BS`), the HC14 (`H 9014`) and the Z80 (`29017`). Their newest chips are a week apart (`9026`, `9027`). So the `/M1` and beeper bodges were not a later board revision: one board of the batch got them and the other did not.
- **The CC710 shipped without a beeper driver,** and both its bodge targets concern the beeper path (U9's Q7) or stray strobes the beeper would make audible. That may be why it went without [M].
- **Every board has dipped tantalums at C3, C4 and C18.** The original CC784's C3 failed short and burned on its first power-up ([§13](#13-the-original-cc784s-board-h)): replace C3 and C4 before powering any of these.
- **The rating labels** all read AC 9 V, 30 W nominal, 40 W max, 0–35 °C, the CC710's too despite its shorter panel. The two `CC784-3A` signs name the CC100 keyboard (PCB `CC-KP1`, [§6](#6-connectors)); the two `CC784-4` signs name a "CC110 NET", not seen here. The NIR's label names it as well, so the NET and NIR probably shared label text [M].
- **The patent list grows by one country per sign** along the firmware's lineage: US and Australia, then Japan, then Canada ([firmware notes §1](CC784_firmware.md#1-lineage-of-the-stock-firmware-m--from-the-four-roms-their-labels-and-the-boards)).
- **Serial numbers:** the `CC784-4` signs' are low (`A00634` on a 1992 NET, `A 09119` on a 1993 NIR) next to the original CC784's `A23458` from 1990, so the numbering restarted with the new board or each model had its own series [L]. The original CC784's serial sticker repeats its ROM label, `CC784-9E-USA`.
