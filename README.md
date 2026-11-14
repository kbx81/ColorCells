# Color Cells CC784 LED sign

Reverse engineering, documentation and firmware work for the Color Cells / Innovative Sign Technology **CC784** family of scrolling LED signs (1990–1993): the **CC784NIR** ("NIR"), which has an infrared remote, and the **CC784NET** ("NET"), which has a wired, plug-in keypad which connects to the sign's DB9 that both models use for serial communication. Both are the same `CC784-4` controller board.

The ten-channel **CC710** (same code base on the earlier `CC784-3A` board, a 10-pin header instead of the DB9, a 7×59 panel) is covered too: its firmware source, board notes and wire differences are in the same files. Its panel is shorter than the CC784's, and it appears to be rare: no other unit or documentation has turned up. The *original* CC784 (10 memory banks, 6 colors, 10-pin connector, also a `CC784-3A` board) is covered the same way; its firmware is the oldest of the four, and [firmware notes §1](firmware.md#1-lineage-of-the-stock-firmware-m--from-the-four-roms-their-labels-and-the-boards) traces the line from it through the CC710 and the NET to the NIR.

## The hardware

A Z80 with 16 K of firmware in an EPROM, an 8 K battery-backed SRAM that holds the message store, and 74LS/HC glue: a 74LS273 control latch, a second '273 color latch, 74LS151 selectors for the row data, an HC4020 that makes the timer interrupt and acts as a watchdog, and a 74LS244 that is both the serial output driver and the input port. The panel is two PCBs of 7 × 42 LEDs, red and green alternating per column, fed as one 84-stage 74LS164 chain through ULN2003 column drivers, with seven TIP125 row transistors. The DB9 carries a bit-banged serial link, 300 baud on the stock firmware and up to 1200 on the patched one, that works with RS-232 ports without being RS-232 itself: the outputs are TTL straight from the 74LS244, and the one input has a diode clamp rather than a receiver, so a PC port's ±12 V is tolerated and a TTL adapter is probably enough (hardware notes §4).

- **CC784NET:** Z80 at 4 MHz, firmware in a 27128, a keypad on the DB9, no infrared parts. **The firmware decides at power-up whether a PC or a keypad is attached** and acts accordingly.
- **CC784NIR:** Z80 at 8 MHz with the interrupt gating reworked to suit, firmware in the lower half of a 27C256, an infrared receiver on an add-in board inserted next to the display PCBs (with a small window in the front acrylic panel to allow the IR through), and a Motorola MC14497 PCM remote at 31.25 kHz.

To turn a NET into a NIR, follow [upgrades.md](upgrades.md) §4.

## The firmware

16 K of Z80 code: a timer-driven display scanner with four-level brightness by time slicing, a bit-banged serial receiver and transmitter, a packet parser for the PC protocol, a 100-channel message store with a sequence list, a renderer with fonts, effects, colors and a "MAGIC" auto-coloring mode, an on-sign editor driven from the remote or a terminal, a real-time clock from the mains frequency, and on the NIR an infrared decoder.

## What has been done

- **Firmware dump and reconstruction.** The NIR's ROM was dumped, disassembled and turned into an annotated source that reassembles byte for byte ([src/stock/cc784nir.asm](src/stock/cc784nir.asm)). Every routine and variable is named; the notes record what each does and how confident the reading is. The NET, CC710 and original CC784 ROMs are dumped and compared against it, which explains the keypad, the factory cable's wiring and the 4 MHz timebase; the original CC784's is the oldest code base of the four.
- **Serial protocol.** Recovered from the original DOS software (`NETCC.EXE`) and the firmware, verified against the sign.
- **Hardware.** The whole controller board is captured in KiCad from the PCB, with the factory bodge wires, the DB9 pinout, the panel connector, the battery path and the timebase explained. An add-in board replaces the NIR's IR receiver board and adds a 32.768 kHz clock source for signs on a DC supply ([hardware/CC784NIR_IR+Clock/](hardware/CC784NIR_IR+Clock/)).
- **Thirteen stock firmware bugs** found and documented, from a `0x20` payload byte that releases a WAIT to the one that counts as a remote exploit: a single query frame on the serial line overflows the 64-byte stack into the ROM, the matching pops read ROM bytes back as return addresses, and the CPU runs off into whatever they point at.
- **An emulator** ([tools/cc784_sim.py](tools/cc784_sim.py), on kosarev's Z80 core) with the serial line, the IR receiver, the mains tick, the watchdog and the EEPROM modeled, used as the regression gate for every firmware change.
- **A patched firmware** ([src/patched/cc784nir.asm](src/patched/cc784nir.asm)): patches that fix the bugs, support a 32 K RAM for a 15 K message store, add over-the-air firmware updates through the serial link into an A/B EEPROM layout with a boot stub, trial boots and rollback, process packets without blanking the display or going deaf, run the serial link at 300 to 2560 baud as the host chooses (the stock DOS software still works at 300), keep every row lit at the slow scroll speeds, add a 24-hour clock, set the clock to the second, keep a configuration block (brightness, mute, hold and flash timing, beeper, remote lock) that the host can read and write, take the clock from the add-in board's crystal when there is no mains cycle to count, and scan the NET's wired keypad alongside the remote, switching between keypad and serial by itself. Both signs run it, and so does the CC710 on a converted board, from a build for its 59-column panel.
- **Host tools** for loading messages, setting the clock, querying and dumping the sign, pushing firmware, and encoding remote keystrokes, over a USB serial adapter or an [ESPHome serial proxy](https://esphome.io/components/serial_proxy/).
- **The remote** decoded from a logic-analyzer capture and the firmware: frame format, key map, carrier.

## Documentation

| Document | Covers |
|---|---|
| [hardware.md](hardware.md) | The controller board: parts, decoding, timebase and watchdog, serial port and DB9, display drive, panel, connectors, power and battery, bodge wires; the earlier `CC784-3A` board (CC710), its keypad and panel, and converting it to a `CC784-4` |
| [firmware.md](firmware.md) | The stock firmware as a reference: how the four signs' ROMs descend from one another; the NIR's in full (memory map, execution model, serial link, packet parser and commands, store format, renderer, IR decoder, editor, bugs); the NET, CC710 and original CC784 by their differences |
| [protocol.md](protocol.md) | The serial protocol: frames, commands, message bytes, attributes and colors, queries |
| [patched.md](patched.md) | The patched firmware: memory map, the patch list, what was rejected, what has been verified on the sign, how to rebuild and test |
| [ota.md](ota.md) | Over-the-air updates: the EEPROM and bank-register hardware, the ROM layout and boot stub, the OTA commands, using the tools, testing, gotchas |
| [upgrades.md](upgrades.md) | Upgrade guide: the EEPROM and bank register, the RAM, converting a NET board, with the bench checklists; converting a `CC784-3A` board is in the hardware notes §12 |
| [ideas.md](ideas.md) | Parked work with its sizing and decisions: the spare DB9 lines, chaining signs, scrolling in other directions, keypad support, faster CPUs |
| [hardware/CC784-4/](hardware/CC784-4/) | KiCad project: schematic and PCB of the `CC784-4` controller board (NIR and NET) |
| [hardware/CC784-3A/](hardware/CC784-3A/) | KiCad project: the earlier `CC784-3A` controller board (CC710) |
| [hardware/CC784NIR_IR+Clock/](hardware/CC784NIR_IR+Clock/) | KiCad project: the IR receiver and clock add-in board |
| [hardware/CC784-ESP32-C6_dongle/](hardware/CC784-ESP32-C6_dongle/) | KiCad project: the ESP32-C6 serial dongle for the DB9 |

Source and tools:

| Path | What |
|---|---|
| [src/stock/](src/stock/) | The stock firmware of all four signs, each reassembling to its dump: NIR (`md5 c021af14…`), NET (`872c8793…`), CC710 (`f346d39e…`), original CC784 (`3e7a679f…`); same labels throughout |
| [src/patched/](src/patched/) | The patched firmware; `Build patched ROM` and `Pack OTA image` tasks produce the bank image for `push` and the chip image for a programmer |
| [tools/cc784.py](tools/cc784.py) | Talk to a sign over serial: messages, clock, sequence, queries, dump; `--channels 10` for the CC710 |
| [tools/cc784_esphome.py](tools/cc784_esphome.py) | As above but through an [ESPHome serial proxy](https://esphome.io/components/serial_proxy/) |
| [tools/cc784_lint.py](tools/cc784_lint.py) | Checks a message before it is loaded: composition rules (colors only on sideways motion, wipes and scrolls ended by LEFT, no trailing spaces, THIN, background spacing) and each effect page's width at 86 and 60 columns, measured by the patched firmware in the emulator, with the fields' values given by `--field` |
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
