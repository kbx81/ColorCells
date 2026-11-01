# CC784 ideas and parked work

Everything discussed but not built, with the sizing and the decisions already made, so nothing has to be worked out twice. Firmware sizes are estimates against the patched build; the free ROM count is in [CC784_patched.md](CC784_patched.md#1-memory-map). Sections link to the notes that hold the facts they rely on.

---

## 1. The four spare DB9 lines

The dongle ([hardware/CC784-ESP32-C6_dongle/](hardware/CC784-ESP32-C6_dongle/)) brings out every DB9 signal. Two are inputs to the sign that the patched firmware never reads, two are outputs it never drives ([hardware notes §4](CC784_hardware.md#4-serial-port-h)). The ISR already reads the input port every tick and already preserves latch bits 5 and 6 in the shadow byte, so each feature is a few bytes.

| DB9 | Direction | Sign side | Dongle pin | Proposed job | ROM |
|---|---|---|---|---|---|
| 6 | ESP drives, sign reads | `PORT_IN` bit 2 | IO4 | **Mute.** Low blanks the rows and stops scrolling; high resumes where it left off. Works with Wi-Fi down, and a mechanical switch to ground in parallel with the dongle's open-drain driver also mutes | ~30 |
| 2 | ESP drives, sign reads | `PORT_IN` bit 0 | IO3 | **Alert channel** or **chain input** (§2). Alert: while low, play one designated channel in a loop; on release, resume the sequence where it was. Home Assistant preloads the channel once and fires it with a GPIO, no serial round trip | ~40 |
| 4 | sign drives | `CTRL_LATCH` bit 5 | IO1 | **Message boundary.** Toggles each time a channel starts, so the dongle can report which message is playing and how long each runs | ~15 |
| 7 | sign drives | `CTRL_LATCH` bit 6 | IO6 | **Heartbeat / busy.** Toggles once per frame while the display runs, held still inside packet processing. A hung-sign detector from outside the Z80, and a hardware busy flag the host could use instead of waiting for the DONE byte | ~15 |

Alternatives considered for pin 2 and set aside:

| Idea | Why not first |
|---|---|
| Hold (freeze the frame) | the panel shows too little at once for a hold to mean much; the remote already has WAIT |
| Dim (skip the second intensity pass, one third brightness, no color shift, ~15 bytes) | close to what mute gives; worth it only if a night level that is not dark is wanted |
| Beep (pulse the beeper for the BEEP attribute's 115 ms, ~10 bytes) | the beeper is feeble |

Facts that shape the patches:

- All four are serial-mode features. In keypad mode on a NET they are the keypad's lines, so the patches check the mode flag first ([firmware notes §13](CC784_firmware.md#13-the-cc784net-firmware-h--from-a-rom-dump-78409n1401920145)).
- Pin 2 low is the stock NET firmware's "a PC is attached" test. The patched firmware ignores it; the dongle's JP1 grounds it for the stock case.
- Pins 4 and 7 come from the control latch, which the HC4020 watchdog clears whenever the firmware stops servicing interrupts ([hardware notes §3](CC784_hardware.md#3-timebase-h)). A crashed sign therefore reads as a flat heartbeat even if the bit was left high.
- The ESPHome side: two `binary_sensor` GPIO inputs with `inverted: true` (the dongle's 2G14s invert), two `switch` outputs where "on" is GPIO low (the 2G07s pull down).
- The emulator models the input port and the latch, so gates for all four come without new infrastructure.

## 2. Several signs on one serial link

This is the legacy case: one or two RS-232 ports on a PC and many signs. With a dongle per sign the constraint disappears, and status reports (§10) become the way to follow each sign. The two can be on together; in a chain the reports are best effort, as §10 says. The factory only ever had a transmit-only fan-out: the host's TX to every sign's RX, the `*` broadcast address so nobody replies ([protocol notes](CC784_protocol.md)). A return path through the spare input makes it bidirectional.

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
- Every sign needs a unique address. After a RAM loss the patched firmware defaults to 1 ([patched notes](CC784_patched.md)), so a battery swap means setting the address again.
- The chain takes one spare input line, so a chained sign gives up mute or alert on it. Put the chain on pin 2, keep mute on pin 6, and make it a stored setting rather than an autodetect: a mute switch held low at boot would look like an idle upstream transmitter.
- A chained sign running stock NET firmware sees pin 2 low at boot as "a PC is attached", which is correct.

**Alternative with no firmware.** The dongle's header carries UART0. A second sign can hang off TXD0 and RXD0 through its own small level board, and the ESP proxies two sign ports. Wins only for exactly two signs.

## 3. Scrolling up, down and right

Today only LEFT scrolls; UP, DOWN, RIGHT and HOLD are wipes. The engine stages every non-LEFT effect as an 86-column page in `TXBUF` and hands it to the routine in `EFFECT_VECTOR` ([firmware notes §7](CC784_firmware.md#7-rendering-h)), so the scrolls are three more page routines. Like the wipes, each acts on the text between one movement attribute and the next, at most a screenful, centered by `STAGE_OFFSET`.

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

## 4. Wired keypad support

Done as patch 36 ([patched notes](CC784_patched.md#2-patches)), with the remote moved off the DB9 ([CC784_upgrades.md §8](CC784_upgrades.md#8-ir-off-the-db9)). Open: keypad keys ignore the remote lock; whether they should is a choice for whoever mounts a keypad in public.

## 5. Night mode by the clock

Dim or blank the display between two times of day, set like the clock over serial or from the editor. About 40 bytes. The dongle's mute line (§1) covers the same need from Home Assistant, so this only matters for a sign without a dongle.

## 6. ROM savings still available

| Item | Bytes | Note |
|---|---|---|
| Duplicate-code factoring | ~100 | 43 groups of repeated sequences found by a scan of the listing; each becomes a CALL |
| The `B4 '4'` timing query | 60 | only useful while a clock source is being calibrated |
| Faster boot CRC | dropped | only ~20 % faster and needs a chip burn; not worth it |

## 7. Skip empty channels in the sequence

With the default sequence of channels 0 to 99 and one message loaded, every loop of the message ends with `seq_next_channel` opening the 99 empty channels in turn, and each open is a `chan_select` scan of the store: about 2.4 s of CPU per loop with nothing on the panel, and no packet polling inside it, so a frame that lands in that burst waits up to 2.4 s for its processing and its DONE. The sequence recount already runs at every edit; pruning the empty channels there, or remembering the last non-empty entry, removes the burst. About 30 bytes. The emulator's loop-period measurement in the patch 35 work (2.4 to 2.7 s per loop of a four-letter message) is the before number.

## 8. Faster CPU: analyzed and shelved

A Z84C0020 is a drop-in at 8 MHz. Faster clocks were worked through and set aside ([hardware notes §2](CC784_hardware.md#2-memory-and-io-decoding-h--from-the-schematic)):

- The ROM select is `/MREQ` through the LS139, which leaves 67 ns for the EEPROM at 8 MHz and 12 ns at 16 MHz. No parallel EEPROM or flash reaches that; the AT28HC256-70 is the fastest pin-compatible part and needs two wait states at 16 MHz, one at 12 MHz. The fitted AT28C256-15 needs two waits even at 12 MHz, which hands the gain back.
- The only visible benefit would be faster serial, because the sampling grid that capped 2400 baud is the interrupt period: 12 MHz gives a 9-tick frame that keeps every timing exact and brings 2400 back; 16 and 20 MHz give 12 and 15.
- The clean fast design is run-from-SRAM: a 12 ns 62256-pinout SRAM shadowing the EEPROM, a spare bank-register bit as the shadow select, F or AC decoders. About 2.5 times today's throughput. A project on its own, if ever.

## 9. Dongle follow-ups

- **ESPHome config:** `serial_proxy` at 1200 baud with `tx_pin` `inverted: true` only; `remote_receiver` on IO7 with `dump: raw` to read a NIR's remote through U5B; `power_save_mode: light`, since the sign's 10 Ω R31 caps the average current near 130 mA. Bridge R31 on the sign if a dongle ever browns out.
- **IR keystroke injection** on a receiver-less NET: close JP2, drive pin 1 from IO2 with the encoder in [tools/cc784_ir.py](tools/cc784_ir.py). Never on a NIR, where the HC14 drives that net.
- **Remote decoding on the ESP:** the frame format is known ([firmware notes §8](CC784_firmware.md#8-ir-remote-decoder-ir_-14821571-h--verified-against-a-capture-of-the-signs-own-receiver)); a custom `remote_receiver` protocol would turn remote keypresses into Home Assistant events.
- **Declined, recorded:** the LM66200 ideal diode in place of the two MBR120s (better headroom, but raises the WS2812's data threshold above 3.3 V unless the LED keeps a diode of its own); a solder jumper to run the LED from 3.3 V (out of the LED's VDD spec by 0.2 V, blue may be weak).

## 10. Other models

The CC710 runs the NET's code base on the `CC784-3A` board ([firmware notes §14](CC784_firmware.md#14-the-cc710-firmware-h--from-a-rom-dump-id-710), [hardware notes §11](CC784_hardware.md#11-the-cc784-3a-board-cc710-h)). As shipped it cannot run the patched firmware: 2 KB of RAM in a 24-pin socket against the 16 KB the patched build uses. [Hardware notes §12](CC784_hardware.md#12-converting-a-cc784-3a-board-to-a-cc784-4) turns the board into a `CC784-4` (RAM, the later power-fail detect, a DB9 cable), after which the patched firmware runs on it, though the CC710's 59-column panel would need display changes. As it is, two things it could still get:

- **A dongle on its header.** Packet mode needs the boot probe answered (SK1 pins 5, 4, 9) and the CTS/ready lines honoured (SK1 pins 8 and 7 high for TX; pin 4 is the sign's ready). An ESP on the header could do all of that in software, and the CC710 answers queries `0`–`3` once in packet mode. For bench tests there is a way in without an adapter: hold `1`, `7` or `U` on the keypad at power-up (address `*`).
- **Small patches of its own** (16 KB ROM, 3.9 KB free): the address-inversion bug in the probe's keep path, and the `17` AM/PM handling, if the sign is ever used with a host.
## 11. A configuration store

The block itself exists since patch 35 ([patched notes](CC784_patched.md#2-patches)): sixteen battery-backed bytes with a signature and a sum, written with `B6 index value`, read with `B4 '5'`, carrying brightness, mute, the spare-line roles, the alert channel, hold time, flash rate, beeper and remote lock. Settings it reserves bytes for but does not act on yet:

| Setting | Values | Default | Notes | ROM |
|---|---|---|---|---|
| Status reports | on, off | off | the sign emits a short frame on TX at each channel start, naming the channel, so a dongle knows exactly what is playing; the boundary line (§1) only says that something started. Framed like a query reply with a type byte, so the host tool can skip them while waiting for an ACK. Off by default because unsolicited bytes break the request-reply model for a stock host. In a chain (§2) they stay allowed but are best effort: a report is dropped when the link is busy at the moment it would be sent, and one that collides with a forwarded reply fails the host's checksum. A sign defers its own report while it is forwarding, which removes most collisions | ~40 |
| Clock source | auto, mains, crystal | auto | overrides patch 31's boot-time detection on the add-in board | ~8 |
| Night schedule | start, end, level | off | the clock-based night mode of §5 as three bytes in the reserved space instead of its own editor dialog | ~40 |
| Chain forwarding | on, off | off | the bit repeater of §2 | 1 |

The live bits of the flags byte (alert playing, editor open, wrapped) sit outside the sum so they can change without a reseal; the clock and the sequence beside the block are outside it for the same reason, and the sequence is read with `B4 '6'`.

**Status report format.** Sent like a query reply, `B1 addr len payload cksum`, with a three-byte payload:

| Byte | Content |
|---|---|
| 0 | `'S'`, the type, so a host waiting for an ACK or a query reply can tell a report from either by its first byte |
| 1 | channel now starting, 0 to 99, `0x64` for the demo; `0xFF` playback stopped |
| 2 | flags: bit 0 the sequence wrapped to its start; bits 1 and 2 brightness (off, low, medium, full); bit 3 muted; bit 4 mute pending at the end of this message; bit 5 the alert channel is playing; bit 6 the on-sign editor is open |

Sent at the start of every message, at the end of playback when it stops (a pending mute, an empty sequence), and whenever a flag changes for a reason the host did not cause, such as the hardware mute line or the remote opening the editor. The shortest message holds the panel for about two seconds, so that is the peak rate: six bytes every two seconds, 50 ms of line time at 1200 baud.
