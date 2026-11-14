# CC784 ideas and parked work

Work not built, with its sizing and the decisions already made. Firmware sizes are estimates against the patched build; the free ROM count is in [patched.md](patched.md#1-memory-map). Sections link to the notes that hold the facts they rely on.

---

## 1. The four spare DB9 lines

Dropped. Every sign has a dongle, and the dongle already does over serial what the lines were for: brightness and mute are configuration bytes (`B6`), an alert is a sequence change sent and later undone, the message boundary is the status report (patch 41, §11), and the heartbeat is a periodic `stats` poll (patch 40): no reply, or an uptime that stops counting, is a hung sign; a boot count that moves is a reboot. The lines also belong to the wired keypad in keypad mode (patch 36), so leaving them alone avoids that conflict. Two are inputs to the sign (`PORT_IN` bits 0 and 2, DB9 pins 2 and 6), two are outputs (`CTRL_LATCH` bits 5 and 6, pins 4 and 7) ([hardware notes §4](hardware.md#4-serial-port-h)); the four role bytes in the configuration block (3–6) stay unused. The chain of §2 would still need pin 2.

## 2. Several signs on one serial link

This is the legacy case: one or two RS-232 ports on a PC and many signs. With a dongle per sign the constraint disappears, and status reports (§11) become the way to follow each sign. The two can be on together; in a chain the reports are best effort. The factory only ever had a transmit-only fan-out: the host's TX to every sign's RX, the `*` broadcast address so nobody replies ([protocol notes](protocol.md)). A return path through the spare input makes it bidirectional.

**Topology.** Host TX fans out to every sign's RX (pin 8). Replies come back up a chain: the last sign's TX (pin 3) goes to the spare input of the sign above it, that sign forwards it onto its own TX, and so on to the host. Only the first sign needs the dongle. No collisions by construction: a packet addresses one sign, so at most one sign transmits, and the forwarding sign is never that one.

**Bit repeater, the cheap version, ~15 bytes.** In the ISR, every interrupt (130 µs): read the upstream input bit and copy it to latch bit 4 unless the sign's own transmitter is active. Polarity needs no inversion: an upstream TX idles low for mark, the input reads 0, and latch bit 4 at 0 is mark. Each hop re-times every edge to the interrupt grid, so each hop adds up to an interrupt of jitter per edge:

| Baud | Bit | Hops before the host's mid-bit sample is at risk |
|---|---|---|
| 300 | 3333 µs | 10 or more |
| 600 | 1667 µs | 5 |
| 1200 | 833 µs | 2; a third is marginal |
| 1920 | 521 µs | 1; a second is marginal |

**Byte-level forwarding, the robust version, ~120 bytes ROM plus a few of RAM.** A second receive engine re-times each byte before the transmitter resends it: unlimited hops at any rate, one byte of latency per hop. Only worth building if a chain grows past three signs.

Caveats:

- The forwarding sign must not hold interrupts off for a fraction of a bit while a downstream reply passes. The remaining long DI windows are OTA page writes, which happen only while the host talks to that sign, so no downstream traffic exists then. The latch and FIFO critical sections are microseconds.
- Every sign needs a unique address. After a RAM loss the patched firmware defaults to 1 ([patched notes](patched.md)), so a battery swap means setting the address again.
- The chain takes pin 2, as a stored setting rather than an autodetect.
- A chained sign running stock NET firmware sees pin 2 low at boot as "a PC is attached", which is correct.

**Alternative with no firmware.** The dongle's header carries UART0. A second sign can hang off TXD0 and RXD0 through its own small level board, and the ESP proxies two sign ports. Wins only for exactly two signs.

## 3. Scrolling right

Built: patch 53 ([patched notes](patched.md#2-patches)), `B2 0F`. A true mirror of the LEFT crawl stays ruled out: it needs the store walked backwards, and the renderer accumulates fonts and colors forwards.

## 4. Wired keypad and the remote lock

The wired keypad is patch 36 ([patched notes](patched.md#2-patches)). Its keys ignore the remote lock; whether they should is a choice for whoever mounts a keypad in public.

## 5. Night mode by the clock

Dim or blank the display between two times of day, set like the clock over serial or from the editor. About 40 bytes. The mute setting (`B6`, configuration byte 2) covers the same need from Home Assistant, so this only matters for a sign without a dongle.

## 6. ROM savings

Nothing open. Dropped: a faster boot CRC, only about 20 percent faster and in need of a chip burn.

## 7. Skip empty channels in the sequence

Built: patch 39 ([patched notes](patched.md#2-patches)).

## 8. Faster CPU: analyzed and shelved

A Z84C0020 is a drop-in at 8 MHz. Faster clocks were worked through and set aside ([hardware notes §2](hardware.md#2-memory-and-io-decoding-h--from-the-schematic)):

- The ROM select is `/MREQ` through the LS139, which leaves 67 ns for the EEPROM at 8 MHz and 12 ns at 16 MHz. No parallel EEPROM or flash reaches that; the AT28HC256-70 is the fastest pin-compatible part and needs two wait states at 16 MHz, one at 12 MHz. The fitted AT28C256-15 needs two waits even at 12 MHz, which hands the gain back.
- The only visible benefit would be faster serial, because the sampling grid that capped 2400 baud is the interrupt period: 12 MHz gives a 9-tick frame that keeps every timing exact and brings 2400 back; 16 and 20 MHz give 12 and 15.
- The clean fast design is run-from-SRAM: a 12 ns 62256-pinout SRAM shadowing the EEPROM, a spare bank-register bit as the shadow select, F or AC decoders. About 2.5 times today's throughput. A project on its own, if ever.

## 9. Dongle follow-ups

- **ESPHome config:** one shared base for every dongle. The UART has `tx_pin` `inverted: true` only, two stop bits, a 16 K `rx_buffer_size` (a whole store dump survives a stalled API connection) and a 1 K `tx_buffer_size` (a whole frame goes in one write); the host tools set the rate, up to 1920, when they connect. `serial_proxy` needs [esphome/esphome#22687](https://github.com/esphome/esphome/pull/22687): before it, bytes read from the sign while the API connection was blocked were lost, which showed as long replies missing a few bytes at 1920 on a busy network. The entities: a Display light (brightness, configuration byte 2), Remote and Beeper switches (bytes 11 and 10), a clock format select and a set-clock button, with the clock sent from Home Assistant's time on the minute. `power_save_mode: light`, since the sign's 10 Ω R31 caps the average current near 130 mA; bridge R31 on the sign if a dongle ever browns out. Not fitted: a `remote_receiver` on IO7 with `dump: raw` could read a NIR's remote through U5B.
- **IR keystroke injection** on a receiver-less NET: close JP2, drive pin 1 from IO2 with the encoder in [tools/cc784_ir.py](tools/cc784_ir.py). Never on a NIR, where the HC14 drives that net.
- **Remote decoding on the ESP:** the frame format is known ([firmware notes §9](firmware.md#9-ir-remote-decoder-ir_-14821571-h--verified-against-a-capture-of-the-signs-own-receiver)); a custom `remote_receiver` protocol would turn remote keypresses into Home Assistant events.
- **Declined, recorded:** the LM66200 ideal diode in place of the two MBR120s (better headroom, but raises the WS2812's data threshold above 3.3 V unless the LED keeps a diode of its own); a solder jumper to run the LED from 3.3 V (out of the LED's VDD spec by 0.2 V, blue may be weak).

## 10. Other models

The CC710 and the original CC784 are `CC784-3A` boards ([hardware notes §11](hardware.md#11-the-cc784-3a-board-h), [§13](hardware.md#13-the-original-cc784s-board-h)), converted to a `CC784-4` by [hardware notes §12](hardware.md#12-converting-a-cc784-3a-board-to-a-cc784-4) (the original with its `/M1` bodge moved first, step 5). Both run the patched firmware with a dongle: the CC710 its own build ([patched.md](patched.md#2-patches), patch 37), the original the standard one, since its panel has the NIR's 84 columns. Their stock firmwares are in [firmware notes §15](firmware.md#15-the-cc710-firmware-h--from-a-rom-dump-id-710) and [§16](firmware.md#16-the-original-cc784-firmware-h--from-a-rom-dump-id-9g). An unmodified 3A board runs the LITE build (patch 51).

## 11. A configuration store

The block itself exists since patch 35 ([patched notes](patched.md#2-patches)): sixteen battery-backed bytes with a signature and a sum, written with `B6 index value`, read with `B4 '5'`, carrying brightness, mute, the spare-line roles, the alert channel, hold time, flash rate, beeper and remote lock. Settings it reserves bytes for but does not act on yet:

| Setting | Values | Default | Notes | ROM |
|---|---|---|---|---|
| Clock source | auto, mains, crystal | auto | overrides patch 31's boot-time detection on the add-in board | ~8 |
| Night schedule | start, end, level | off | the clock-based night mode of §5 as three bytes in the reserved space instead of its own editor dialog | ~40 |
| Chain forwarding | on, off | off | the bit repeater of §2 | 1 |

The live bits of the flags byte (alert playing, editor open, wrapped) sit outside the sum so they can change without a reseal; the clock and the sequence beside the block are outside it for the same reason, and the sequence is read with `B4 '6'`.

**Status reports** are built as patch 41 ([patched notes](patched.md#2-patches)): byte 12, `B1 addr 03 'S' channel flags sum` at each channel start and with channel `FF` when the editor opens, the flags being `CFG_FLAGS` as is. Not built from the design: a report on every flag change, since with the spare lines dropped (§1) nothing else changes behind the host's back.

## 12. Serial rates on whole interrupts

Built for 1920 baud: patch 52 ([patched notes](patched.md#2-patches)). A bit of a whole number of interrupts puts every sample at the same point of its bit; what remains is where the start edge falls between two interrupts:

| Interrupts a bit | Baud | Sample error, bits | Notes |
|---|---|---|---|
| 6.4 | 1200 | ±0.16 | standard; snapped samples |
| 4 | 1920 | −0.25 to 0 | patch 52: the middle falls between two interrupts, and the earlier one is taken |
| 3 | 2560 | ±0.17 | built and tested: about 6 percent of long frames lost to the board's late interrupts, which cost a third of a bit each |
| 2 | 3840 | ±0.25 | the ceiling: a two-interrupt start pulse is hard to tell from noise |

Open: what delays the board's interrupts by one to three periods in the middle of a byte. The emulator shows no stretch with interrupts off longer than about 60 µs, and the remote decoder accounts for part of it on the signs. A lead: `/INT` is the HC4020's Q11, high for only 128 µs ([hardware notes §3](hardware.md#3-timebase-h)), so an acknowledge later than that loses the request and the next comes 384 µs after the last acknowledge, two interrupts late. A count of lost requests on the board would test it. If it is found, 2560 could come back as the fast rate.

Other routes to faster serial:

- **A faster CPU clock** (§8).
- **Q10 for the interrupt** (64 µs, a cut and a jumper at U10 pin 13): 3840 at four interrupts a bit. The request window shrinks to 64 µs, so only the line sample and the counting may run at the full rate and the rest every other interrupt; every constant counted in interrupts changes (`TICK6_DIV`, the display dividers, the lit counts, the remote decoder, the calibration), `RX_FIFO` needs depth, and every board needs the bodge with the firmware. Q9 (32 µs) leaves no time for the handler. Store processing and page writes keep their time, so a push gains far less than the wire does. The watchdog stays on Q13: it counts from the last acknowledge whatever the tap.
- **A hardware UART** (an 82C51 or 16550 class part on a spare I/O port, on the add-in board): whole bytes, the bit engines out of the interrupt, 9600 and up. A hardware project of its own.

## 13. Smoother crawl during loads

The crawl stutters while a load is processed: during 220-byte loads the stall meter (patch 40) shows pauses of up to about 15 frames, more than patch 42's lead of crawl columns covers, and at 1920 they come about once a second. Not yet broken down between the store insert (already one move of the store's tail per run of plain characters, patch 27), the sequence recount and the DONE; timing each part in the emulator comes first. If the insert dominates, processing a frame in slices between display frames is the likely answer.
