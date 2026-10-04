# CC784NIR hardware — reference notes and open questions

Color Cells / Innovative Sign Technology **CC784NIR** ("NIR" = infrared
remote variant). Controller board silk-screened `CC784-4` (rear: `COLOR CELLS
CC784-4`), double-sided, through-hole only, factory bodge wires. Chip date codes
9235–9246 (late 1992); firmware dated 17-02-93. Photos on file: front, rear,
backlit detail of the DB9/LS244 area.

Confidence key as in the firmware notes: **[H]** verified, **[M]** inferred,
**[L]** hypothesis.

---

## 1. Parts list (from photos) [H unless noted]

| Ref | Part | Role |
|---|---|---|
| U1 | Zilog **Z0840008PSC** (Z80, 8 MHz grade) | CPU |
| U2 | ST **M27C256B-15F1** (32 K × 8, 150 ns) | firmware ROM; only lower 16 K used |
| U3 | Hyundai **HY6264ALP-10** (8 K × 8 SRAM) | RAM `4000–5FFF` |
| U4 | 74LS139 | U4B memory decode, U4A I/O decode (§2) |
| U5, U9 | 74LS273 ×2 | U5 = `CTRL_LATCH` (`8000`), U9 = colour latch (§5) |
| U6 | **74LS145** (BCD→decimal, OC) | row select → TR1–TR7 |
| U7, U8 | 74LS151 ×2 | row-bit selector and colour selector for the panel data (§5) |
| U10, U16, U17 | 74LS00 ×3 | glue |
| U11 | 74HC04 + 8.000 MHz crystal | oscillator |
| U12 | 74LS244 | serial outputs, and the input port read by `IN C0` (§4) |
| U13 | 74HC132 | RAM `/CE` gating and the power-fail CS2, on the battery rail |
| U14 | **74HC4020** (14-stage ripple counter) | timebase divider (§3) |
| U15 | LM340T-5 (7805) | 5 V regulator |
| U18 | CD74HC14 | IR receiver conditioning |
| U19 | 74HC164 | first stage of the column shift chain (§5) |
| TR1–TR7 | TIP125 (PNP Darlington) | LED row drivers |
| Q8, Q9 | BC548 | beeper driver; power-fail detector for CS2 (§7) |
| C1, C2 | 4700 µF 16 V | bulk filter |
| R4, D3 | 220 Ω, diode | battery charge/discharge path and the `+5VP` rail (§7) |
| SK2 | 24-pin connector | display panel (§6) |
| J | DB9 male | serial (§4) |
| — | "NICAD BATTERY" footprint | RAM backup; **was fitted, removed (leaking)** |
| — | 3-pin header (right edge, glued) | IR receiver module (5 V; the remote's carrier is 31.4 kHz, §9) |
| — | barrel jack | 9 V **AC** in (supplied PSU: 9 V AC, 4.2 A transformer) |
| — | piezo/speaker near SK2 | beeper (`07` command) |

## 2. Memory and I/O decoding [H — from the schematic]

U4 (74LS139) does both halves:

- **Memory (U4B, enabled by `/MREQ`, inputs A15/A14):** `2Y0` ROM `/CE` and
  `/OE` (`0000–3FFF`); `2Y1` → U13 → RAM `/CE` (`4000–7FFF`, gated by CS2,
  §7); `2Y2` clocks U5, the control latch (`8000`); `2Y3` (`C000–FFFF`) is
  unused on the stock board and now clocks the OTA bank register.
- **I/O (U4A, enabled by `IORQ·/M1` so interrupt acknowledges are excluded,
  inputs A7/A6):** `1Y0` (`00–3F`) unused; `1Y1` = the `40` group: clocks the
  on-board HC164 (U19) and the panel's column clock (J2 pin 11, through U18),
  and, gated with D7 in U10, clocks U9, the colour latch; `1Y2` = `80`, the
  strobe (J2 pin 12); `1Y3` = `C0`, enables the '244's input half onto the
  bus. Within the `40` group the Z80's low address bits are used as data: A0–A2
  select the row bit (§5), A3 the intensity pass, A5 the beeper, and A8 — the
  `B` register during `OTIR` — red or green.

### ROM socket wiring [H — traced on the board]

- **Pins 1 (VPP) and 28 (VCC) are both on the 5 V net**, joined by a visible
  trace. Nothing on the board can drive VPP, so any substitute that expects an
  address line on pin 1 has to have that pin lifted.
- **A14 reaches the EPROM on pin 27 through a factory bodge wire from Z80
  pin 4.** The PCB does not route it. That fits a layout originally cut for a
  2764/27128, where pin 27 is `/PGM` and gets tied high; fitting a 27C256
  needed a real A14, hence the wire. ROM `/CE` is only asserted when A14 = 0,
  so the chip is permanently confined to its lower 16 K — which is why the
  upper half of the dump is `0xFF`.

Substitutes, given the above:
- **W27C512** — pin 1 is A15 and sits on 5 V, so the upper half runs; program
  the 32 K image twice.
- **AT28C256 / 28C64** — pin 1 is A14 and pin 27 is `/WE`, i.e. both swapped
  relative to the 27C256. Straight substitution is destructive: board A14 lands
  on `/WE` and goes low on every ROM fetch. Two bodges make it exact:
  lift **pin 27** and jumper it to VCC (writes permanently disabled), and lift
  **pin 1** and run it to A14 (Z80 pin 4). With both done the part is
  electrically a 27C256 and takes the ordinary 32 K image unchanged — `/CE`
  only asserts when A14 = 0, so nothing above the chip's own `3FFF` is ever
  addressed. Skipping the pin 1 bodge leaves A14 stuck high on the VPP net;
  that needs the low 16 K duplicated into both halves instead.

## 3. Timebase [H]

8.000 MHz crystal → HC04 oscillator → the Z80 clock and the HC4020 (U14).
The counter is **reset by every interrupt acknowledge** (`M1·IORQ`, U17 →
U11 → pin 11), and `/INT` is its Q11 output inverted: it asserts 1024 clocks
= 128 µs after the last acknowledge, which is the 7812.5 Hz tick. Q13 goes
high 4096 clocks = 512 µs after the last acknowledge and, inverted by U17,
**clears U5**, the control latch, for the next 512 µs: a watchdog that blanks
the rows and parks TX whenever the firmware stops servicing interrupts, for
instance for the whole of `pkt_process`. It is why the OTA bank register is a
separate chip (`CC784_ota.md` §1). The Z80 runs at the full 8 MHz: the
firmware's per-tick work does not fit 4 MHz (firmware notes §2).

**As designed (the CC784NET board):** 4 MHz crystal, and U10 NANDs Q11 with
Q12 (pin 1, the trace the NIR cuts), so `/INT` asserts 3072 clocks = 768 µs
after the acknowledge: 1302 Hz, the rate the NET firmware runs its serial
engines and row scan at directly. The NIR's 8 MHz crystal and the Q11-only
bodge give the 7812.5 Hz tick its IR decoder needs; its firmware divides by 6
to get the same 1302 Hz for everything else. A NET board therefore needs
both the crystal and the bodge before it can run the NIR firmware; done on
2026-10-03, and its Z8400A (4 MHz grade) runs the patched firmware at 8 MHz.

NMI: 60 Hz from the AC input via a zero-cross detector (`NMI_PER_SEC = 60`).
With a DC supply the clock would not run; the supplied PSU is AC, so it does.

## 4. Serial port [H]

DB9 wiring, from the schematic (2026-09-27; corrects the earlier photo trace,
which had RX on pin 2):

| DB9 | Path | Direction | Function |
|---|---|---|---|
| 3 | U12 pin 18 (1Y1) ← `CTRL_LATCH` bit 4 | sign → PC | **TX** (ACK/NAK, query replies) |
| 8 | R30 270 Ω → D8/D9 clamp → R7 3.3 k pull-up → U12 → `PORT_IN` bit 3 | PC → sign | **RX** — the only real RS-232 receiver on the board |
| 4 | U12 pin 16 (1Y2) ← latch bit 5 | sign → PC | keypad row select bit 1; NIR firmware never drives it |
| 7 | U12 pin 14 (1Y3) ← latch bit 6 | sign → PC | keypad row select bit 2; NIR firmware never drives it |
| 1 | R8 pull-up → U12 → `PORT_IN` bit 1 | PC → sign | keypad column code bit 1; shares the net with the IR receiver output (factory bodge) |
| 2 | R9 pull-up → U12 → `PORT_IN` bit 0 | PC → sign | keypad column code bit 0; the factory cable ties it to pin 5, which is how the NET firmware detects a PC (§6) |
| 6 | R6 pull-up → U12 → `PORT_IN` bit 2 | PC → sign | keypad column code bit 2; not read by the NIR firmware |
| 9 | R31 10 Ω from +5 V | sign → PC | +5 V out |
| 5 | — | — | GND |

The factory cable is the crossover: sign 3 → PC 2, **sign 8 → PC 3**, and
sign 2 and 5 → PC 5. Levels: TTL out of the LS244 on the outputs; pin 8 is the
one input with a proper RS-232 clamp (negative swing shunted by D9, so bit 3
reads 1 during space). Polarity as the firmware sees it: `PORT_IN` bit 3 = 1
during space; `CTRL_LATCH` bit 4 = 1 drives space. 300 baud, 8 data, no
parity; sign checks 1 stop bit, sends ~2.

Working setups (both verified with live ACKs): USB-RS232 adapter + crossover;
ESPHome `serial_proxy` via `cc784_esphome.py` (aioesphomeapi 46.4.x).
A MAX3232 is the faithful interface; direct 3.3 V TTL with software inversion
would probably work through the 220 Ω but is unverified.

## 5. Display drive [H — from the schematic and the firmware]

- **Row select:** U5 Q0–Q3 → U6 (LS145) → TR1–TR7 → J2 pins 1–7. The
  firmware writes the row index complemented (`7−k`), so live rows are codes
  1–7; code 0's output is unconnected and `0F` decodes to nothing, so both
  blank. U5 Q4 is serial TX, Q5/Q6 go to DB9 pins 4/7 (unused), Q7 is the
  2.4 Hz FLASH clock.
- **Column data:** one `OTIR` of 86 bytes per row, the same 86 column bytes
  for every row. U7 (LS151, data = D0–D7, select = A0–A2 = the row) picks
  the current row's bit out of each byte and feeds it to the on-board HC164
  and to U16, whose output is J2 pin 10, the panel's serial data. Each row is
  written twice, to `40+row` then `48+row`, displayed for one and two ticks
  respectively (§7 of the firmware notes): A3 selects intensity bit 0 or bit
  1 of the colour, giving four levels with 1:2 weights.
- **Colour:** a byte with bit 7 set is latched by U9 instead of being shifted
  (U10 gates the `40`-group clock with D7). Bits 0–1 green and 2–3 red
  intensity, bit 4 FLASH, bits 5–6 background red/green (one bit each, so the
  four background names). U8 (LS151) takes U9's outputs: for a lit pixel it
  selects the foreground bit chosen by A3 (which intensity bit) and A8 (green
  or red, alternating per column because `B` counts down on A8–A15 during
  `OTIR`); for an unlit pixel it selects the background bit. The FLASH bit is
  ANDed with U5 Q7 in U10 to blank flashing columns on the off phase. U9 Q7
  is latched from **A5**, not the data bus, and drives the beeper through
  Q8: `OUT (68+row)` beeps.
- **The panel** [H — owner]: two PCBs of 7 × 42, red and green LEDs
  alternating per column (right-most green, left-most red), common anode per
  row from TR1–TR7 at +9 V, cathodes per column into ULN2003As (six per
  PCB) driven by 74LS164s (six per PCB) in one daisy chain. Each PCB's last
  '164 uses two outputs and passes the second on to the next PCB, so the
  six unused outputs are off the data path and the chain is exactly 84
  stages with no latch. The firmware's 86 bits per row are 84 columns plus
  two that fall off the far end (`FRAMEBUF` is 86 wide), and its 85 zeros
  flush the chain; the row is blanked while shifting and selected after.
  Single-colour text therefore lights every other column; yellow lights
  both.
- **Background codes** `94–9F` draw no background (watched on the sign); the
  two hardware background bits make only `90–93` useful.

## 6. Connectors

**SK2 (24-pin, to the LED panel)**, counted from the board's bottom corner
(user's tracing): pins 1–7 LED rows (from TR1–TR7); 8–9 V+ (rectified 9 V AC,
unregulated); 10 column data, 11 column clock (port `40`); 12 is the port
`80` strobe but is not connected on the panel; 13–14 GND.

**IR header**: 3 pins — 5 V, GND, signal — glued near U18. Signal → HC14 →
`PORT_IN` bit 1 (one inversion; active-low module output becomes 1 = burst).
Verified by capture: module output idles high, bursts low, and lengthens each
burst by ~250 µs relative to the transmitted half-bit (512 µs → ~780 µs).

**The IR carrier is 31.25 kHz nominal, 31.4 measured.** The remote is a
Motorola MC14497P PCM transmitter on a 500 kHz ceramic resonator (board
BP0300346B, 62 keys, two IR LEDs); the chip's carrier is the oscillator
divided by 16 and its bit cell is 512 oscillator cycles, 1024 µs. Logic
analyzer on its driver output: 31.88 µs period, 29 % duty, every burst 16
cycles = 510 µs, start burst 3.06 ms after the leader, frames every
89.8 ms. A 30 kHz receiver (TSOP4830/TSOP38230 class) is the closest
replacement, 33 kHz the next; a 38 kHz part is 17 % off and chops the
bursts.

**Keypad**: plugs into the DB9. The same `CC784-4` board ships as the
CC784NET (keypad or PC, no IR), and that firmware scans a keypad over the
seven DB9 signals [H — from the NET ROM, see firmware notes §13]:

| Signal | DB9 | Firmware side |
|---|---|---|
| row select, 3 bits (decoded to 8 rows in the keypad) | 3, 4, 7 | `CTRL_LATCH` bits 4–6 |
| column code, 3 bits (encoded from 8 columns in the keypad) | 2, 1, 6 | `PORT_IN` bits 0–2 |
| key pressed, active low | 8 | `PORT_IN` bit 3 |

Key code = row × 8 + column (`keypad_scan`, identical in both ROMs; key 0
is reported as `1E`, which is why the charsets hold `K` at both `00` and
`1E`). The code indexes the `CHARSET_*` tables directly; the NIR's
`IR_KEY_TABLE` converts a remote key number into this code, so the remote
and the keypad share one editor. STOP/START is code `35`, SHIFT is `19`.
The keypad's decoder and encoder ICs are inferred from the code, not seen.

**PC or keypad?** The NET firmware decides at boot: it clocks a pattern out
on pins 4 and 7 and samples pin 2; pin 2 low (the factory cable's 2–5 short)
means serial, anything else means keypad, and in keypad mode the serial
engines never run. The NIR firmware skips the test and never calls
`keypad_scan`; the patched build drops it.

## 7. Power / battery

9 V AC in → bridge (D?) → C1/C2 → 7805 → 5 V logic; unregulated rail to the
LED rows via SK2. Battery: 3-cell NiCd footprint. It charges **and**
discharges through R4 (220 Ω) to `+5VP`, the rail behind D3 that feeds only
the RAM and U13; Q9 with zener D11 watches the main 5 V and drops CS2 (via
U13) as it fails, which deselects the RAM. The backed-up contents are the
message store, address, sequence and clock digits — the clock does not *run*
on battery, it only keeps its value.
Battery removed by the owner (leaking). Replacement options: same-chemistry
pack off-board; CR2032 **with a series diode** (do not charge a lithium
primary); or a 0.47–1 F 5.5 V supercap in the existing charge path.
Without a battery the sign boots with address 0 and an empty store.

## 8. Factory bodge wires [H — from the schematic]

- Z80 pin 4 (A14) → ROM socket pin 27 (A14): the layout was cut for a
  27128; a 27C256 needed a real A14.
- The RAM footprint is a 24-pin socket. The 6264's pins 1, 2, 27 and 28
  hang outside it, with the wires below soldered straight to the legs.
- Z80 pin 22 (`/WR`) → RAM pin 27 (`/WE`).
- U13 pin 8 (CS2) → RAM pin 26.
- U18 pin 11 → J2 pin 11 (the panel column clock), cut from its original
  route.
- U10 pin 12 cut from HC4020 pin 1 and bridged to pin 13: the `/INT` gate
  became an inverter on Q11.
- U18 pin 6 (IR, after the inverter) → the DB9 pin 1 net, which is how IR
  reaches `PORT_IN` bit 1.

## 9. Open questions

Answered from the schematic (2026-09): CPU clock (8 MHz), the INT source and
the watchdog (§3), the control-latch and colour-latch bit maps (§5), the
input port (§4, the '244, not a mux), SK2 pins 10–12 (data, clock, strobe),
the bodge wires (§8), the battery path (§7), the `OUT (40)` role and the
double row write (§5).

Answered on the bench (2026-10): the IR carrier and the remote's chip (§6),
the panel's construction (§5), the background codes (§5).

Still open:

- **Direct 3.3 V TTL serial** without a MAX3232 (§4): probable, unverified.
- **SK2 pins 15–24:** which are used on the panel side.

## 10. Verified-on-hardware summary

The whole board is captured in KiCad (`~/Development/Hardware/ColorCells/CC784`); the netlist is the source for every [H] above that cites the schematic.
Serial framing and checksum; ACK `06` on own address (0 after RAM loss);
NAK on bad checksum implied by code; message load/display, sequence, clear,
clock-set commands; `B4` queries crash/corrupt the stock firmware (see
firmware notes B1); DB9 pin roles; AC supply; battery footprint; part numbers.
