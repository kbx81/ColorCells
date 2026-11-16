# Color Cells CC784 LED sign

Reverse engineering, documentation and firmware work for the Color Cells / Innovative Sign Technology **CC700-series** of scrolling LED signs (1990–1993). Four models are covered, oldest first:

- **Original CC784:** the `CC784-3A` controller board, 10 memory banks, 6 colors, a wired keypad on a 10-pin header.
- **CC710:** also the `CC784-3A` board, ten channels, a keypad on a 10-pin header, and a shorter 7×59 panel. It appears to be rare: no other unit or documentation has turned up.
- **CC784NET ("NET"):** the `CC784-4` controller board, a newer revision of the `3A` board, with a DB9 in place of the 10-pin header, for a wired keypad or a PC.
- **CC784NIR ("NIR"):** also the `CC784-4` board, with an infrared remote; with the stock firmware, its DB9 functions only as a serial port.

Each model's firmware source, board notes and wire differences are in the same files. [Firmware notes §1](firmware.md#1-lineage-of-the-stock-firmware-m--from-the-four-roms-their-labels-and-the-boards) traces the line from the original CC784 through the CC710 and the NET to the NIR.

## The hardware

### Common to all four

- **CPU and memory:** a Z80, 16 K of firmware in an EPROM, and a battery-backed SRAM that holds the message store.
- **Glue:** a 74LS273 control latch and a second '273 color latch, 74LS151 selectors for the row data, an HC4020 that makes the timer interrupt and acts as a watchdog, and a 74LS244 that is both the serial output driver and the input port.
- **Panel:** seven rows of LEDs, red and green alternating per column, with ULN2003 column drivers and seven TIP125 row transistors.
- **Serial:** a bit-banged link, 300 baud on the stock firmware; the patched one adds 600, 1200 and 2560 (300 only in its LITE build for an unmodified `CC784-3A`). It works with RS-232 ports without being RS-232 itself: the outputs are TTL straight from the 74LS244, and the one input has a diode clamp rather than a receiver, so a PC port's ±12 V is tolerated and a TTL adapter is probably enough ([hardware notes §2.4](hardware.md#24-host-port-serial-and-keypad-h)).

### The `CC784-3A` board: original CC784 and CC710

- **Memory:** a 2 K 6116 SRAM and a 27128 EPROM.
- **CPU:** Z80 at 4 MHz.
- **Connector:** a 10-pin header carrying the same signals as the `CC784-4`'s DB9, for a keypad or serial.
- **Panel:** 74HC595 shift registers with a latch strobe; two 7 × 42 PCBs on the original CC784, a 7 × 42 and a 7 × 21 (7 × 59) on the CC710.
- **Power-fail lockout:** watches the unregulated rail and trips too late, so switching off can corrupt the store.
- **Factory bodges:** two on the original CC784 (a delayed `/M1` and a beeper capacitor), none on the CC710.

Details in [hardware notes §4](hardware.md#4-the-cc784-3a-board-original-cc784-and-cc710-h); converting one to a `CC784-4` is [§5](hardware.md#5-converting-a-cc784-3a-board-to-a-cc784-4).

### The `CC784-4` board: CC784NET and CC784NIR

- **Memory:** an 8 K 6264 SRAM in the 6116's 24-pin footprint, its four overhanging pins on factory bodge wires ([hardware notes §3.2](hardware.md#32-factory-bodge-wires-h--from-the-schematic)).
- **Connector:** a DB9 in place of the 10-pin header.
- **Panel:** two 7 × 42 PCBs fed as one 84-stage 74LS164 chain, with no latch.
- **Power-fail lockout:** a transistor watching the regulated 5 V.
- **CC784NET:** Z80 at 4 MHz, firmware in a 27128, no infrared parts. **The firmware decides at power-up whether a PC or a keypad is attached** and acts accordingly.
- **CC784NIR:** **the CPU clock doubled to 8 MHz**, with the interrupt gating reworked to suit by a factory bodge. Firmware in the lower half of a 27C256, an infrared receiver on an add-in board next to the display PCBs (with a small window in the front acrylic panel to let the IR through), and a Motorola MC14497 PCM remote at 31.25 kHz.

To turn a NET into a NIR, follow [upgrades.md](upgrades.md) §4.

## The firmware

16 K of Z80 code: a timer-driven display scanner with four-level brightness by time slicing, a bit-banged serial receiver and transmitter, a packet parser for the PC protocol, a message store with a sequence list (100 channels on the `CC784-4` with its 8 K RAM, 10 on the `CC784-3A` with 2 K), a renderer with fonts, effects, colors and a "MAGIC" auto-coloring mode, an on-sign editor driven from the remote or a terminal, a real-time clock from the mains frequency, and on the NIR an infrared decoder.

## What has been done

- **Firmware dump and reconstruction.** All four signs' ROMs were dumped, disassembled and turned into annotated sources that reassemble byte for byte ([src/stock/](src/stock/)): the NIR, NET, CC710 and original CC784. Every routine and variable is named, with one name per routine across all four; the notes record what each does and how confident the reading is. Comparing them explains the keypad, the factory cable's wiring and the 4 MHz timebase; the original CC784's is the oldest code base of the four.
- **Serial protocol.** Recovered from the original DOS software (`NETCC.EXE`) and the firmware, verified against the sign.
- **Thirteen stock firmware bugs** found and documented, from a one-byte typo (`LD (STORE_CURSOR),A` where `HL` was meant) that sends the next insert to a random spot in the store, to the **one that counts as a remote exploit:** a single query frame on the serial line overflows the 64-byte stack into the ROM, the matching pops read ROM bytes back as return addresses, and the CPU runs off into whatever they point at.
- **An emulator** ([tools/cc784_sim.py](tools/cc784_sim.py), on kosarev's Z80 core) with the serial line, the IR receiver, the mains tick, the watchdog and the EEPROM modeled, used as the regression gate for every firmware change.
- **A patched firmware** ([src/patched/cc784nir.asm](src/patched/cc784nir.asm)): patches that fix the bugs, support a 32 K RAM for a 15 K message store, add over-the-air firmware updates through the serial link into an A/B EEPROM layout with a boot stub, trial boots and rollback, process packets without blanking the display or going deaf, run the serial link at 300 to 2560 baud as the host chooses (the stock DOS software still works at 300), slow the crawl by lengthening the panel scan rather than adding dark time, so the slow speeds are no longer dimmer, decode the remote from the edges of its signal rather than fixed sample points, so keys no longer need a second press (stock drops about half the remote's frames), add a 24-hour clock, set the clock to the second, keep a configuration block (brightness, mute, hold and flash timing, beeper, remote lock) that the host can read and write, take the clock from the add-in board's crystal when there is no mains cycle to count, and scan the wired keypad alongside the IR remote, switching between keypad and serial by itself. All signs can run it, though it may require board conversion depending on what you have ([upgrades.md](upgrades.md) for the `CC784-4`, [hardware notes §5](hardware.md#5-converting-a-cc784-3a-board-to-a-cc784-4) for the `CC784-3A`); a build variant accommodates the CC710's 59-column panel.
- **Host tools** for loading messages, setting the clock, querying and dumping the sign, pushing firmware, and encoding remote keystrokes, over a USB serial adapter or an [ESPHome serial proxy](https://esphome.io/components/serial_proxy/).
- **The remote** decoded from a logic-analyzer capture and the firmware: frame format, key map, carrier.
- **Hardware capture.** Both controller boards, the `CC784-4` and the earlier `CC784-3A`, are captured in KiCad from the PCB, with the factory bodge wires, the DB9 pinout, the panel connector, the battery path and the timebase explained. An add-in board replaces the NIR's IR receiver board with a more modern TSOP38230, improving range and reliability, and adds a 32.768 kHz clock source for signs on a DC supply ([hardware/CC784NIR_IR+Clock/](hardware/CC784NIR_IR+Clock/)).

## Documentation

| Document | Covers |
|---|---|
| [hardware.md](hardware.md) | The controller boards: the four signs side by side; the common design (parts, decoding, timebase and watchdog, host port and keypads, display drive and panels, connectors, power and battery) with the differences called out; the `CC784-4`'s NET and NIR builds and factory bodges; the `CC784-3A`'s differences, power-fail fault and the original CC784's modifications; converting a `CC784-3A` to a `CC784-4` |
| [firmware.md](firmware.md) | The stock firmware as a reference: how the four signs' ROMs descend from one another; the NIR's in full (memory map, execution model, serial link, packet parser and commands, store format, renderer, IR decoder, editor, bugs); the NET, CC710 and original CC784 by their differences |
| [protocol.md](protocol.md) | The serial protocol: frames, commands, message bytes, attributes and colors, queries |
| [patched.md](patched.md) | The patched firmware: memory map, the patch list, what was rejected, what has been verified on the sign, how to rebuild and test |
| [ota.md](ota.md) | Over-the-air updates: the EEPROM and bank-register hardware, the ROM layout and boot stub, the OTA commands, using the tools, testing, gotchas |
| [upgrades.md](upgrades.md) | Upgrade guide: the EEPROM and bank register, the RAM, converting a NET board, with the bench checklists; converting a `CC784-3A` board is in the hardware notes §5 |
| [ideas.md](ideas.md) | Parked work with its sizing and decisions: the spare DB9 lines, chaining signs, scrolling in other directions, keypad support, faster CPUs |
| [hardware/CC784-4/](hardware/CC784-4/) | KiCad project: schematic and PCB of the `CC784-4` controller board (NIR and NET) |
| [hardware/CC784-3A/](hardware/CC784-3A/) | KiCad project: the earlier `CC784-3A` controller board (CC710 and original CC784) |
| [hardware/CC784NIR_IR+Clock/](hardware/CC784NIR_IR+Clock/) | KiCad project: the IR receiver and clock add-in board |
| [hardware/CC784-ESP32-C6_dongle/](hardware/CC784-ESP32-C6_dongle/) | KiCad project: the ESP32-C6 serial dongle with a 10-pin header, for the `CC784-3A` signs |
| [hardware/CC784NET-ESP32-C6_dongle/](hardware/CC784NET-ESP32-C6_dongle/) | KiCad project: the ESP32-C6 serial dongle with a DB9, for the `CC784-4` signs |

Source and tools:

| Path | What |
|---|---|
| [src/stock/](src/stock/) | The stock firmware of all four signs, each reassembling to its dump: NIR (`md5 c021af14…`), NET (`872c8793…`), CC710 (`f346d39e…`), original CC784 (`3e7a679f…`); same labels throughout |
| [src/patched/](src/patched/) | The patched firmware; `Build patched ROM` and `Pack OTA image` tasks produce the bank image for `push` and the chip image for a programmer |
| [tools/cc784.py](tools/cc784.py) | Talk to a sign over serial: messages, clock, sequence, queries, dump; `--channels 10` for stock ten-channel firmware, `--lite` for the patched LITE build |
| [tools/cc784_esphome.py](tools/cc784_esphome.py) | As above but through an [ESPHome serial proxy](https://esphome.io/components/serial_proxy/) |
| [tools/cc784_lint.py](tools/cc784_lint.py) | Checks a message before it is loaded: composition rules (colors only on sideways motion, wipes and scrolls ended by LEFT, no trailing spaces, THIN, background spacing, FLUSH in place of runs of spaces) and each effect page's width at 86 and 60 columns, measured by the patched firmware in the emulator, with the fields' values given by `--field` |
| [tools/cc784_font.py](tools/cc784_font.py) | Draws every glyph of the patched firmware's font, read from the assembled ROM, as an HTML page, each labeled with the character codes that draw it (`--cc710` for that build) |
| [tools/cc784_ota.py](tools/cc784_ota.py) | Pack, diff, push, confirm and roll back firmware over the air |
| [tools/cc784_ir.py](tools/cc784_ir.py) | Remote key map and frame encoder, with ESPHome `remote_transmitter` output |
| [tools/cc784_sim.py](tools/cc784_sim.py) | The emulator and its regression commands |
| [.vscode/tasks.json](.vscode/tasks.json) | Build, verify, pack, program and regression tasks |

## Branches

Work happens on the **`wip`** branch; `main` is behind it. Check out `wip` for the current state of the sources, tools and notes.

## Building and testing

The assembler is [sjasmplus](https://github.com/z00m128/sjasmplus); the tools run with `uv`.

```sh
cd src/patched && sjasmplus cc784nir.asm                     # build
uv run tools/cc784_sim.py quiet                              # one regression; see ota.md §6 for the set
uv run tools/cc784_ota.py pack src/patched/cc784nir_patched.bin -o src/patched/cc784nir_bank.bin
uv run tools/cc784_ota.py push src/patched/cc784nir_bank.bin -p /dev/tty.usbserial-XXXX
```

The stock source must keep assembling to the dump's checksum; the `Verify stock ROM is byte-identical` task checks it.

## Copyright and license

The CC784 firmware is copyright its original owner, Color Cells / Innovative Sign Technology (1990–1993) and whoever holds those rights today. The reconstructed source in [src/stock/](src/stock/) and the patched source in [src/patched/](src/patched/) reproduce that code and are published for preservation, study and interoperability with hardware that has been out of production for three decades. No ROM image, no original software (`NETCC.EXE`) and no dump of any sign is distributed here; the sources assemble to an image only from a sign you own. If you hold the rights to this firmware and object to its presence here, open an issue and it will be taken down.

Everything else, meaning the notes, the KiCad captures and the add-in board, the host tools, the emulator, and the annotations and patches themselves, is original work released under the MIT license in [LICENSE](LICENSE). The emulator runs on [kosarev's Z80 core](https://github.com/kosarev/z80), which carries its own license. Color Cells, CC784 and the other model names are used only to identify the hardware.
