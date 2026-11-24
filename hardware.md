# CC784 family hardware — reference notes and open questions

The Color Cells / Innovative Sign Technology signs covered here run on two revisions of one controller board:

- **`CC784-3A`** (silk `CC784-3` on the front, `COLOR CELLS CC784-3A` on the back): the original CC784 and the CC710, 1990.
- **`CC784-4`** (silk `CC784-4`, rear `COLOR CELLS CC784-4`): the CC784NET ("NET", wired keypad or PC) and the CC784NIR ("NIR", infrared remote), 1991–1993.

Both are double-sided, through-hole only. §1 sets the four boards side by side; §2 covers what they share, with the differences called out where they occur; §3 and §4 cover what is particular to each revision; §5 converts a `CC784-3A` into a `CC784-4`.

Confidence key as in the firmware notes: **[H]** verified, **[M]** inferred, **[L]** hypothesis.

---

## 1. The four boards side by side [H — from photos]

From photos of each board and its rating label. Chip dates are the usual YYWW codes.

| | Original CC784 | CC710 | CC784NET | CC784NIR |
|---|---|---|---|---|
| Board | `CC784-3A` | `CC784-3A` | `CC784-4` | `CC784-4` |
| Panel | two 7×42, 74HC595 | 7×42 + 7×21, 74HC595 | two 7×42, 74LS164 | two 7×42, 74LS164 |
| Chip dates | 8844 (RAM), 9005–9026 | 8840 (RAM), 9009–9027 | 9119–9204; TIP125s 9214 | 9150 (RAM), 9235–9246 |
| ROM label | `CC784-9E-USA ©1990 COLOR CELLS INT'L` | `CC710-9L-USA COPYRIGHT 1990 COLOR CELLS INT'L` | `CC784NET#167`, `#6288` (the line between is unclear) | lost; an ST M27C256B |
| CPU | ST Z8400AB1, `29017` | ST Z8400AB1, `29017` | ST Z8400AB1, `29035` | Zilog Z0840008PSC, `9246` |
| RAM | MHS HM3-6116L-5 | MHS HM3-6116L-5 | Hyundai HY6264ALP-10, `9144T` | Hyundai HY6264ALP-10, `9150A` |
| Battery | blue 3-cell, `060` | blue 3-cell, `060` | GP 3.6 V 60 mAh | Varta 3.6 V 70 mAh `3/V80H` |
| C1, C2 | Marcon CF-SE 4700 µF 16 V, `9014` | two axial 105 °C parts marked `8427` on bent leads | Orient 4700 µF 16 V | Orient 4700 µF 16 V |
| C3, C4, C18 | dipped tantalum | dipped tantalum | dipped tantalum | dipped tantalum |
| Beeper | BZ1 fitted | BZ1, Q8 and R27 empty as shipped (since fitted, [§4.2](#42-beeper)) | BZ1 fitted | BZ1 fitted |
| Factory wires | `/M1` delay, 100 µF on U9 Q7 ([§4.4](#44-the-original-cc784s-board-h)) | none | the 6264 wires ([§3.2](#32-factory-bodge-wires-h--from-the-schematic)) | the 6264 wires, A14 to the ROM, the column clock buffer, `/INT` and IR ([§3.2](#32-factory-bodge-wires-h--from-the-schematic)) |
| Rating label | `MODEL CC784`, "manufactured under licence from COLOUR CELLS INTERNATIONAL" | `MODEL CC710`, "… COLOR CELLS INTERNATIONAL LTD." | Color Cells "Innovative Sign Technology" logo, label part `784 NET-L01`, ©1992 | as the NET's, `784 NIR-L01`, ©1992 |
| Serial sticker | `CC784-9E-USA ©1990 COLOR CELLS INT'L`, `A23458` | `AB10235`, no other text | `©1992 COLOR CELLS INT'L`, `A00634` | `©1993 COLOR CELLS INT'L`, `A 09119` |
| Keyboard named | CC100 | CC100 | CC110 NET | CC110 NET |
| Patents listed | US 4162493, Australia 493435, pending PJ6641 | plus Japan 1136058 | plus Canada 1082825 | as the NET's |

- **The two `CC784-3A` boards are from one build period.** They share exact lots: the LS00s (`XXFU9013`), the LS273s (`XXEM9020`), the LS139 (`KKCG9020`), the 74145 (`9022BS`), the HC14 (`H 9014`) and the Z80 (`29017`). Their newest chips are a week apart (`9026`, `9027`). So the `/M1` and beeper bodges were not a later board revision: one board of the batch got them and the other did not.
- **The CC710 shipped without a beeper driver,** and both its bodge targets concern the beeper path (U9's Q7) or stray strobes the beeper would make audible. That may be why it went without [M], cost-cutting aside.
- **Every board has dipped tantalums at C3, C4 and C18.** The original CC784's C3 failed short and burned on its first power-up ([§4.4](#44-the-original-cc784s-board-h)): replace C3 and C4 before powering any of these.
- **The rating labels** all read AC 9 V, 30 W nominal, 40 W max, 0–35 °C, the CC710's too despite its shorter panel. The two `CC784-3A` signs name the CC100 keyboard and the two `CC784-4` signs the CC110 NET; the two keypads differ only in their connector ([§2.4](#24-host-port-serial-and-keypad-h)). The NIR's label is the NET's with the part number changed: it names a wired keypad that its stock firmware never scans.
- **The patent list grows by one country per sign** along the firmware's lineage: US and Australia, then Japan, then Canada ([firmware notes §1](firmware.md#1-lineage-of-the-stock-firmware-m--from-the-five-roms-their-labels-and-the-boards)).
- **Serial numbers:** the `CC784-4` signs' are low (`A00634` on a 1992 NET, `A 09119` on a 1993 NIR) next to the original CC784's `A23458` from 1990, so the numbering restarted with the new board or each model had its own series [L]. The original CC784's serial sticker repeats its ROM label, `CC784-9E-USA`.

## 2. Common design

Both revisions share the CPU, the decoding, the timebase circuit, the host port's signals, the display path and the power supply. Where a part or value differs, it is given for each.

### 2.1 Parts [H — from photos]

| Ref | Role | `CC784-3A` | `CC784-4` |
|---|---|---|---|
| U1 | CPU | ST Z8400AB1 (4 MHz Z80A) | NET: ST Z8400AB1; NIR: Zilog **Z0840008PSC** (8 MHz grade) |
| U2 | firmware ROM, a windowed UV-erasable EPROM on all four; only the lower 16 K addressed ([§2.2](#22-memory-and-io-decoding-h--from-the-schematic)) | 27128 | NET: 27128; NIR: ST **M27C256B-15F1** (32 K × 8, 150 ns) |
| U3 | RAM from `0x4000` | MHS HM3-6116L-5 (2 K × 8), 24-pin | Hyundai **HY6264ALP-10** (8 K × 8) in the 24-pin footprint ([§3.2](#32-factory-bodge-wires-h--from-the-schematic)) |
| U4 | 74LS139: U4B memory decode, U4A I/O decode ([§2.2](#22-memory-and-io-decoding-h--from-the-schematic)) | same | same |
| U5, U9 | 74LS273 ×2: U5 = `CTRL_LATCH` (`0x8000`), U9 = color latch ([§2.5](#25-display-drive-and-panels-h--from-the-schematic-and-the-firmware)) | same | same |
| U6 | BCD→decimal, open collector: row select → TR1–TR7 | SN74145 | **74LS145** |
| U7, U8 | 74LS151 ×2: row-bit selector and color selector for the panel data | same | same |
| U10, U16, U17 | 74LS00 ×3, glue | same | same |
| U11 | 74HC04, oscillator, with the crystal | 4.000 MHz | NET: 4.000 MHz; NIR: 8.000 MHz |
| U12 | 74LS244: serial outputs, and the input port read by `IN 0xC0` ([§2.4](#24-host-port-serial-and-keypad-h)) | same | same |
| U13 | 74HC132: RAM `/CE` gating and the power-fail lockout, on the battery rail ([§2.7](#27-power-and-battery)) | same | same |
| U14 | **74HC4020** (14-stage ripple counter): timebase divider and watchdog ([§2.3](#23-timebase-h)) | same | same |
| U15 | 7805 (MC7805C, MC7805CT, LM340T-5): 5 V regulator, on a heatsink | same | same |
| U18 | CD74HC14 | two gates in use | NIR: also IR conditioning and the column clock buffer ([§3.2](#32-factory-bodge-wires-h--from-the-schematic)) |
| U19 | **74LS164**: first stage of the column shift chain ([§2.5](#25-display-drive-and-panels-h--from-the-schematic-and-the-firmware)) | same | same (a GoldStar GD74LS164 on the NIR) |
| TR1–TR7 | TIP125 (PNP Darlington): LED row drivers | same | same |
| Q8 | BC548: beeper driver | empty on the CC710 as shipped | same |
| Q9 | BC548: power-fail detector ([§2.7](#27-power-and-battery)) | not on this board | fitted (silk `TR9`), with R33 |
| D5 | bridge rectifier, on the aluminum heatsink by U15; the part and heatsink cover its silk | same | same |
| C1, C2 | 4700 µF 16 V bulk filter ([§2.7](#27-power-and-battery)) | same | same |
| R4, D3 | battery charge/discharge path and the `+5VP` rail ([§2.7](#27-power-and-battery)) | same | same |
| SK2 | 14-pin connector to the display panel ([§2.6](#26-connectors)) | same | same |
| — | host connector ([§2.4](#24-host-port-serial-and-keypad-h)) | SK1, 2×5 header | DB9 male |
| — | "NICAD BATTERY" footprint: RAM backup ([§2.7](#27-power-and-battery)) | same | same |
| — | 3-pin IR receiver header (right edge, glued) | none | NIR only ([§2.6](#26-connectors)) |
| — | barrel jack, 9 V **AC** in (supplied PSU: 9 V AC, 4.2 A transformer) | SK3 | fitted |
| BZ1 | beeper (`0x07` command) | empty on the CC710 as shipped | same |

### 2.2 Memory and I/O decoding [H — from the schematic]

U4 (74LS139) does both halves:

- **Memory (U4B, enabled by `/MREQ`, inputs A15/A14):** `2Y0` ROM `/CE` and `/OE` (`0x0000–0x3FFF`); `2Y1` → U13 → RAM `/CE` (`0x4000–0x7FFF`, gated by the power-fail lockout, [§2.7](#27-power-and-battery)); `2Y2` clocks U5, the control latch (`0x8000`); `2Y3` (`0xC000–0xFFFF`) is unused as shipped; the EEPROM upgrade clocks its bank register from it ([upgrades.md §2](upgrades.md#2-eeprom-and-bank-register)).
- **I/O (U4A, enabled by `IORQ·/M1` so interrupt acknowledges are excluded, inputs A7/A6):** `1Y0` (`0x00–0x3F`) unused; `1Y1` = the `0x40` group: clocks the on-board '164 (U19) and the panel's column clock (SK2 pin 11; through U18 on the NIR), and, gated with D7 in U10, clocks U9, the color latch; `1Y2` = `0x80`, the strobe (SK2 pin 12); `1Y3` = `0xC0`, enables the '244's input half onto the bus. Within the `0x40` group the Z80's low address bits are used as data: A0–A2 select the row bit ([§2.5](#25-display-drive-and-panels-h--from-the-schematic-and-the-firmware)), A3 the intensity pass, A5 the beeper, and A8 — the `B` register during `OTIR` — red or green.

The RAM select covers `0x4000–0x7FFF`, so the `CC784-3A`'s 2 K 6116 appears there eight times and the `CC784-4`'s 8 K 6264 twice.

#### ROM socket wiring [H — traced on the board]

- **Pins 1 (VPP) and 28 (VCC) are both on the 5 V net**, joined by a visible trace beside the socket and a second under it. Nothing on the board can drive VPP, so any substitute that expects an address line on pin 1 has to have that pin lifted.
- **The layout was cut for a 2764/27128**, where pin 27 is `/PGM` and gets tied high: R32, a footprint from pin 27 to 5 V, carries a 3.3 k pull-up on the boards with a 27128 (both `CC784-3A` boards and the NET). The same footprint takes the `/WE` pull-up of the EEPROM upgrade ([upgrades.md §2](upgrades.md#2-eeprom-and-bank-register)).
- **On the NIR, A14 reaches pin 27 through a factory bodge wire from Z80 pin 4**, and R32 is empty. On its 27C256 that pin is A14 and must be low for the chip to read its lower half; A14 is always 0 whenever the ROM is selected, so the wire simply holds it low.
- ROM `/CE` is only asserted when A14 = 0, so the chip is permanently confined to its lower 16 K — which is why the upper half of the NIR's dump is `0xFF`, and why the NIR firmware runs from a 27128 just as well. Only the EEPROM's two OTA banks use the upper half, through the bank register on its pin 1 ([upgrades.md §2](upgrades.md#2-eeprom-and-bank-register)).

Substitutes, given the above:
- **W27C512** — pin 1 is A15 and sits on 5 V, so the upper half runs; program the 32 K image twice.
- **AT28C256 / 28C64** — pin 1 is A14 and pin 27 is `/WE`, both swapped relative to the 27C256. Straight substitution is destructive: board A14 lands on `/WE` and goes low on every ROM fetch. Two bodges make it exact: lift **pin 27** and jumper it to VCC (writes permanently disabled), and lift **pin 1** and run it to A14 (Z80 pin 4). With both done the part is electrically a 27C256 and takes the ordinary 32 K image unchanged — `/CE` only asserts when A14 = 0, so nothing above the chip's own `0x3FFF` is ever addressed. Skipping the pin 1 bodge leaves A14 stuck high on the VPP net; that needs the low 16 K duplicated into both halves instead.

### 2.3 Timebase [H]

The crystal → HC04 oscillator → the Z80 clock and the HC4020 (U14). The counter is **reset by every interrupt acknowledge** (`M1·IORQ`, U17 → U11 → pin 11), so each interrupt comes a fixed count after the last one was taken.

- **As designed (both `CC784-3A` boards and the NET):** 4 MHz crystal, and U10 NANDs Q11 with Q12 (pins 15 and 1), so `/INT` asserts 3072 clocks = 768 µs after the acknowledge: 1302 Hz, the rate the stock firmware of these three runs its serial engines and row scan at directly. The `CC784-3A`'s serial bit tables match the NET's byte for byte, which confirms the rate.
- **The NIR:** 8 MHz crystal, and U10 pin 12 cut from Q12 and bridged to pin 13, so the gate inverts Q11 alone ([§3.2](#32-factory-bodge-wires-h--from-the-schematic)): `/INT` asserts 1024 clocks = 128 µs after the acknowledge, the 7812.5 Hz tick its IR decoder needs. Its firmware divides by 6 to get the same 1302 Hz for everything else, and its per-tick work does not fit 4 MHz ([firmware notes §3](firmware.md#3-execution-architecture-h)).
- **Watchdog:** Q13 goes high 4096 clocks after the last acknowledge (1 ms at 4 MHz, 512 µs at 8 MHz) and, inverted by U17, **clears U5**, the control latch, for as long again: it blanks the rows and parks TX whenever the firmware stops servicing interrupts, for instance for the whole of `pkt_process`. It is why the OTA bank register is a separate chip ([ota.md §1](ota.md#1-hardware)).

A NET board needs both the crystal and the bodge before it can run the NIR firmware ([upgrades.md §4](upgrades.md#4-net-to-nir)). The Z8400A is a 4 MHz grade part, yet all three tried here ran at 8 MHz for about a month (before being replaced by Z84C0020s); that is just three samples outside their rating, so be prepared to swap in a Z84C0008 (or better) in case yours is not stable in this configuration.

**NMI:** 60 Hz from the AC input via a zero-cross detector (`NMI_PER_SEC = 60`), U18 pin 4 on the `CC784-4`. With a DC supply the clock would not run; the supplied PSU is AC, so it does. The IR and clock add-in board ([hardware/CC784NIR_IR+Clock/](hardware/CC784NIR_IR+Clock/)) cuts that trace and puts a 74HC151 between U18 and the Z80: input 0 is the mains pulse, input 1 a 64 Hz square wave from an HC4060 on a 32.768 kHz crystal, and the select is the bank register '273's Q7 (pin 19), its top bit (Q1 and Q2 stay free for a larger EEPROM). The patched firmware picks the crystal when no mains cycle arrives at boot ([patched.md](patched.md#2-patches), patch 31). The board also carries the TSOP38230 receiver; its 7-pin connector is GND, AC_IN, CLOCK_OUT, +5 V, CLOCK_SEL, IR_RX, GND. The signs studied here all carry one now.

### 2.4 Host port: serial and keypad [H]

The `CC784-4` brings the host port out on a DB9; the `CC784-3A` brings the same seven signals out on SK1, a 2×5 header (traced on the board). The DB9 numbers are used throughout these notes.

| DB9 | SK1 | Dir | Serial role | Keypad role | Path |
|---|---|---|---|---|---|
| 1 | 8 | in | — | column code bit 1 | R8 pull-up → U12 → `PORT_IN` bit 1; on the NIR shares the net with the IR receiver output (factory bodge, [§3.2](#32-factory-bodge-wires-h--from-the-schematic)) unless the receiver is moved to bit 4 ([upgrades.md §8](upgrades.md#8-ir-off-the-db9)) |
| 2 | 9 | in | PC detect on the NET firmware: the factory cable ties it to pin 5 | column code bit 0 | R9 pull-up → U12 → `PORT_IN` bit 0 |
| 3 | 3 | out | **TX** (ACK/NAK, query replies) | row select bit 0 | U12 pin 18 (1Y1) ← `CTRL_LATCH` bit 4 |
| 4 | 4 | out | — | row select bit 1 | U12 pin 16 (1Y2) ← latch bit 5; the NIR firmware never drives it |
| 5 | 2 | — | GND | GND | — |
| 6 | 7 | in | — | column code bit 2 | R6 pull-up → U12 → `PORT_IN` bit 2; not read by the NIR firmware |
| 7 | 5 | out | — | row select bit 2 | U12 pin 14 (1Y3) ← latch bit 6; the NIR firmware never drives it |
| 8 | 6 | in | **RX** — the only real RS-232 receiver on the board | key pressed, active low | R30 270 Ω → D8/D9 clamp → R7 pull-up → U12 → `PORT_IN` bit 3 |
| 9 | 1 | out | +5 V | +5 V | R31 10 Ω from +5 V |
| — | 10 | — | unused | — | — |

The pull-ups R6–R9 are 3.9 k on the `CC784-3A`, 3.3 k on the `CC784-4`.

**Serial.** The factory cable is the crossover: sign 3 → PC 2, **sign 8 → PC 3**, and sign 2 and 5 → PC 5. Levels: TTL out of the LS244 on the outputs; pin 8 is the one input with a proper RS-232 clamp (negative swing shunted by D9, so bit 3 reads 1 during space). Polarity as the firmware sees it: `PORT_IN` bit 3 = 1 during space; `CTRL_LATCH` bit 4 = 1 drives space. 300 baud, 8 data, no parity; sign checks 1 stop bit, sends ~2. Pins 3, 4 and 7 are bare LS244 outputs with no protection: a host whose RS-232 TX lands on pin 3 (TX and RX crossed) holds it below ground at the transmitter's idle level and upsets the board's logic, and the sign crashes at random after seconds to minutes, with steady supply rails and no reply to frames. A sign that runs with the cable unplugged at the host end but freezes or blanks once it is plugged in has its TX and RX crossed.

Working setups (both verified with live ACKs): USB-RS232 adapter + crossover; [ESPHome serial proxy](https://esphome.io/components/serial_proxy/) via `cc784_esphome.py` (aioesphomeapi 46.4.x). A MAX3232 is the faithful interface. 3.3 V logic works too: the ESP32-C6 dongles ([ideas.md §9](ideas.md#9-dongle-follow-ups)) drive pin 8 from an open-drain buffer with the transmit inverted in software and read pin 3 through a Schmitt inverter [H]. On a `CC784-3A`, a 10-pin IDC socket to a DB9 male ([§5, step 3](#step-3-host-cable)) takes the same cable.

**The CC710's roles** differ, from [firmware notes §15](firmware.md#15-the-cc710-firmware-h--from-a-rom-dump-id-710):

| DB9 | SK1 | CC710 serial and boot probe |
|---|---|---|
| 3 | 3 | TX |
| 4 | 4 | probe clock; "ready" output in serial modes |
| 7 | 5 | probe data out |
| 8 | 6 | RX |
| 6 | 7 | must be high for TX to start |
| 1 | 8 | must be high for TX to start and for RX to sample; low at power-up in keypad mode clears the store |
| 2 | 9 | probe sample |

**Keypad.** The stock firmware of the original CC784, the CC710 and the NET scans a keypad over the seven signals [H — from the ROMs, see [firmware notes §14](firmware.md#14-the-cc784net-firmware-h--from-a-rom-dump-78409n1401920145)]. The NIR's stock firmware does not; the patched build does, on either board.

| Signal | DB9 | Firmware side |
|---|---|---|
| row select, 3 bits (decoded to 8 rows in the keypad) | 3, 4, 7 | `CTRL_LATCH` bits 4–6 |
| column code, 3 bits (encoded from 8 columns in the keypad) | 2, 1, 6 | `PORT_IN` bits 0–2 |
| key pressed, active low | 8 | `PORT_IN` bit 3 |

**The keypads [H].** The CC100 (PCB `CC-KP1`, on a 10-pin IDC plug, named on the `CC784-3A` signs' labels) and the CC110 NET (on a DB9, named on the `CC784-4` signs') differ only in the connector; both work on either sign through an adapter. Both have 62 keys, as the remote does. The CC100 has an MC74HC138 decoding the three row-select bits into eight row lines and an SN74LS148 priority encoder turning the eight column lines (pulled up by RN1) into the 3-bit column code, its GS output being the active-low key-pressed line. With no key pressed the '148 outputs are all high, so the column bits and the key-pressed line idle high: `PORT_IN` bit 0 reads 1 at boot (keypad mode) and bit 1 reads 1 (no boot clear). The '148 outputs are active low, so the column code the firmware reads is the inverted column number; `keypad_scan`'s key codes already include that.

Key code = row × 8 + column (`keypad_scan`, identical in the NET and NIR ROMs; key 0 is reported as `0x1E`, which is why the charsets hold `K` at both `0x00` and `0x1E`). The code indexes the `CHARSET_*` tables directly; the NIR's `IR_KEY_TABLE` converts a remote key number into this code, so the remote and the keypad share one editor. STOP/START is code `0x35` (row 6, column 5), SHIFT is `0x19` (row 3, column 1).

**PC or keypad?** The NET firmware decides at boot: it clocks a pattern out on pins 4 and 7 and samples pin 2; pin 2 low (the factory cable's 2–5 short) means serial, anything else means keypad, and in keypad mode the serial engines never run. The NIR firmware skips the test and never calls `keypad_scan`; the patched build drops the test and switches between keypad and serial by itself. The CC710's three-way probe is in [firmware notes §15](firmware.md#15-the-cc710-firmware-h--from-a-rom-dump-id-710).

### 2.5 Display drive and panels [H — from the schematic and the firmware]

- **Row select:** U5 Q0–Q3 → U6 ('145) → TR1–TR7 → SK2 pins 1–7. `ROW_INDEX` counts 0–6 once per frame, each row written twice (the two intensity passes) before it advances. Both the data-pass port and the latch code are `6 − ROW_INDEX`, except that the latch gets 7 instead of 0, so '145 output n carries frame-buffer bit n for n = 1–6 and output 7 carries bit 0, the top of every glyph; the scan runs bottom to top. The panel's rows are in SK2 pin order, top row on pin 1 [H — checked on the panel], so output 7 feeds pin 1 and outputs 1–6 feed pins 2–7. Code 0's output is unconnected and `0x0F` decodes to nothing, so both blank. U5 Q4 is serial TX, Q5/Q6 go to DB9 pins 4/7, Q7 is the 2.4 Hz FLASH clock.
- **Column data:** one `OTIR` per row, the same column bytes for every row (86 on the NIR firmware). U7 (LS151, data = D0–D7, select = A0–A2 = the row) picks the current row's bit out of each byte and feeds it to the on-board '164 and to U16, whose output is SK2 pin 10, the panel's serial data. Each row is written twice, to `0x40+row` then `0x48+row`, displayed for one and two ticks respectively ([firmware notes §8](firmware.md#8-rendering-h)): A3 selects intensity bit 0 or bit 1 of the color, giving four levels with 1:2 weights.
- **Color:** a byte with bit 7 set is latched by U9 instead of being shifted (U10 gates the `0x40`-group clock with D7). Bits 0–1 green and 2–3 red intensity, bit 4 FLASH, bits 5–6 background red/green (one bit each, so the four background names). U8 (LS151) takes U9's outputs: for a lit pixel it selects the foreground bit chosen by A3 (which intensity bit) and A8 (green or red, alternating per column because `B` counts down on A8–A15 during `OTIR`); for an unlit pixel it selects the background bit. The FLASH bit is ANDed with U5 Q7 in U10 to blank flashing columns on the off phase. U9 Q7 is latched from **A5**, not the data bus, and drives the beeper through Q8: `OUT (0x68+row)` beeps.
- **Background codes** `0x94–0x9F` draw no background (watched on the sign); the two hardware background bits make only `0x90–0x93` useful.

**The panels** [H — inspected]. Every panel PCB is 7 rows of red and green LEDs alternating per column (right-most green, left-most red), common anode per row from TR1–TR7 at the unregulated rail, cathodes per column into ULN2003As. SK2 lands on the right-hand PCB and the data shifts right to left. The column registers differ:

- **`CC784-4` signs: one 84-stage 74LS164 chain, no latch.** Two PCBs of 7 × 42, each with six '164s and six ULN2003As in one daisy chain. Each PCB's last '164 uses two outputs and passes the second on to the next PCB, so the six unused outputs are off the data path and the chain is exactly 84 stages. Of the firmware's 86 bits per row the first two sent fall off the left edge, the third is the left-most (red) column and the last is the right-most (green): `FRAMEBUF` reads left to right with a two-column margin at its start. The 85 zeros of `shift_chain_clear` flush the chain; the row is blanked while shifting and selected after. SK2 pin 12, the port `0x80` strobe, is not connected on these panels.
- **`CC784-3A` signs: 74HC595s latched by the port `0x80` strobe.** Both use the same 7 × 42 PCB: five 74HC595s latched by SK2 pin 12, then one 74HC164 for the two stages a 42-column PCB needs beyond them, so the chain passes to the next PCB without extra bits. The original CC784 has two, 7 × 84: of the 86 bits the firmware shifts per row the first two fall off the far end, as on the '164 panels [M]. The CC710 has one plus a 7 × 21 PCB with four unpopulated columns, 7 × 59 in all; its firmware shifts 60 bits per row: 42 on the first PCB, 18 on the second, the last into an unpopulated position.

Red or green text lights every other column; colors that blend the two (orange, yellow, lime) light both.

### 2.6 Connectors

**SK2 (14-pin, to the LED panel)**, counted from the board's bottom corner (traced on the board): pins 1–7 LED rows (from TR1–TR7); 8–9 regulated +5 V for the panel logic (the shift registers and ULN2003s); the LED current comes down the row pins from the unregulated rail; 10 column data, 11 column clock (port `0x40`); 12 the port `0x80` strobe, used only by the `CC784-3A` signs' '595 panels; 13–14 GND.

**Host connector:** the DB9 or SK1, [§2.4](#24-host-port-serial-and-keypad-h).

**IR header (NIR only):** 3 pins — 5 V, GND, signal — glued near U18, cabled to the receiver module on a small add-in board beside the display PCBs, behind a window in the front acrylic. Signal → HC14 → `PORT_IN` bit 1 (one inversion; active-low module output becomes 1 = burst). Verified by capture: module output idles high, bursts low, and lengthens each burst by ~250 µs relative to the transmitted half-bit (512 µs → ~780 µs). The IR and clock add-in board ([§2.3](#23-timebase-h)) replaces this receiver on the signs studied here.

**The IR carrier is 31.25 kHz nominal, 31.4 measured.** The remote is a Motorola MC14497P PCM transmitter on a 500 kHz ceramic resonator (board BP0300346B, 62 keys, two IR LEDs); the chip's carrier is the oscillator divided by 16 and its bit cell is 512 oscillator cycles, 1024 µs. Logic analyzer on its driver output: 31.88 µs period, 29 % duty, every burst 16 cycles = 510 µs, start burst 3.06 ms after the leader, frames every 89.8 ms. A 30 kHz receiver (TSOP4830/TSOP38230 class) is the closest replacement, 33 kHz the next; a 38 kHz part is 17 % off and chops the bursts.

### 2.7 Power and battery

9 V AC in → bridge rectifier D5 → C1/C2 → 7805 → 5 V logic; unregulated rail to the LED rows via SK2.

**Battery:** a 3-cell NiCd footprint. It charges **and** discharges through R4 (220 Ω) to `+5VP`, the rail behind D3 that feeds only the RAM and U13. The backed-up contents are the message store, address, sequence and clock digits — the clock does not *run* on battery, it only keeps its value.

**Power-fail lockout:** U13, an HC132 on `+5VP`, deselects the RAM when the supply fails, so a CPU running garbage as 5 V collapses cannot write to it. The two revisions detect the failure differently:

- **`CC784-4`:** Q9 watches the regulated 5 V through zener D1 (4.3 V, marked `4V3`) and R25 (220 Ω, with R10 1 k from base to ground) and, as it fails, turns off, letting R33 (100 k to `+5VP`) pull its collector high; U13 inverts that onto the `/CS2` net, which reaches the RAM twice: directly on the 6264's CS2 (pin 26), and through a second gate that NANDs it with the decoded RAM select to make `/CE` and `/OE`. Either path deselects the RAM. The 62256 upgrade turns pin 26 into A13 and removes the first path; the `/CE` path is untouched, so the deselect on power fail still happens, and the 62256 then sits in CMOS standby at about a microamp.
- **`CC784-3A`:** watches the **unregulated** rail: R25 1 k and zener D1 from the rail, R10 4.7 k to ground, zener D2 as a clamp, C20, straight into an HC132 Schmitt input that gates the RAM's `/CS`; no Q9 or R33. It trips far too late, and switching off can corrupt the store ([§4.3](#43-store-corruption-on-mains-power-cycles-h--measured-on-the-cc710)).

**Filter capacitors C1/C2.** The originals are 4700 µF 16 V. They carry the LED rows' ripple current, so replace them with 105 °C parts rated for at least 2 A of ripple at 120 Hz, at 25 V for margin over the unloaded rail. The signs studied here all carry a pair of Chemi-Con EKY-250ELL562MM40S (5600 µF 25 V, 18 × 40 mm) [H]; at that size they still hang off the board edge on their leads like the originals.

> [!WARNING]
> **The factory 3-cell NiCd pack leaks with age** and its electrolyte attacks the board around it. Every board studied here had leaking cells. Remove the pack and clean the area before doing anything else, even if the sign still works.

The replacement fitted on the signs studied here is a **5 F 5.5 V supercapacitor (ADCM-S05R5SA505RB)** in the existing charge path through R4, which needs no other change. Other options: a same-chemistry pack off-board, or a CR2032 **with a series diode** (a lithium primary must not be charged). With nothing on `+5VP` the sign boots with an empty store and its default address: 0 on the stock firmware, 1 on the patched.

## 3. The CC784-4 board: CC784NET and CC784NIR [H]

The later revision, captured in [hardware/CC784-4/](hardware/CC784-4/). Its differences from the `CC784-3A`, all covered in §2: an 8 K 6264 on factory wires in place of the 6116, a DB9 in place of SK1, the lockout on the regulated 5 V (Q9), the 74LS145 at U6, 3.3 k pull-ups, and the '164-chain panels.

### 3.1 NET and NIR

The same board, built two ways. The NET is the board as designed; the NIR is the NET with factory changes for its faster firmware and the remote. The NIR's chip dates are 9235–9246 (late 1992), its firmware dated 17-02-93.

| | CC784NET | CC784NIR |
|---|---|---|
| CPU and crystal | 4 MHz Z80, 4 MHz crystal | 8 MHz Z80, 8 MHz crystal |
| `/INT` | 1302 Hz from Q11·Q12 | 7812.5 Hz from Q11, by a factory bodge ([§2.3](#23-timebase-h)) |
| ROM | 27128, R32 pull-up on pin 27 | 27C256, A14 wired to pin 27, R32 empty ([§2.2](#22-memory-and-io-decoding-h--from-the-schematic)) |
| Panel column clock | straight from U4 | buffered through U18, by a factory bodge |
| IR | none | receiver header, U18 into `PORT_IN` bit 1, by a factory bodge ([§2.6](#26-connectors)) |
| Host port | keypad or PC, chosen at boot ([§2.4](#24-host-port-serial-and-keypad-h)) | PC only |

To turn a NET into a NIR, follow [upgrades.md §4](upgrades.md#4-net-to-nir). The NET boards lack the column clock buffer; the conversion adds it.

### 3.2 Factory bodge wires [H — from the schematic]

On both:

- The RAM footprint is a 24-pin socket. The 6264's pins 1, 2, 27 and 28 hang outside it, with the wires below soldered straight to the legs.
- Z80 pin 22 (`/WR`) → RAM pin 27 (`/WE`).
- U13 pin 8 (CS2) → RAM pin 26.

On the NIR only:

- Z80 pin 4 (A14) → ROM socket pin 27 (A14): the layout was cut for a 27128, which the NET still carries; on the NIR's 27C256 this pin must be low, and A14 is always 0 when the ROM is selected.
- The panel column clock is buffered: SK2 pin 11 is cut from the U4 pin 5 net (U11 pin 11, U19 pin 8), that net is wired to U18 pin 11, pins 10 and 9 are bridged, and U18 pin 8 drives SK2 pin 11. Two Schmitt inverters in series, so the clock keeps its polarity.
- U10 pin 12 cut from HC4020 pin 1 and bridged to pin 13: the `/INT` gate became an inverter on Q11.
- U18 pin 6 (IR, after the inverter) → the DB9 pin 1 net, which is how IR reaches `PORT_IN` bit 1.

## 4. The CC784-3A board: original CC784 and CC710 [H]

The earlier revision, from the photos and the KiCad capture in [hardware/CC784-3A/](hardware/CC784-3A/). No factory bodge wires on the CC710's; two modifications on the original CC784's ([§4.4](#44-the-original-cc784s-board-h)). Same Z80 (ST Z8400AB1), same decoding, same display path as the `CC784-4`.

### 4.1 Differences from the CC784-4

Beyond the parts in [§2.1](#21-parts-h--from-photos):

| | `CC784-3A` | `CC784-4` |
|---|---|---|
| Timebase | 4 MHz; U10 NANDs Q11 and Q12 of the HC4020 for `/INT`, and Q13 clears the control latch: the NET's original design, 1302 Hz and a 1 ms watchdog | 4 MHz NET as designed; 8 MHz with the Q11 bodge on the NIR |
| RAM | 2 KB 6116 in the 24-pin socket | 8 KB 6264, its overhanging pins on factory wires |
| RAM pad 21 | Z80 `/WR` (the 6116's `/WE`) | A11 (a 6264's pin 23); `/WE` reaches pin 27 by a factory wire ([§3.2](#32-factory-bodge-wires-h--from-the-schematic)) |
| Power fail | the unregulated rail into U13 ([§2.7](#27-power-and-battery)) | Q9 on the regulated 5 V, driving CS2 as well as gating `/CE` |
| Pull-ups R6–R9 | 3.9 k | 3.3 k |
| IR | none, no header | NIR only |

**Battery:** the "NICAD BATTERY" position (a small blue 3-cell can marked 060 on both boards) charges and discharges through R4 220 Ω to `+5VP`, as on the `CC784-4`.

### 4.2 Beeper

The CC710 shipped with BZ1, its driver Q8 (BC548) and Q8's base resistor R27 (1 k) all unpopulated; BZ1's silk is for a 25 mm part, leads 12.5 mm apart. The firmware drives it as a plain on/off level, Q8 switching the low side from U9's Q7, so it needs an **internally driven** 5 V buzzer; a bare transducer would only click. Polarity: + on +5 V and − on Q8's collector, as the board's silk and the schematics show. This CC710 now has Q8 and R27 fitted and a VCC MI-TH12-0531-RK (12 mm, 5 V, 3.1 kHz, 30 mA) on BZ1, its leads bent out to the footprint's pads; it fits and sounds [H]. Every CC784 shipped with the same buzzer at BZ1, a round magnetic part of the size the silk is drawn for.

### 4.3 Store corruption on mains power cycles [H — measured on the CC710]

Switching a `CC784-3A` sign off sometimes corrupts the message store, in any input mode. A channel loses its `03` terminator or marker, and the display runs into the free store area, which the boot repair has filled with `?` and leftover characters. The firmware does not cause it (five emulated boots in a row leave an intact store unchanged); a capture of the 5 V rail, `/RESET`, the unregulated rail, U13 pin 5 and the RAM's `/CE` and `/WE` shows where it happens:

- **Switch-off:** the 7805 leaves regulation about 97 ms after the mains goes, with the unregulated rail near 6.3 V. RAM writes carry on at the normal rate as the 5 V rail falls through 4.5 V, then jump about fifteenfold between 3.9 V and 3.5 V: the CPU is running garbage. U13 only stops selecting the RAM when its input falls to about 1.3 V, which happens with the 5 V rail at 3.5 V and the unregulated rail near 4.9 V, some 75 ms after 5 V started to fall. About 3000 stray writes land in that window. `/RESET` stays above 4.5 V throughout, held up by C18: nothing stops the CPU.
- **Switch-on** (after 29 s off): C18 had fully discharged, `/RESET` rose cleanly from 0 V, and the first RAM writes are the firmware's own, about 35 ms in. The power-on reset is not the problem.

So the lockout trips far too late: it watches the unregulated rail, whose ripple under LED load (8.5–9.2 V here) forces a threshold low enough that 5 V is already collapsing when it trips. Whether a given switch-off does damage is chance: it depends on what the CPU is running as its supply leaves spec, and on how long the window lasts (about 27 ms from 3.9 V to 3.5 V here), which shrinks the more LEDs are lit and draining C1/C2 at that moment. The fix is the `CC784-4`'s lockout on the regulated 5 V ([§5, step 2](#step-2-power-fail-detect-and-reset)). Fitted on the CC710's board without a reset supervisor, the store survived dozens of power cycles in a row [H].

### 4.4 The original CC784's board [H]

From photos and inspection of the board, matched against the KiCad capture. A second `CC784-3A` board, populated as the CC710's: ST Z8400AB1, HM3-6116L-5 in the 24-pin socket, SK1 header, 1990 date codes. Differences:

- ROM labelled `CC784-9E-USA ©1990 COLOR CELLS INT'L`; the ID inside it is `9g` ([firmware notes §16](firmware.md#16-the-original-cc784-firmware-h--from-a-rom-dump-id-9g)).
- The sign arrived new and sealed in its box, never used, so everything on the board is as it left the factory; **its NiCd pack had leaked all the same.**
- C3, the 1 µF tantalum on the 7805's input, failed short and flamed out within one minute of its first power-up. C3 and C4 are replaced with equivalent ceramics; the bulk caps C1/C2 are replaced with electrolytics; C18, the reset capacitor, is still the original, since R3 (10 k) limits any fault there to 0.5 mA [H].
- Two factory modifications the CC710's board does not have, below. No other wires or cut tracks found.

**Delayed `/M1` into the I/O decoder.** U17 pin 9 is cut from Z80 pin 27 (`/M1`) and wired to U18 pin 6; U17 pins 3 and 4 are wired to U18 pin 5.

- On the bare `CC784-3A`, U17's gate at pins 8–10 enables U4A with `/M1·IORQ`: `/M1` straight from the Z80 on pin 9, `IORQ` from U11 (HC04) on pin 10.
- With the bodge, pin 9 gets `/M1` through U17's first gate (pins 1–3, `M1`) and U18's pins 5 → 6: two inversions, the same polarity, two gate delays later.
- The `CC784-4` has the same circuit in copper on U18's other spare gate: U17 pins 3 and 4 to U18 pin 13, U18 pin 12 to U17 pin 9.
- Why [M]: at the end of an interrupt acknowledge `/M1` and `/IORQ` rise together, but `IORQ` comes through U11's inverter. With `/M1` direct, U4A is enabled for a few nanoseconds: a stray I/O strobe in whichever group A7/A6 select, a panel column clock, the port `80` strobe or a color latch write (whose Q7 is the beeper). Delaying `/M1` closes that window.

**100 µF on the beeper drive.** An electrolytic from U9 pin 19 (Q7, the beeper bit) to GND, soldered at R27 (Q8's base resistor) and U4 pin 8. Not on the `CC784-4`.

- Why [M]: it slows Q7's edges to milliseconds, so a microsecond pulse on Q7 never turns Q8 on, while the firmware's 115 ms beep still sounds. Probably the first fix for the same stray strobes, heard as beeper clicks. It loads U9's output heavily.
- For the conversion ([§5](#5-converting-a-cc784-3a-board-to-a-cc784-4)) it can stay; the `CC784-4` does without it. The `/M1` bodge must move to U18 pins 13 and 12 before the IR goes on 5 and 6 ([§5, step 5](#step-5-timebase-and-ir)).

## 5. Converting a CC784-3A board to a CC784-4

What it takes for a `CC784-3A` board to run the CC784 firmware (stock NET, stock NIR or the patched build) the way a `CC784-4` does. Derived from comparing the two KiCad captures. Verified on the CC710's board [H]: steps 1–4 with the stock CC710 firmware in both banks (step 1 with an AS6C62256, step 2's lockout without a supervisor, step 4 with the AT28C256 and bank register, [upgrades.md §2](upgrades.md#2-eeprom-and-bank-register)), then step 5 with a Z84C0020 in place of the Z8400A, after which it runs the patched firmware's CC710 build ([patched.md](patched.md#2-patches), patch 37). Done on the original CC784's board as well. The `CC784-3A` already has the NET's original timebase (4 MHz, `/INT` from Q11·Q12), so after this it is a `CC784NET` board and [upgrades.md](upgrades.md) applies from there.

| Step | Why | Parts | Time |
|---|---|---|---|
| 1. RAM | the CC784 firmware needs 8 KB at `4000` (32 KB for the patched build's larger store) | 6264, or AS6C62256 for the patched build; 28-pin socket | 30 min |
| 2. Power-fail detect and reset | the stock lockout releases the RAM to a CPU running garbage as 5 V collapses, corrupting the store ([§4.3](#43-store-corruption-on-mains-power-cycles-h--measured-on-the-cc710)) | BC548 (or 2N3904, mind the pinout), 100 k, 1 k, 220 Ω, 4.3 V zener; optionally a reset supervisor (DS1233-5 or MCP120-450) | 45 min |
| 3. Host cable | SK1 carries the DB9 signals on a 10-pin header | 10-pin IDC socket, DB9 male, ribbon | 15 min |
| 4. ROM | only for the EEPROM and over-the-air updates; every firmware image fits the 27128 | AT28C256, optionally | 10 min |
| 5. Timebase and IR | only for the NIR or patched firmware | as in [upgrades.md §4](upgrades.md#4-net-to-nir) | 20 min |

### Step 1: RAM

The footprint is for a 24-pin 6116, at positions 3–26 of a 28-pin chip; pins 1, 2, 27 and 28 overhang, as on the `CC784-4` ([§3.2](#32-factory-bodge-wires-h--from-the-schematic)). Two pads carry different signals on this board, so cut their tracks before fitting the new socket. Pad numbers below are the 24-pin footprint's; RAM pin numbers are the 28-pin chip's:

- [ ] Cut the track at pad 21: `/WR` from Z80 pin 22, the only other part on that net. RAM pin 23 (A11) lands here.
- [ ] Cut the track at pad 24: `+5VP`. RAM pin 26 lands here: CS2 on a 6264, A13 on a 62256.
- [ ] Fit a 28-pin socket in place of the 24-pin one, as in [upgrades.md §3](upgrades.md#3-ram), and wire:

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

### Step 2: Power-fail detect and reset

- [ ] Optional, belt and braces: a reset supervisor, a 3-pin open-drain part with a ~4.4–4.5 V threshold (DS1233-5, MCP120-450) from Z80 pin 26 (`/RESET`) to GND, powered from +5 V, in parallel with R3/C18. It halts the Z80 below the threshold, before the garbage phase measured in [§4.3](#43-store-corruption-on-mains-power-cycles-h--measured-on-the-cc710), and holds it for 150–350 ms after power returns. Check: pin 26 low for a moment at every power-on, high while running.

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
- [ ] Check the backup draw: with the mains off and the RAM fitted, the voltage across R4 must be a few millivolts. A volt or more (about 4.5 mA) means the RAM is still selected and drains the backup in under an hour: U13 pins 9 and 10 must sit at `+5VP`. A leaky Q9 holds them near 1 V; on one board studied here, a Q9 corroded by battery electrolyte did exactly that.

### Step 3: Host cable

No board change: a 10-pin IDC socket on SK1 to a DB9 male, to match the `CC784-4`'s connector:

| SK1 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| DB9 | 9 | 5 | 3 | 4 | 7 | 8 | 6 | 1 | 2 | — |

With a CC784 serial cable on it (the factory crossover with its 2–5 short) the stock CC710 boots into terminal mode and talks both ways [H]. The same wiring in reverse, IDC socket to DB9 female, lets the CC100 keypad drive a CC784NET or a patched CC784NIR [H on the patched NIR].

### Step 4: ROM

Unmodified, the hardware can only read 16 KB of ROM ([§2.2](#22-memory-and-io-decoding-h--from-the-schematic)), so a 27128 holds any of the firmware images: the NET's as it is, the NIR's from the lower half of its 32 KB dump, and the patched build's 16 KB bank image (`cc784nir_bank.bin`; it should boot without the bank register, unverified on hardware). Over-the-air updates need the AT28C256's two banks:

- [ ] AT28C256: [upgrades.md §2](upgrades.md#2-eeprom-and-bank-register), which reuses R32's footprint for the `/WE` pull-up (10 k).
- [ ] A 27C256 instead of the 27128: remove R32 and wire **Z80 pin 4** to ROM pin 27, which must be low on a 27C256 ([§2.2](#22-memory-and-io-decoding-h--from-the-schematic)).

### Step 5: Timebase and IR

Exactly as for a `CC784NET`: [upgrades.md §4](upgrades.md#4-net-to-nir). U18 (CD74HC14) is fitted with two gates in use; the IR path needs gate pins 5 and 6 and a receiver header. That includes buffering the panel column clock (SK2 pin 11) through U18's gates at pins 8–11, which are unused on this board.

- [ ] A board with the original CC784's `/M1` bodge ([§4.4](#44-the-original-cc784s-board-h)) has U18 pins 5 and 6 taken. Move it to pins 13 and 12 first, where the `CC784-4` has it: U17 pins 3 and 4 to **U18 pin 13**, U17 pin 9 to **U18 pin 12**. Check: U18 pin 5 ↔ U17 pin 3 and U18 pin 6 ↔ U17 pin 9 must **not** beep. 10 min.

### The panel

Converting the board does not convert the CC710's display. The CC784 firmware shifts 86 columns per row; on the CC710's 60-stage panel the first 26 fall off the far end, so only the right-hand part of each frame shows [M]. The patched firmware's CC710 build shifts 60 and strobes the '595s after each row ([patched.md](patched.md#2-patches), patch 37) [H]. The original CC784's panel has 84 columns on the same '595 chain, and the standard build, which shifts 86 and strobes after every row, drives it as it is [H].

### Checks after conversion — 10 min

- [ ] Power up with the NET firmware: the demo scrolls; [upgrades.md §5](upgrades.md#5-checks-after-any-upgrade--5-min) for the rest.
- [ ] Load a short message, then switch the mains off and on twenty times: the message must survive every cycle. The fault is intermittent, so more cycles make a pass more convincing. This is the test the stock lockout fails.
- [ ] If every cycle comes back empty (demo running, address 1, clock at 12:00 AM) rather than damaged, the RAM lost its backup supply, not its contents to stray writes: run step 2's backup-draw check.

## 6. Open questions

- **Direct 3.3 V TTL serial** without a MAX3232 ([§2.4](#24-host-port-serial-and-keypad-h)): probable, unverified.

## 7. Verified on hardware

Both boards are captured in KiCad ([hardware/CC784-4/](hardware/CC784-4/), [hardware/CC784-3A/](hardware/CC784-3A/)); the netlists are the source for every [H] above that cites the schematic. Serial framing and checksum; ACK `0x06` on own address (0 after RAM loss); NAK on bad checksum implied by code; message load/display, sequence, clear, clock-set commands; `0xB4` queries crash/corrupt the stock firmware (see firmware notes B1); host port pin roles on both boards; AC supply; battery footprint; part numbers from the photos of all four boards.
