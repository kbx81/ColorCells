# Color Cells CC784 LED sign

Reverse engineering, documentation and firmware work for the Color Cells / Innovative Sign Technology **CC784** family of scrolling LED signs (1991–1993): the **CC784NIR** ("NIR"), which has an infrared remote, and the **CC784NET** ("NET"), which has a wired, plug-in keypad which connects to the sign's DB9 that both models use for serial communication. Both are the same `CC784-4` controller board.

To date, I've not yet looked at the *original* CC784 model (same physical dimensions, but with only 10 memory banks, 6 colors, and a 10-pin IDC-style connector instead of a DB9).

## The hardware

A Z80 with 16 K of firmware in an EPROM, an 8 K battery-backed SRAM that holds the message store, and 74LS/HC glue: a 74LS273 control latch, a second '273 colour latch, 74LS151 selectors for the row data, an HC4020 that makes the timer interrupt and acts as a watchdog, and a 74LS244 that is both the serial output driver and the input port. The panel is two PCBs of 7 × 42 LEDs, red and green alternating per column, fed as one 84-stage 74LS164 chain through ULN2003 column drivers, with seven TIP125 row transistors. The DB9 carries a bit-banged serial link, 300 baud on the stock firmware and up to 1200 on the patched one, that works with RS-232 ports without being RS-232 itself: the outputs are TTL straight from the 74LS244, and the one input has a diode clamp rather than a receiver, so a PC port's ±12 V is tolerated and a TTL adapter is probably enough (hardware notes §4).

- **CC784NET:** Z80 at 4 MHz, firmware in a 27128, a keypad on the DB9, no infrared parts. **The firmware decides at power-up whether a PC or a keypad is attached** and acts accordingly.
- **CC784NIR:** Z80 at 8 MHz with the interrupt gating reworked to suit, firmware in the lower half of a 27C256, an infrared receiver on an add-in board inserted next to the display PCBs (with a small window in the front acrylic panel to allow the IR through), and a Motorola MC14497 PCM remote at 31.25 kHz.

To turn a NET into a NIR, follow [CC784_upgrades.md](CC784_upgrades.md) §4.

## The firmware

16 K of Z80 code: a timer-driven display scanner with four-level brightness by time slicing, a bit-banged serial receiver and transmitter, a packet parser for the PC protocol, a 100-channel message store with a sequence list, a renderer with fonts, effects, colours and a "MAGIC" auto-colouring mode, an on-sign editor driven from the remote or a terminal, a real-time clock from the mains frequency, and on the NIR an infrared decoder.

## What has been done

- **Firmware dump and reconstruction.** The NIR's ROM was dumped, disassembled and turned into an annotated source that reassembles byte for byte ([src/stock/cc784nir.asm](src/stock/cc784nir.asm)). Every routine and variable is named; the notes record what each does and how confident the reading is. The NET's ROM was dumped and compared, which explained the keypad, the factory cable's wiring and the original 4 MHz timebase.
- **Serial protocol.** Recovered from the original DOS software (`NETCC.EXE`) and the firmware, verified against the sign.
- **Hardware.** The whole controller board is captured in KiCad from the PCB, with the factory bodge wires, the DB9 pinout, the panel connector, the battery path and the timebase explained.
- **Thirteen stock firmware bugs** found and documented, from a `0x20` payload byte that releases a WAIT to the one that counts as a remote exploit: a single query frame on the serial line overflows the 64-byte stack into the ROM, the matching pops read ROM bytes back as return addresses, and the CPU runs off into whatever they point at.
- **An emulator** ([tools/cc784_sim.py](tools/cc784_sim.py), on kosarev's Z80 core) with the serial line, the IR receiver, the mains tick, the watchdog and the EEPROM modelled, used as the regression gate for every firmware change.
- **A patched firmware** ([src/patched/cc784nir.asm](src/patched/cc784nir.asm)): 25 patches that fix the bugs, support a 32 K RAM for a 15 K message store, add over-the-air firmware updates through the serial link into an A/B EEPROM layout with a boot stub, trial boots and rollback, process packets without blanking the display or going deaf, and set the clock to the second. Both signs run it.
- **Host tools** for loading messages, setting the clock, querying and dumping the sign, pushing firmware, and encoding remote keystrokes, over a USB serial adapter or an [ESPHome serial proxy](https://esphome.io/components/serial_proxy/).
- **The remote** decoded from a logic-analyzer capture and the firmware: frame format, key map, carrier.

## Documentation

| Document | Covers |
|---|---|
| [CC784_hardware.md](CC784_hardware.md) | The controller board: parts, decoding, timebase and watchdog, serial port and DB9, display drive, panel, connectors, power and battery, bodge wires |
| [CC784_firmware.md](CC784_firmware.md) | The stock firmware as a reference: memory map, execution model, serial link, packet parser and commands, store format, renderer, IR decoder, editor, bugs, the NET variant |
| [CC784_protocol.md](CC784_protocol.md) | The serial protocol: frames, commands, message bytes, attributes and colours, queries |
| [CC784_patched.md](CC784_patched.md) | The patched firmware: memory map, the patch list, what was rejected, what has been verified on the sign, how to rebuild and test |
| [CC784_ota.md](CC784_ota.md) | Over-the-air updates: the EEPROM and bank-register hardware, the ROM layout and boot stub, the OTA commands, using the tools, testing, gotchas |
| [CC784_upgrades.md](CC784_upgrades.md) | Upgrade guide: the EEPROM and bank register, the RAM, converting a NET board, with the bench checklists |
| [hardware/CC784NIR/](hardware/CC784NIR/) | KiCad project: schematic and PCB of the controller board |

Source and tools:

| Path | What |
|---|---|
| [src/stock/](src/stock/) | The stock NIR firmware, reassembles to the dump (`md5 c021af14…`) |
| [src/patched/](src/patched/) | The patched firmware; `Build patched ROM` and `Pack OTA image` tasks produce the bank image for `push` and the chip image for a programmer |
| [tools/cc784.py](tools/cc784.py) | Talk to a sign over serial: messages, clock, sequence, queries, dump |
| [tools/cc784_esphome.py](tools/cc784_esphome.py) | As above but through an [ESPHome serial proxy](https://esphome.io/components/serial_proxy/) |
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
uv run tools/cc784_sim.py quiet                              # one regression; see CC784_ota.md §6 for the set
uv run tools/cc784_ota.py pack src/patched/cc784nir_patched.bin -o src/patched/cc784nir_bank.bin
uv run tools/cc784_ota.py push src/patched/cc784nir_bank.bin -p /dev/tty.usbserial-XXXX
```

The stock source must keep assembling to the dump's checksum; the `Verify stock ROM is byte-identical` task checks it.
