# Color Cells CC784 and CC710 LED signs

> [!NOTE]
> **This `main` branch holds only the stock firmware reconstruction.** The exciting bits live on the [**`wip`**](https://github.com/kbx81/ColorCells/tree/wip) branch: the full README, the hardware, firmware and protocol notes, the patched firmware with over-the-air updates, the host tools and emulator, the KiCad projects and the photo gallery.

I've had a CC784NIR since the mid-90s. These signs are based on the Z80, a processor I'm quite familiar with thanks to the Texas Instruments line of graphing calculators (in particular the TI-85 and TI-92). Once I realized that, I just had to do some hacking...someday. I've had a few things I've been wanting to "figure out" for quite a long time now:
- How exactly did that serial packet protocol work?
- How does the hardware work?
- Can I add some features of my own to the firmware?

In early 2026, I was working on building the [serial proxy component for ESPHome](https://esphome.io/components/serial_proxy/) and I was looking for other hardware to test it with. Of course, the CC784 came to mind...but I knew there were some bits I had to figure out before it could really be useful.

Unfortunately, sorting out everything that's going on in a ROM dump and mapping that all back to the hardware can take quite a bit of time and, even once that part is done, hand-writing assembly language is slow-going. Fortunately for us, it's 2026 and we now have these great AI tools to make figuring out just about anything way faster than was ever possible before.

So I threw the sign's old DOS program (`NETCC.EXE`) and a dump of its EPROM at Claude ("the Clanker") and it had a whole lot to say about it! Naturally I jumped down the rabbit hole and got right to reverse engineering, documenting and other firmware work/patches.

This led me to realize that just one sign wasn't going to be enough: when you tear something apart, some questions get answered but then dozens more surface. Curiosity got the better of me and I jumped right over to eBay to see what I could scrape up. I ended up with five signs covering four models, two of them the original CC784 (oldest first):

- **Original CC784:** the `CC784-3A` controller board, ten channels, six colors, a wired keypad on a 10-pin header.
- **CC710:** also the `CC784-3A` board, ten channels, a keypad on a 10-pin header, and a shorter 7×59 panel. It appears to be rare: no other unit or documentation has turned up.
- **CC784NET ("NET"):** the `CC784-4` controller board, a newer revision of the `3A` board, with a DB9 in place of the 10-pin header, for a wired keypad or a PC.
- **CC784NIR ("NIR"):** also the `CC784-4` board, with an infrared remote; with the stock firmware, its DB9 functions only as a serial port.

After a non-trivial amount of poking and prodding the Clanker, I turned some ROM dumps and photos of the PCBs into what you see in this repo:
- [Firmware source by model/version](src/stock/) (on this branch)
- Patched firmware which implements quite a bit of new functionality for the signs, including [OTA firmware updates](https://github.com/kbx81/ColorCells/blob/wip/OTA.md) [**with a hardware mod**](https://github.com/kbx81/ColorCells/blob/wip/UPGRADES.md#2-eeprom-and-bank-register)
- Board schematics, notes and their differences, including the factory bodge wires found on most boards
- [Firmware notes §1](https://github.com/kbx81/ColorCells/blob/wip/FIRMWARE.md#1-lineage-of-the-stock-firmware-m--from-the-five-roms-their-labels-and-the-boards) to trace the line from the original CC784 through the CC710 and the NET to the NIR
- The [serial protocol](https://github.com/kbx81/ColorCells/blob/wip/PROTOCOL.md) and host tools ([tools/](https://github.com/kbx81/ColorCells/tree/wip/tools/)) to load messages, set the clock and query the sign from a PC or through ESPHome
- New hardware: an [IR receiver and clock add-in board](https://github.com/kbx81/ColorCells/tree/wip/hardware/CC784NIR_IR+Clock/) and ESP32-C6 serial dongles for the [10-pin header](https://github.com/kbx81/ColorCells/tree/wip/hardware/CC784-ESP32-C6_dongle/) and the [DB9](https://github.com/kbx81/ColorCells/tree/wip/hardware/CC784NET-ESP32-C6_dongle/)
- Upgrade guides for the [`CC784-4`](https://github.com/kbx81/ColorCells/blob/wip/UPGRADES.md) and for [converting a `CC784-3A`](https://github.com/kbx81/ColorCells/blob/wip/HARDWARE.md#5-converting-a-cc784-3a-board-to-a-cc784-4)
- [Thirteen stock firmware bugs](https://github.com/kbx81/ColorCells/blob/wip/FIRMWARE.md#11-bugs), including one that lets a single serial frame crash the sign
- An [emulator](https://github.com/kbx81/ColorCells/blob/wip/tools/cc784_sim.py) that runs the firmware and serves as the regression gate for every change
- A [gallery](https://github.com/kbx81/ColorCells/blob/wip/GALLERY.md) of the boards, as shipped and modified

Today all five run the patched firmware and talk to Home Assistant through ESPHome serial proxies, and the four converted ones update over the air.

Whatever you want to know about these signs, you can probably find it on the `wip` branch!

## On this branch

[src/stock/](src/stock/) holds the stock firmware of the five ROMs studied, as annotated Z80 sources that reassemble byte for byte to their EPROM dumps. Each is named for its model and ROM revision, and a name means the same routine in all five.

| Source | Sign | ROM ID | md5 of the image |
|---|---|---|---|
| [cc784_9g.asm](src/stock/cc784_9g.asm) | original CC784 | `9g` | `3e7a679f77d7dac121926182442f923a` |
| [cc784_9k.asm](src/stock/cc784_9k.asm) | original CC784, later revision | `78409k0111900019` | `8429b5a4436faf434c18c27e822bd9aa` |
| [cc710_9l.asm](src/stock/cc710_9l.asm) | CC710 | `710` + `09l` | `f346d39e5aa7b49709a717c85d7c7e11` |
| [cc784net_9n.asm](src/stock/cc784net_9n.asm) | CC784NET | `78409n1401920145` | `872c87932339e9e072c5525d30ffb5df` |
| [cc784nir_9o.asm](src/stock/cc784nir_9o.asm) | CC784NIR | `78409O1702930205` | `c021af146a50b93a22d13535201b7eaa` |

How the five descend from one another, and what each one does, is in the firmware notes on `wip` ([FIRMWARE.md](https://github.com/kbx81/ColorCells/blob/wip/FIRMWARE.md)); the comments in the sources refer to them.

## Building

The assembler is [sjasmplus](https://github.com/z00m128/sjasmplus).

```sh
cd src/stock
sjasmplus cc784nir_9o.asm      # -> cc784nir_9o.bin; likewise for the other four
md5 cc784nir_9o.bin            # must match the table above
```

In VS Code, the `Build stock ROM` and `Verify stock ROM is byte-identical` tasks do this for all five.

## Copyright and license

The CC784 firmware is copyright its original owner, Color Cells / Innovative Sign Technology (1990–1993) and whoever holds those rights today. The reconstructed source in [src/stock/](src/stock/) and the patched source on the `wip` branch reproduce that code and are published for preservation, study and interoperability with hardware that has been out of production for three decades. No ROM image, no original software (`NETCC.EXE`) and no dump of any sign is distributed here; the sources assemble to an image only from a sign you own. If you hold the rights to this firmware and object to its presence here, open an issue and it will be taken down.

Everything else, meaning the annotations, the notes, the KiCad captures and the add-in board, the host tools, the emulator and the patches themselves, is original work released under the MIT license in [LICENSE](LICENSE). Color Cells, CC784 and the other model names are used only to identify the hardware.
