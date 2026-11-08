# CC784 ideas and parked work

Work not built, with its sizing and the decisions already made. Firmware sizes are estimates against the patched build; the free ROM count is in [patched.md](patched.md#1-memory-map). Sections link to the notes that hold the facts they rely on.

---

## 1. The four spare DB9 lines

Dropped. Every sign has a dongle, and the dongle already does over serial what the lines were for: brightness and mute are configuration bytes (`B6`), an alert is a sequence change sent and later undone, the message boundary is the status report (patch 41, §11), and the heartbeat is a periodic `stats` poll (patch 40): no reply, or an uptime that stops counting, is a hung sign; a boot count that moves is a reboot. The lines also belong to the wired keypad in keypad mode (patch 36), so leaving them alone avoids that conflict. Two are inputs to the sign (`PORT_IN` bits 0 and 2, DB9 pins 2 and 6), two are outputs (`CTRL_LATCH` bits 5 and 6, pins 4 and 7) ([hardware notes §4](hardware.md#4-serial-port-h)); the four role bytes in the configuration block (3–6) stay unused. The chain of §2 would still need pin 2.

## 2. Several signs on one serial link

This is the legacy case: one or two RS-232 ports on a PC and many signs. With a dongle per sign the constraint disappears, and status reports (§11) become the way to follow each sign. The two can be on together; in a chain the reports are best effort. The factory only ever had a transmit-only fan-out: the host's TX to every sign's RX, the `*` broadcast address so nobody replies ([protocol notes](protocol.md)). A return path through the spare input makes it bidirectional.

**Topology.** Host TX fans out to every sign's RX (pin 8). Replies come back up a chain: the last sign's TX (pin 3) goes to the spare input of the sign above it, that sign forwards it onto its own TX, and so on to the host. Only the first sign needs the dongle. No collisions by construction: a packet addresses one sign, so at most one sign transmits, and the forwarding sign is never that one.

**Bit repeater, the cheap version, ~15 bytes.** In the ISR, every 128 µs: read the upstream input bit and copy it to latch bit 4 unless the sign's own transmitter is active. Polarity needs no inversion: an upstream TX idles low for mark, the input reads 0, and latch bit 4 at 0 is mark. Each hop re-times every edge to the interrupt grid, so each hop adds up to 128 µs of jitter per edge:

| Baud | Bit | Hops before the host's mid-bit sample is at risk |
|---|---|---|
| 300 | 3333 µs | 10 or more |
| 600 | 1667 µs | 5 |
| 1200 | 833 µs | 2; a third is marginal |

**Byte-level forwarding, the robust version, ~120 bytes ROM plus a few of RAM.** A second receive engine re-times each byte before the transmitter resends it: unlimited hops at any rate, one byte of latency per hop. Only worth building if a chain grows past three signs.

Caveats:

- The forwarding sign must not hold interrupts off for a fraction of a bit while a downstream reply passes. The remaining long DI windows are OTA page writes, which happen only while the host talks to that sign, so no downstream traffic exists then. The latch and FIFO critical sections are microseconds.
- Every sign needs a unique address. After a RAM loss the patched firmware defaults to 1 ([patched notes](patched.md)), so a battery swap means setting the address again.
- The chain takes pin 2, as a stored setting rather than an autodetect.
- A chained sign running stock NET firmware sees pin 2 low at boot as "a PC is attached", which is correct.

**Alternative with no firmware.** The dongle's header carries UART0. A second sign can hang off TXD0 and RXD0 through its own small level board, and the ESP proxies two sign ports. Wins only for exactly two signs.

## 3. Scrolling up, down and right

Today only LEFT scrolls; UP, DOWN, RIGHT and HOLD are wipes. The engine stages every non-LEFT effect as an 86-column page in `TXBUF` and hands it to the routine in `EFFECT_VECTOR` ([firmware notes §8](firmware.md#8-rendering-h)), so the scrolls are three more page routines. Like the wipes, each acts on the text between one movement attribute and the next, at most a screenful, centered by `STAGE_OFFSET`.

| Piece | Design | ROM |
|---|---|---|
| Store | one new byte, `0xB2` SCROLL, as a prefix: `B2 1A` scroll up, `B2 1B` scroll down, `B2 0F` scroll right. Plain `1A`/`1B`/`0F` stay the wipes, so no stored message changes. Only `0xB2` and `0xBF` have no meaning anywhere in the code space today | 1 byte RAM for the flag |
| Renderer | one check in the attribute chain sets the flag; the three existing setters pick the slide routine instead of the wipe when it is set | ~30 |
| UP / DOWN | the page slides in one row per step from the bottom or top, pushing the current page out, 7 steps, then the usual hold. In-place shift of the 86 panel bytes with the next page's row bit OR'd in; one routine with a direction flag. During motion the page is one color (its first color byte), since color bytes are separate stream bytes; colors return at rest, which is what the stock UP/DOWN wipes already do in yellow | ~75 |
| RIGHT | the page slides in from the left one column per frame, 86 minus `STAGE_OFFSET` steps, pushing the current page off; color bytes travel with their glyphs, so full color throughout. Page 2 enters to the left of page 1 only when a section exceeds 86 columns and gets split, which the stock effects also do | ~45 |
| Row color latch for a page in motion | | ~15 |
| Editor | the `0xB2` slot in the second label table is empty; the message reads `.SCROLL..UP.`; FUNC then LEFT inserts it (LEFT has no FUNC meaning) | ~16 |
| Host tool | `scroll up` sends `B2 1A`; three rows in the protocol notes | 0 |
| Emulator | a `scroll` gate: each frame's panel is the previous one shifted by a row or a column | 0 |

Totals: ~150 bytes for UP and DOWN, ~200 with RIGHT; RIGHT can be added later for its ~50 bytes with no store change. Step delay can follow the SPEED attribute for free. A true mirror of the LEFT crawl was ruled out: it needs the store walked backwards and the renderer accumulates fonts and colors forwards.

## 4. Wired keypad and the remote lock

The wired keypad is patch 36 ([patched notes](patched.md#2-patches)). Its keys ignore the remote lock; whether they should is a choice for whoever mounts a keypad in public.

## 5. Night mode by the clock

Dim or blank the display between two times of day, set like the clock over serial or from the editor. About 40 bytes. The mute setting (`B6`, configuration byte 2) covers the same need from Home Assistant, so this only matters for a sign without a dongle.

## 6. ROM savings

| Item | Bytes | Note |
|---|---|---|
| Faster boot CRC | dropped | only ~20 % faster and needs a chip burn; not worth it |

## 7. Skip empty channels in the sequence

Built: patch 39 ([patched notes](patched.md#2-patches)).

## 8. Faster CPU: analyzed and shelved

A Z84C0020 is a drop-in at 8 MHz. Faster clocks were worked through and set aside ([hardware notes §2](hardware.md#2-memory-and-io-decoding-h--from-the-schematic)):

- The ROM select is `/MREQ` through the LS139, which leaves 67 ns for the EEPROM at 8 MHz and 12 ns at 16 MHz. No parallel EEPROM or flash reaches that; the AT28HC256-70 is the fastest pin-compatible part and needs two wait states at 16 MHz, one at 12 MHz. The fitted AT28C256-15 needs two waits even at 12 MHz, which hands the gain back.
- The only visible benefit would be faster serial, because the sampling grid that capped 2400 baud is the interrupt period: 12 MHz gives a 9-tick frame that keeps every timing exact and brings 2400 back; 16 and 20 MHz give 12 and 15.
- The clean fast design is run-from-SRAM: a 12 ns 62256-pinout SRAM shadowing the EEPROM, a spare bank-register bit as the shadow select, F or AC decoders. About 2.5 times today's throughput. A project on its own, if ever.

## 9. Dongle follow-ups

- **ESPHome config:** `serial_proxy` at 1200 baud with `tx_pin` `inverted: true` only; `remote_receiver` on IO7 with `dump: raw` to read a NIR's remote through U5B; `power_save_mode: light`, since the sign's 10 Ω R31 caps the average current near 130 mA. Bridge R31 on the sign if a dongle ever browns out.
- **IR keystroke injection** on a receiver-less NET: close JP2, drive pin 1 from IO2 with the encoder in [tools/cc784_ir.py](tools/cc784_ir.py). Never on a NIR, where the HC14 drives that net.
- **Remote decoding on the ESP:** the frame format is known ([firmware notes §9](firmware.md#9-ir-remote-decoder-ir_-14821571-h--verified-against-a-capture-of-the-signs-own-receiver)); a custom `remote_receiver` protocol would turn remote keypresses into Home Assistant events.
- **Declined, recorded:** the LM66200 ideal diode in place of the two MBR120s (better headroom, but raises the WS2812's data threshold above 3.3 V unless the LED keeps a diode of its own); a solder jumper to run the LED from 3.3 V (out of the LED's VDD spec by 0.2 V, blue may be weak).

## 10. Other models

The CC710 runs a descendant of the original CC784's code base, with the packet protocol added, on the `CC784-3A` board ([firmware notes §15](firmware.md#15-the-cc710-firmware-h--from-a-rom-dump-id-710), [hardware notes §11](hardware.md#11-the-cc784-3a-board-cc710-h)). As shipped it cannot run the patched firmware: 2 KB of RAM in a 24-pin socket against the 16 KB the patched build uses. [Hardware notes §12](hardware.md#12-converting-a-cc784-3a-board-to-a-cc784-4) turns the board into a `CC784-4` (RAM, the later power-fail detect, a DB9 cable), after which the patched firmware's CC710 build runs on it ([patched.md](patched.md#2-patches), patch 37). On its stock firmware, two things it could still get:

- **A dongle on its header.** Packet mode needs the boot probe answered (SK1 pins 5, 4, 9) and the CTS/ready lines honoured (SK1 pins 8 and 7 high for TX; pin 4 is the sign's ready). An ESP on the header could do all of that in software, and the CC710 answers queries `0`–`3` once in packet mode. For bench tests there is a way in without an adapter: hold `1`, `7` or `U` on the keypad at power-up (address `*`).
- **Small patches of its own** (16 KB ROM, 3.9 KB free): the address-inversion bug in the probe's keep path, and the `17` AM/PM handling, if the sign is ever used with a host.

The original CC784 is on the same board ([firmware notes §16](firmware.md#16-the-original-cc784-firmware-h--from-a-rom-dump-id-9g), [hardware notes §13](hardware.md#13-the-original-cc784s-board-h)) and converts the same way, with its `/M1` bodge moved first ([hardware notes §12](hardware.md#12-converting-a-cc784-3a-board-to-a-cc784-4), step 5). Its stock firmware has no packet protocol, so a host can only type into it as keys. Its panel matches the NET's and NIR's, so once converted it runs the standard patched build [H].

## 11. A configuration store

The block itself exists since patch 35 ([patched notes](patched.md#2-patches)): sixteen battery-backed bytes with a signature and a sum, written with `B6 index value`, read with `B4 '5'`, carrying brightness, mute, the spare-line roles, the alert channel, hold time, flash rate, beeper and remote lock. Settings it reserves bytes for but does not act on yet:

| Setting | Values | Default | Notes | ROM |
|---|---|---|---|---|
| Clock source | auto, mains, crystal | auto | overrides patch 31's boot-time detection on the add-in board | ~8 |
| Night schedule | start, end, level | off | the clock-based night mode of §5 as three bytes in the reserved space instead of its own editor dialog | ~40 |
| Chain forwarding | on, off | off | the bit repeater of §2 | 1 |

The live bits of the flags byte (alert playing, editor open, wrapped) sit outside the sum so they can change without a reseal; the clock and the sequence beside the block are outside it for the same reason, and the sequence is read with `B4 '6'`.

**Status reports** are built as patch 41 ([patched notes](patched.md#2-patches)): byte 12, `B1 addr 03 'S' channel flags sum` at each channel start and with channel `FF` when the editor opens, the flags being `CFG_FLAGS` as is. Not built from the design: a report on every flag change, since with the spare lines dropped (§1) nothing else changes behind the host's back.
