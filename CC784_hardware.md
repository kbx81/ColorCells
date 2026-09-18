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
| U4 | 74LS139 | memory + I/O decoding [M: which half does what] |
| U5, U9 | 74LS273 ×2 | `CTRL_LATCH` (`8000`) and column-data latch [M: which is which] |
| U6 | **74LS145** (BCD→decimal, OC) | row select → TR1–TR7 |
| U7, U8 | 74LS151 ×2 | 8:1 input muxes feeding `IN C0` [M] |
| U10, U16, U17 | 74LS00 ×3 | glue |
| U11 | 74HC04 + 8.000 MHz crystal | oscillator |
| U12 | 74LS244 | serial port buffer (traced, §4) |
| U13 | 74HC132 | Schmitt NAND — reset / mains zero-cross [M] |
| U14 | **74HC4020** (14-stage ripple counter) | timebase divider (§3) |
| U15 | LM340T-5 (7805) | 5 V regulator |
| U18 | CD74HC14 | IR receiver conditioning |
| U19 | 74LS164 | column shift register (§5) [M] |
| TR1–TR7 | TIP125 (PNP Darlington) | LED row drivers |
| TR8, TR9 | small TO-92 | near IR header / reset [L] |
| C1, C2 | 4700 µF 16 V | bulk filter |
| D1, R32 | — | battery trickle-charge path [M] |
| SK2 | 24-pin connector | display panel (§6) |
| J | DB9 male | serial (§4) |
| — | "NICAD BATTERY" footprint | RAM backup; **was fitted, removed (leaking)** |
| — | 3-pin header (right edge, glued) | IR receiver module (38/40 kHz type, 5 V) |
| — | barrel jack | 9 V **AC** in (supplied PSU: 9 V AC, 4.2 A transformer) |
| — | piezo/speaker near SK2 | beeper (`07` command) |

## 2. Memory and I/O decoding [M]

Consistent with the firmware and an LS139:
- Memory: A15/A14 → `00` ROM (`0000–3FFF`), `01` RAM (`4000–5FFF`), `10`
  control latch write at `8000`. Note the ROM select stops at `3FFF`, so a
  28C256/28C64-style substitute with `/WE` on pin 27 would see A14 low and
  self-corrupt — use a **W27C512** (27C512 pinout, pin 1 = A15 tied high →
  program both halves) instead.
- I/O: A7/A6 → `40` (column clock), `80` (strobe), `C0` (input mux read);
  `48–4F` = `40` group with A3 set, row in A0–A2, used by `OTIR` for the 86
  column bytes of one row.

## 3. Timebase [H for the arithmetic, M for the wiring]

8.000 MHz crystal → HC04 oscillator → HC4020. The firmware's bit tables give
300 baud only if the interrupt is **7812.5 Hz = 8 MHz / 1024 = HC4020 Q10**.
Whether the Z80 clock is 8 MHz (from the HC04 directly) or 4 MHz (HC4020 Q1) is
**not yet determined** (open question H1). A 150 ns EPROM is comfortable at
4 MHz and marginal at 8 MHz without a wait state.

NMI: 60 Hz from the AC input via a zero-cross detector (`NMI_PER_SEC = 60`).
With a DC supply the clock would not run; the supplied PSU is AC, so it does.

## 4. Serial port [H]

DB9 wiring (traced on the backlit photo; through 220 Ω resistors R8/R9/R10):

| DB9 | LS244 pin | Direction | Function |
|---|---|---|---|
| 3 | 18 (1Y1 out) | sign → PC | **TX** (ACK/NAK, query replies) |
| 2 | 17 (2A1 in) | PC → sign | **RX** |
| 4 | 16 (1Y2 out) | sign → PC | DTR-like, probably held asserted |
| 7 | 14 (1Y3 out) | sign → PC | RTS-like, probably held asserted |
| 1 | 15 (2A2 in) | PC → sign | DCD-like input; not read by the firmware as far as seen |
| 5 | — | — | GND |

So the sign is wired like a DTE (TX on 3, RX on 2): a PC needs a **crossover**.
Levels are **TTL** (0/+5 V out of the LS244); the input side is RS-232
current-limited into a TTL input by the 220 Ω. Polarity as the firmware sees
it: `PORT_IN` bit 3 = 1 during space; `CTRL_LATCH` bit 4 = 1 drives space.
300 baud, 8 data, no parity; sign checks 1 stop bit, sends ~2.

Working setups (both verified with live ACKs): USB-RS232 adapter + crossover;
ESPHome `serial_proxy` via `cc784_esphome.py` (aioesphomeapi 46.4.x).
A MAX3232 is the faithful interface; direct 3.3 V TTL with software inversion
would probably work through the 220 Ω but is unverified.

## 5. Display drive [M]

- Frame buffer 4 × 86 bytes; 7 physical rows (TR1–TR7 via LS145; latch low
  nibble = row, `0F` = no row = blank).
- Row refresh: `OTIR` 86 bytes to `48+row`, strobe on `80`. Port `40` clocks
  the LS164 column shift chain; 85 zero-writes clear it (`sub_2B84`).
- Colour: two LED dies per pixel (red/green) with 2-bit intensity each
  (16 foreground codes), consistent with the 4 planes in the buffer being PWM
  planes. Exact plane→intensity mapping not traced.

## 6. Connectors

**SK2 (24-pin, to the LED panel)**, counted from the board's bottom corner
(user's tracing): pins 1–7 LED rows (from TR1–TR7); 8–9 V+ (rectified 9 V AC,
unregulated); 10–12 three data lines (**to be identified** — expect column
data/serial, column clock from port `40`, strobe/latch from port `80`);
13–14 GND. Remaining pins not yet noted.

**IR header**: 3 pins — 5 V, GND, signal — glued near U18. Signal → HC14 →
`PORT_IN` bit 1 (one inversion; active-low module output becomes 1 = burst).
Verified by capture: module output idles high, bursts low, and lengthens each
burst by ~250 µs relative to the transmitted half-bit (512 µs → ~780 µs).

**10-pin IDC keypad header**: present on an *earlier* model instead of the DB9;
not on this board. Explains the `keypad_scan` code (8×8 matrix through the
latch upper nibble and the LS151 muxes).

## 7. Power / battery

9 V AC in → bridge (D?) → C1/C2 → 7805 → 5 V logic; unregulated rail to the
LED rows via SK2. Battery: 3-cell NiCd footprint, trickle-charged through
D1/R32 [M], backing only the HY6264 (message store, address, sequence, clock
digits — the clock does not *run* on battery, it only keeps its value).
Battery removed by the owner (leaking). Replacement options: same-chemistry
pack off-board; CR2032 **with a series diode** (do not charge a lithium
primary); or a 0.47–1 F 5.5 V supercap in the existing charge path.
Without a battery the sign boots with address 0 and an empty store.

## 8. Factory bodge wires [L]

Several (yellow/green/white on top, red/white/black underneath), original.
Endpoints not yet recorded. One white wire lands near the DB9 area. Likely a
decoding or timing fix absorbed in a later PCB revision.

## 9. Open questions (ordered by value), with how to answer each

- **H1. CPU clock.** Scope Z80 pin 6: 8 MHz vs 4 MHz. Or trace HC04 output /
  HC4020 pin 9 (Q1) to Z80 pin 6.
- **H2. INT source.** Confirm Z80 pin 16 is ~7.8 kHz and comes from HC4020
  pin 14 (Q10).
- **H3. Control-latch bit map.** Follow the `8000` LS273's Q0–Q7: expect
  Q0–Q3 → LS145 (rows), Q4 → LS244 pin 2 (TX), Q4–Q6 → LS151 select lines.
  **Q7 is unassigned in the firmware analysis** — beeper drive? brightness?
- **H4. Input mux map.** LS151 inputs (U7/U8): which carry IR (bit 1), RX
  (bit 3), keypad columns, and whether DB9 pins 1/4/7 reach the mux at all.
- **H5. SK2 pins 10–12** and any remaining pins; what's on the panel side
  (more LS164s? driver ICs? how many columns physically — 86?).
- ~~H6. IR format~~ — **solved** from a logic-analyzer capture of the sign's own
  receiver output: 600 µs leader, start cell at 3.14 ms, 6 biphase data cells
  of 1024 µs, code = 0x80|key, 0xBE on release, ~90 ms repeat. Decoder model
  and encoder in `cc784_ir.py`; details in the firmware notes §8. Remaining:
  the **carrier frequency** — read the receiver module's part number (38 vs
  40 kHz); the earlier TSOP38238 capture chopped the bursts, which suggests
  the remote is not 38 kHz.
- ~~H7. ESPHome serial_proxy path~~ — verified end-to-end (ACK round-trip works).
- **H8. Bodge wire endpoints** (chip + pin for each end).
- **H9. Battery circuit**: confirm D1/R32 are the charge path and what voltage
  the RAM sees, before choosing a replacement chemistry.
- **H10. Background colour codes `94–9F`** and effects `BB/BD/BE`: send with
  `cc784.py msg 0 "@{9a}TEST"` etc. and record what appears.
- **H11. `OUT (40)`** electrical role confirmation (LS164 clock) — one probe
  during a `clearall`.

## 10. Verified-on-hardware summary

Serial framing and checksum; ACK `06` on own address (0 after RAM loss);
NAK on bad checksum implied by code; message load/display, sequence, clear,
clock-set commands; `B4` queries crash/corrupt the stock firmware (see
firmware notes B1); DB9 pin roles; AC supply; battery footprint; part numbers.
