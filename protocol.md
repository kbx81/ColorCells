# Color Cells CC784 / CC6x7 LED sign — serial protocol

Reverse-engineered from `NETCC.EXE` (NETCC USA v3.0, © 1991 Color Cells Ltd / Innovative Sign Technology; compiled QuickBASIC 4.x, EXEPACK-compressed).

Everything below is for the **CC784 / CC6x7 family** ("CC784NET" / "CC784NIR", model type 1 in the program). Where the program does something different for the NC900-series network controllers (model type 2, internal code 5) it is noted in *italics* so you can ignore it.

Confidence: **high** for framing, checksum, ACK/NAK, message/clear/sequence packets and the attribute code table (all read directly from the code and DATA statements). **Medium** for the meaning of a few individual bytes that the program only ever emits as constants (marked "?").

---

## 1. Serial settings

Opened as `COMn:baud,n,8,2,cs,ds,cd,bin`:

| Setting | Value |
|---|---|
| Baud | 300 default (menu allows 300/1200/2400/4800/9600; program resets CC784 to 300) |
| Data bits | 8 |
| Parity | none |
| Stop bits | **2** |
| Flow control | none (CTS/DSR/CD ignored) |

The program sends **one byte at a time with a ~50 ms pause after each byte**. The firmware shows this is *not* required: reception is interrupt-driven into an 8-byte FIFO. What *is* required is not sending the next frame until the sign has ACKed the previous one (see §7).

**Connecting anything else** (a microcontroller, a USB adapter, your own cable): a TX line to the sign's RX on DB9 pin 8 and an RX line from the sign's TX on pin 3, ground on pin 5. The sign expects RS-232 polarity; a MAX3232-class driver is the faithful interface, and the [hardware notes §4](hardware.md#4-serial-port-h) explain why plain TTL may do. Nothing else is required on a NIR or on the patched firmware. A CC784NET on its stock firmware also needs sign pins 2 and 5 tied together: its boot-time test reads pin 2 low as "a PC is attached" and otherwise runs in keypad mode and ignores serial ([hardware.md §6](hardware.md#6-connectors)).

---

## 2. Frame format

Every transmission to the sign is one frame:

```
 B1  <addr>  80  <len>  <payload ...>  <cksum>
 └───────────────────┘
 header, 4 bytes, not checksummed; <cksum> = 8-bit sum of the payload bytes
```

| Byte | Meaning |
|---|---|
| `0xB1` | Start of frame (constant) |
| `addr` | Sign address as a **binary byte** (as set in the sign's address menu/configuration). `0x2A` (`*`) is used as the broadcast "all signs" address; the program does not wait for an ACK when using it. |
| `0x80` | Flag. Stock firmware processes the packet immediately if it is exactly `0x80`, else defers it to the main loop (see §7). The [patched firmware](patched.md) processes every packet at its next render step whatever bit 7 says, and bit 0 asks for DONE: with `0x81` the sign sends a `0x04` byte once the packet has been processed and its reply sent, which is the moment it will accept a new frame; a frame sent before that is parsed and ignored. |
| `len` | Number of payload bytes that follow (does **not** include the checksum) |
| payload | 1–254 bytes, see §4 |
| `cksum` | **8-bit additive checksum: sum of all payload bytes, modulo 256.** The 4 header bytes are excluded. No inversion, no two's-complement. |

Reference:

```python
def frame(addr: int, payload: bytes) -> bytes:
    assert 1 <= len(payload) <= 254
    return bytes([0xB1, addr, 0x80, len(payload)]) + payload + bytes([sum(payload) & 0xFF])
```

### 2.1 Reply

After the checksum byte the program waits (default 7 s, 2 s in some modes) and reads what has arrived:

| Byte | Meaning |
|---|---|
| `0x06` (ACK) | Frame accepted |
| `0x15` | NAK, bad checksum (**firmware-verified**). `0x15` is the ASCII NAK character, as `0x06` is ASCII ACK. NETCC's source waits for `CHR$(15)`, decimal 15 = `0x0F`, which the sign never sends: a hex-read-as-decimal slip, so NETCC never notices a NAK |
| anything else / nothing | treated as error |

On anything but ACK the input buffer is flushed and the **same frame is re-sent, up to 3 attempts total**, then "sign not responding" is reported.

Query frames (§4.5) are answered with ACK **followed by a frame in the same format** (`B1 addr ... cksum`); the program validates it with exactly the same checksum rule (sum of bytes 5..N-1 mod 256 == byte N) and checks that byte 2 equals the sign address.

---

## 3. Long messages: splitting into 250-byte chunks

If the *message* payload (§4.1) is ≤ 255 bytes it is sent as a single frame with the payload exactly as built.

If it is longer, the program removes the 4-byte message-header prefix (`09 '0' c 0E`) from the front and then sends the remainder in **chunks of 250 bytes**, each wrapped as:

```
B1 addr 80 <chunklen+4>  09  '0' c  <type>  <chunk>  cksum
```

* `type` = `0x0E` for the **first** chunk (same as the normal message header)
* `type` = `0xB3` for every **continuation** chunk

So the sign sees "message header with type 0x0E" then "append, type 0xB3". The length byte is `LEN(chunk) + 4` because the four bytes `09 '0' c type` are counted.

---

## 4. Payloads (CC784 constants)

The program builds every payload as `SOH … CR` and then strips the SOH and CR before framing, so the payloads below are what actually goes on the wire.

Control bytes used by the CC784 build (the NC900 build uses different ones):

| Name in program | CC784 | *NC900* | Used as |
|---|---|---|---|
| SOH | `0x01` | `0x02` | wrapper only, stripped |
| separator | `0x09` | `0x0B` | starts a channel header |
| type | `0x0E` | `0x09` | message / clear type |
| CR | `0x0D` | `0x10` | wrapper only, stripped |
| EOT | `0x04` | `0x0C` | "display sequence" marker |
| time | `0x17` | `0x0F` | time-set command |
| continuation | `0xB3` | `0x16` | continuation chunk type |
| remark | `0xB0` | `0x13` | hidden comment delimiter |
| clear-all | `0x03` | – | clear all channels |

Channels are `00`–`99`, always written as **two ASCII digits** (the patched firmware also takes one digit after `09` when the next byte is not a digit, or when the pair is past the last channel; its LITE build has channels `0`–`9` and wants one digit each in a sequence, [patched.md](patched.md#2-patches) patch 51); the sign stores them as a two-byte marker `D0+tens D0+units`. Channel 100 is the read-only built-in demo. All channels share one 6625-byte pool (no per-channel limit). **A channel header (CHANNEL, `09 d d`) must be followed by DELETE_TEXT (`0E`, replace) or APPEND (`B3`) before any text** — on its own it leaves the insertion point on the channel marker and the text would corrupt it. The names are the firmware source's `CMD_*` constants; §7.3 lists them all.

### 4.1 Load a message into a channel

```
09 '0' c 0E           channel header  (c = '0'..'9')
B0 <name8> <MMDDYY> <size4> B0
                      "remark" block: 8-char message name (space padded),
                      date as MMDDYY, 4-char size field (space padded).
                      Not displayed; the sign echoes it back so the PC can
                      list what is stored (see §4.5).  You can omit it or
                      fill it with anything.
<text …>              message body: printable ASCII + control codes of §5.
                      Lines of the editor are just concatenated; an empty
                      line becomes a single space.
04 '0' c              optional trailer: "and display channel c now"
```

Trailer variants the program uses (after the body):

* `04 '0' c` — load and start displaying channel *c* ("Send message to channel and display it")
* nothing — load only, no change on the sign ("no change")
* `04 '0' d` — load into *c* but display sequence starting at *d*

`04` is the SEQUENCE command: the trailer replaces the sign's display sequence, so the message appears as soon as the current channel ends. Without it the channel plays when the sequence reaches it, and after a RAM loss the default sequence is channels 0–99, so a load with no trailer still shows up.

Example (address 1, channel 0, text `HELLO`, no remark, display it):

```
B1 01 80 0C | 09 30 30 0E 48 45 4C 4C 4F 04 30 30 | 9F
```

### 4.2 Clear a channel

Same as a message with an empty body, just channel headers:

```
09 '0' c 0E   [09 '0' c 0E …]      one group per channel to clear
```

Clear **all** channels (`'A'` in the menu): payload is the single byte `03`.

### 4.3 Set display sequence

```
04  '0' c1  '0' c2  '0' c3 …       channels in the order to display
```

NETCC sends `"A"` (all) as every channel, `04 30 30 30 31 30 32 … 30 39`, but the firmware lays the full 0–99 sequence down before it parses the digits and stops at the first byte that is not one, so a bare `04`, or `04 41` (`'A'`), means all as well; `cc784.py seq a` sends the bare form.

The patched firmware also takes `04 'M'`: the message channels 00–89, leaving out 90–99, which a message can show inside itself as fields ([patched.md](patched.md#2-patches), patch 54); `cc784.py seq m`.

### 4.4 Set the clock

```
17  H H  M M  a
```

`HH` = hour **1–12** (zero padded, ASCII), `MM` = minutes (ASCII), `a` = `'Y'` for AM, `'N'` for PM. Only the time is sent; the CC784 has no date command in this program (*the NC900 build sends a longer binary date/time record*).

Example 9:41 AM → `17 30 39 34 31 59` → frame `B1 01 80 06 17 30 39 34 31 59 <sum>`.

### 4.5 Status / "what's in the sign" query

```
17 32          ( 0x17 '2' )
```

Sent by the "Messages in sign" / "Check sequence usage" screens. The sign replies ACK then a frame whose payload the program scans for `B0 … B0` remark blocks (name/date/size) to build the listing, and reads a "remaining memory" figure. On the CC784 family firmware `17` is SET_TIME, so `17 32` is a truncated set-time with no reply frame (§7); a host uses QUERY MEMORY and QUERY DUMP instead.

---

## 5. In-text control codes (CC784 / CC6x7 column of the program's table)

These are single bytes embedded in the message body. The editor letter is what you type after the attribute key in NETCC; the code is what is sent.

### 5.1 Letter styles

| Editor | Name | Byte |
|---|---|---|
| N | Normal | `0x11` (17) |
| B | Bold | `0x12` (18) |
| I | Italic | `0x13` (19) |
| L | Large (big) | `0x10` (16) |
| F | Flashing | `0x14` (20) |
| Y | Thin | `0xB9` (185) |
| H | Tall | not supported on CC6x7 |

### 5.2 Movement / effects

NETCC's names for these are not the sign's. The sign's own editor labels each byte (`ATTR_LABEL_TABLE` in the firmware) and its remote has keys for them, so the last column is the name to use; the host tool's `@{...}` escapes follow it. UP, DOWN, RIGHT and HOLD wipe the text that follows them onto the panel; PAUSE puts it up at once and holds it; LEFT is the plain scroll, which also ends a held section when a space alone will not; HALT stops and waits with the text yellowed.

| Editor | NETCC's name | Byte | The sign's name |
|---|---|---|---|
| C | Crawl on | `0x18` (24) | **LEFT** |
| J | Jump | `0x19` (25) | **PAUSE** |
| D | Wipe down | `0x1B` (27) | **DOWN** |
| U | Wipe up | `0x1A` (26) | **UP** |
| W | Wipe back | `0x0F` (15) | **RIGHT** |
| — | not in NETCC | `0xBB` (187) | **HOLD** |
| M | Magic | `0x1F` (31) | MAGIC |
| P | Pause 1 s | `0x06` (6) | **HALT** |
| X | Wait for key | `0xBA` (186) |

### 5.3 Speed

| Editor | Byte |
|---|---|
| 0 (speed 0) | `0xF8` (248) |
| 1 (fastest) | `0xF1` (241) |
| 2 | `0xF2` |
| 3 | `0xF3` |
| 4 | `0xF4` |
| 5 | `0xF5` |
| 6 | `0xF6` |
| 7 (slowest) | `0xF7` (247) |

### 5.4 Miscellaneous

| Editor | Name | Byte |
|---|---|---|
| T | Display time | `0x5F` (95, `_`) |
| S | Sound beeper | `0x07` |
| R | Remark / comment (hidden text, terminated by another `0xB0`) | `0xB0` |
| G | User-drawn graphic follows | `0xB8` (184) |
| A | Rainbow | `0xBC` (188) |
| — | Scroll up / scroll down, the patched firmware's variants of the UP and DOWN wipes: the page pushes the one on the panel out ([patched.md](patched.md#2-patches), patch 48; `@{scroll up}`, `@{scroll down}`) | `0xB2 0x1A` / `0xB2 0x1B` |
| — | Scroll right, the variant of the RIGHT wipe: the page slides in from the left a column a frame and pushes the one on the panel off to the right (patch 53; `@{scroll right}`) | `0xB2 0x0F` |
| — | Glimmer, a patched-firmware modifier for the hold after Pause, a wipe, Hold or a scroll: dark diagonal stripes roll up or down through the page; it goes after the effect ([patched.md](patched.md#2-patches), patch 50; `@{glimmer}`) | `0xB2 0xBB` |
| — | Twinkle, a patched-firmware modifier for the hold after Pause, a wipe, Hold or a scroll: random pixels go dark while the page holds; it goes after the effect ([patched.md](patched.md#2-patches), patch 49; `@{twinkle}`) | `0xB2 0x19` |
| — | Field, the patched firmware's channel inside a message: `B2 '0'`–`B2 '9'` renders channel 90–99 at that point, so the host changes a value by loading that channel ([patched.md](patched.md#2-patches), patch 54; `@{field 0}`–`@{field 9}`) | `0xB2 0x30`–`0xB2 0x39` |
| — | Randbow, the patched firmware's variant of Rainbow: the five colors in a shuffled order ([patched.md](patched.md#2-patches), patch 46; `@{randbow}`) | `0xB2 0xBC` |
| E, K, O, Q, V | Sync, sync&crawl, var. space, blank, date | **not supported on CC6x7** (listed "(LK)" = later models only) |

### 5.5 Colors

The editor keys are `R O Y L G B` (foreground) and `r g y b` (background).

Foreground: `0x80 | (red<<2) | green`, red/green intensity 0–3:

| Editor | Color | Byte |
|---|---|---|
| B | Black (off) | `0x80` |
| R | Red | `0x8C` |
| O | Orange | `0x8D` |
| Y | Yellow | `0x8F` |
| L | Lime | `0x87` |
| G | Green | `0x83` |

Background `0x90 | n`:

| Editor | Color | Byte |
|---|---|---|
| b | Black | `0x90` |
| r | Red | `0x91` |
| g | Green | `0x92` |
| y | Yellow | `0x93` |

The other foreground codes in `0x80`–`0x8F` are the dimmer and mixed shades; all sixteen are named in [firmware.md §8](firmware.md#8-rendering-h).

### 5.6 Built-in graphics (CC600/700 list; editor `G` then letter)

| Key | Graphic | Byte | Key | Graphic | Byte |
|---|---|---|---|---|---|
| a | Left arrow | `0x1B` (27) | i | Circle | `0xF8` (248) |
| b | Car | `0xE8` (232) | j | House | `0x7F` (127) |
| c | Music note | `0x0E` (14) | k | Yacht/boat | `0x17` (23) |
| d | Eye | `0xEC` (236) | l | Pine tree | `0x06` (6) |
| e | Wine glass | `0x9D` (157) | m | Muncher | `0x02` (2) |
| f | Triangle | `0x10` (16) | n | Clock face | `0xE9` (233) |
| g | Diamond | `0x04` (4) | o | Bell | `0xEA` (234) |
| h | Square | `0xDC` (220) | p | Right arrow | `0x1A` (26) |

Note several graphic bytes collide with attribute bytes (`0x1B` is both "left arrow" and "wipe down"); presumably the sign interprets them by context (the program emits graphics only right after `0xB8`?). Test before relying on them.

*(NC900/CC900 graphics differ: 3 heart, 2 muncher, 227 phone, 248 wheel, 249 ball, 27 plane, 23 ship, 127 house, 232 car.)*

The patched firmware draws `0x9F` as a degree sign ([patched.md](patched.md#2-patches), patch 55); `cc784.py` sends `°` as that byte, since Latin-1's `0xB0` is REMARK and would hide the text after it. `tools/cc784_font.py` draws every glyph with the codes that reach it.

---

## 6. A send routine

```python
import time

def send_frame(uart, addr, payload, gap=0.05, timeout=7.0, retries=3):
    f = frame(addr, payload)
    for attempt in range(retries):
        uart.reset_input_buffer()
        for b in f:
            uart.write(bytes([b]))
            time.sleep(gap)
        uart.timeout = timeout
        r = uart.read(1)
        if r == b'\x06':
            return True
    return False

# load "HELLO" into channel 0 and display it
send_frame(u, 1, b'\x09\x30\x30\x0E' + b'\x12HELLO' + b'\x04\x30\x30')
# set clock 09:41 AM
send_frame(u, 1, b'\x17' + b'0941' + b'Y')
# clear channel 3
send_frame(u, 1, b'\x09\x30\x33\x0E')
# sequence 0,2,1
send_frame(u, 1, b'\x04' + b'000201')
```

---

## 7. What the firmware adds

The sign's side of this protocol is read from the firmware itself, and lives in the firmware notes rather than here:

| Topic | Where |
|---|---|
| The fixed 300 baud, the bit-banged receiver and transmitter | [firmware notes §4](firmware.md#4-serial-link-h) |
| The patched firmware's 300 to 1200 baud, and 2560, set by the first frame after a second of silence | [patched.md](patched.md#2-patches), patches 30 and 52 |
| The patched firmware's configuration block: `B6 index value` writes a byte, `B4 '5'` reads the block, `B4 '6'` the sequence list; `cc784.py config` | [patched.md](patched.md#2-patches), patch 35 |
| The patched firmware's health counters in the `B4 '4'` reply; `cc784.py stats` | [patched.md](patched.md#2-patches), patches 40 and 44 |
| The patched firmware's `B4 '1'` reply adds a third five-digit figure, the longest payload a frame may carry: 254, or 128 on a LITE build with 2 K of RAM. A longer frame is dropped unanswered. `cc784.py mem` | [patched.md](patched.md#2-patches), patches 13 and 51 |
| The patched firmware's unsolicited status reports, `B1 addr 03 'S' channel flags sum`; `cc784.py watch` | [patched.md](patched.md#2-patches), patch 41 |
| The patched firmware's serial line carries frames only: a flag byte of `80` or `81` and no gap of a second inside a frame; `18` (BUSY) while the editor is open; `B7 '1'` opens the editor as a serial terminal, `B7 '0'` closes it; `cc784.py stop` and `start` | [patched.md](patched.md#2-patches), patch 45 |
| The frame parser state by state, ACK, NAK and the silent discard of other addresses | [firmware notes §5](firmware.md#5-packet-parser-pkt_st_-16ef178c-h) |
| The complete command list, including the ones NETCC never sends, and the exact reply and dump frame formats | [firmware notes §6](firmware.md#6-packet-processing-and-command-set-pkt_process-2a68-h) |
| Every attribute byte with the sign's own name for it, the color codes, the graphics and the European characters | [firmware notes §8](firmware.md#8-rendering-h) |
| The board, the DB9 and the serial levels | [hardware notes §4](hardware.md#4-serial-port-h) |

Two consequences for a host, both covered in detail there: the NETCC-style status query (`17 32`) is a truncated set-time that does nothing useful (and stops the stock firmware's clock), so use QUERY MEMORY and QUERY DUMP instead; and after a RAM loss the stock firmware answers only at address 0 (the patched firmware at 1) until an address is set, so `0x2A` broadcast is the way to reach an unknown sign.

### 7.1 Minimal "hello" using only firmware-verified facts

```
B1 2A 80 09  09 30 30 0E 48 45 4C 4C 4F  EB     (broadcast, channel 00, "HELLO")
```
then, if it doesn't start showing on its own:
```
B1 2A 80 03  04 30 30  64                        (sequence: channel 00)
```

## 8. The CC710 on the wire

The ten-channel CC710 ([firmware notes §15](firmware.md#15-the-cc710-firmware-h--from-a-rom-dump-id-710)) speaks the same frames through its 10-pin header, with these differences:

- It must be put into packet mode at boot: the probe (data out on SK1 pin 5, clock on pin 4, sampled on pin 9) has to echo the `55` pattern (an inverting echo yields address `*`; other replies give `~D`, and the fallback path gives `D5`, a firmware bug); the NET cable's plain short of DB9 pins 2 and 5 (SK1 pins 9 and 2) gives serial *terminal* mode instead, where bytes are key codes. Without an adapter, holding `1`, `7` or `U` on the keypad at power-up also selects packet mode, with address `*`; holding `Z` + `1` takes the keep path instead, whose bug alternates the address between `D5` and `*` on successive boots [H].
- The transmitter waits for SK1 pins 8 and 7 (DB9 pins 1 and 6) high and the receiver raises SK1 pin 4 (DB9 pin 4) as "ready", dropped while its 8-byte FIFO is full.
- Query `0` returns six ID bytes (`71009l`); query `2` returns the first `B0` remark of each of channels 0–9, 20 bytes maximum each, separated by `19`; the checksum counts each `19` as `B0`, so a sign with no remarks replies `B1 2A 0A`, ten `19`, `E0` [H].
- `09 c` takes one byte (`0`–`9`, `D` demo), `04` one byte per channel (ten at most), `17 hhmm a` takes `A`/`a` for AM, `03` clears ten channels. Channel markers in a dump are single bytes `D0`–`D9`.
- Attributes: HOLD `BB`, RAINBOW `BC`, MAGIC OFF `BD` and TINY `BE` do not exist; the sign names `06` PAUSE, `19` JUMP, `18` CRAWL and `0F` BCRAWL.
- At address `*` (the keypad route) the sign never ACKs, since frames to `*` get no reply; queries still answer [H].
- `cc784.py --channels 10` sends one-digit channel numbers and reads the one-byte markers in a dump [H]. With it, `time` sends `A`/`P` instead of the CC784's `Y`/`N`; `time24` is refused.

Verified on a CC710 [H]: terminal mode through the host cable ([hardware notes §12](hardware.md#3-host-cable)); packet mode by holding `1`, then queries `0`–`3` (query `2` with a remark), `09 c` loads including a 314-byte message split over `0E` and `B3` frames, `04`, `17` and `03`; ACK and NAK at address `D5` after a `Z` + `1` boot; terminal-mode `7E` then `*` opens the editor, and `20` releases a WAIT loaded by packet.

## 9. The original CC784 on the wire

The original keypad CC784 ([firmware notes §16](firmware.md#16-the-original-cc784-firmware-h--from-a-rom-dump-id-9g)) has no packet protocol: none of the frames above reach it. With `PORT_IN` bit 0 low at boot it takes bytes as keys, like the CC710's terminal mode: `01` opens the editor, where bytes are raw ASCII keys echoed on TX and `0D` leaves it; `7E` followed by the byte `MY_ADDRESS` opens the editor, any other byte resets the sign; a `00` resets the sign at any time. Same 300 baud and handshake lines as the CC710. Not tried on the sign.

