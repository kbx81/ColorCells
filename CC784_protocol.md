# Color Cells CC784 / CC6x7 LED sign — serial protocol

Reverse-engineered from `NETCC.EXE` (NETCC USA v3.0, © 1991 Color Cells Ltd /
Innovative Sign Technology; compiled QuickBASIC 4.x, EXEPACK-compressed).

Everything below is for the **CC784 / CC6x7 family** ("CC784NET" / "CC784NIR",
model type 1 in the program). Where the program does something different for
the NC900-series network controllers (model type 2, internal code 5) it is
noted in *italics* so you can ignore it.

Confidence: **high** for framing, checksum, ACK/NAK, message/clear/sequence
packets and the attribute code table (all read directly from the code and
DATA statements). **Medium** for the meaning of a few individual bytes that
the program only ever emits as constants (marked "?").

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

The program sends **one byte at a time with a ~50 ms pause after each byte**.
The firmware shows this is *not* required: reception is interrupt-driven into
an 8-byte FIFO. What *is* required is not sending the next frame until the
sign has ACKed the previous one (see §8).

For the ESP32: TX → sign RX via an RS-232 driver (MAX3232 etc.), plus RX for
the ACK byte. Nothing else is required.

---

## 2. Frame format

Every transmission to the sign is one frame:

```
 B1  <addr>  80  <len>  <payload ...>  <cksum>
 └─ header (4 bytes, not checksummed) ─┘
```

| Byte | Meaning |
|---|---|
| `0xB1` | Start of frame (constant) |
| `addr` | Sign address as a **binary byte** (whatever is set on the sign's address switch/menu). `0x2A` (`*`) is used as the broadcast "all signs" address; the program does not wait for an ACK when using it. |
| `0x80` | Constant. Firmware stores it and, if it is exactly `0x80`, processes the packet immediately instead of deferring to the main loop. No other effect (see §8). |
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

After the checksum byte the program waits (default 7 s, 2 s in some modes)
and reads what has arrived:

| Byte | Meaning |
|---|---|
| `0x06` (ACK) | Frame accepted |
| `0x15` | NAK — bad checksum (**firmware-verified**; NETCC's source looked for `0x0F`, which the CC784 never sends) |
| anything else / nothing | treated as error |

On anything but ACK the input buffer is flushed and the **same frame is
re-sent, up to 3 attempts total**, then "sign not responding" is reported.

Query frames (§4.5) are answered with ACK **followed by a frame in the same
format** (`B1 addr ... cksum`); the program validates it with exactly the same
checksum rule (sum of bytes 5..N-1 mod 256 == byte N) and checks that byte 2
equals the sign address.

---

## 3. Long messages: splitting into 250-byte chunks

If the *message* payload (§4.1) is ≤ 255 bytes it is sent as a single frame
with the payload exactly as built.

If it is longer, the program removes the 4-byte message-header prefix
(`09 '0' c 0E`) from the front and then sends the remainder in **chunks of
250 bytes**, each wrapped as:

```
B1 addr 80 <chunklen+4>  09  '0' c  <type>  <chunk>  cksum
```

* `type` = `0x0E` for the **first** chunk (same as the normal message header)
* `type` = `0xB3` for every **continuation** chunk

So the sign sees "message header with type 0x0E" then "append, type 0xB3".
The length byte is `LEN(chunk) + 4` because the four bytes `09 '0' c type`
are counted.

---

## 4. Payloads (CC784 constants)

The program builds every payload as `SOH … CR` and then strips the SOH and CR
before framing, so the payloads below are what actually goes on the wire.

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

Channels are `00`–`99`, always written as **two ASCII digits**; the sign stores
them as a two-byte marker `D0+tens D0+units`. Channel 100 is the read-only
built-in demo. All channels share one 6 625-byte pool (no per-channel limit).
**A channel header `09 d d` must be followed by `0E` (replace) or `B3`
(append) before any text** — on its own it leaves the insertion point on the
channel marker and the text would corrupt it.

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

Example (address 1, channel 0, text `HELLO`, no remark, display it):

```
B1 01 80 0C | 09 30 30 0E 48 45 4C 4C 4F 04 30 30 | 9F
```

### 4.2 Clear a channel

Same as a message with an empty body — i.e. just channel headers:

```
09 '0' c 0E   [09 '0' c 0E …]      one group per channel to clear
```

Clear **all** channels (`'A'` in the menu): payload is the single byte `03`.

### 4.3 Set display sequence

```
04  '0' c1  '0' c2  '0' c3 …       channels in the order to display
```

(`"A"` = all → `04 30 30 30 31 30 32 … 30 39`.)

### 4.4 Set the clock

```
17  H H  M M  a
```

`HH` = hour **1–12** (zero padded, ASCII), `MM` = minutes (ASCII),
`a` = `'Y'` for AM, `'N'` for PM. Only the time is sent; the CC784 has no
date command in this program (*the NC900 build sends a longer binary
date/time record*).

Example 9:41 AM → `17 30 39 34 31 59` → frame `B1 01 80 06 17 30 39 34 31 59 <sum>`.

### 4.5 Status / "what's in the sign" query

```
17 32          ( 0x17 '2' )
```

Sent by the "Messages in sign" / "Check sequence usage" screens. The sign
replies ACK then a frame whose payload the program scans for `B0 … B0`
remark blocks (name/date/size) to build the listing, and reads a "remaining
memory" figure. Exact reply layout was not fully decoded — capture one and
it should be self-explanatory given the remark format above.

---

## 5. In-text control codes (CC784 / CC6x7 column of the program's table)

These are single bytes embedded in the message body. The editor letter is
what you type after the attribute key in NETCC; the code is what is sent.

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

| Editor | Name | Byte |
|---|---|---|
| C | Crawl on | `0x18` (24) |
| J | Jump | `0x19` (25) |
| D | Wipe down | `0x1B` (27) |
| U | Wipe up | `0x1A` (26) |
| W | Wipe back | `0x0F` (15) |
| M | Magic | `0x1F` (31) |
| P | Pause 1 s | `0x06` (6) |
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
| E, K, O, Q, V | Sync, sync&crawl, var. space, blank, date | **not supported on CC6x7** (listed "(LK)" = later models only) |

### 5.5 Colours

The editor keys are `R O Y L G B` (foreground) and `r g y b` (background).

Foreground: `0x80 | (red<<2) | green`, red/green intensity 0–3:

| Editor | Colour | Byte |
|---|---|---|
| B | Black (off) | `0x80` |
| R | Red | `0x8C` |
| O | Orange | `0x8D` |
| Y | Yellow | `0x8F` |
| L | Lime | `0x87` |
| G | Green | `0x83` |

Background `0x90 | n`:

| Editor | Colour | Byte |
|---|---|---|
| b | Black | `0x90` |
| r | Red | `0x91` |
| g | Green | `0x92` |
| y | Yellow | `0x93` |

Other foreground combinations in `0x80`–`0x8F` (e.g. `0x84`, `0x88`, `0x8E`)
are probably valid dimmer shades — worth trying.

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

Note several graphic bytes collide with attribute bytes (e.g. `0x1B` is both
"left arrow" and "wipe down"); presumably the sign interprets them by
context (the program emits graphics only right after `0xB8`?). Test before
relying on them.

*(NC900/CC900 graphics differ: 3 heart, 2 muncher, 227 phone, 248 wheel,
249 ball, 27 plane, 23 ship, 127 house, 232 car.)*

---

## 6. Suggested ESP32 send routine

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

## 7. Things worth verifying on real hardware

1. Whether the sign actually needs the 50 ms inter-byte gap.
2. Whether the trailing `04 '0' c` is required for the message to appear, or
   the sign displays the loaded channel by default.
3. The `0x80` header byte — try `0x00`/`0x01` to see if it is a source
   address (would matter only for multi-sign networks).
4. Reply format to `17 32` (the NETCC listing shows name/date/size per channel
   and a "Remaining" byte count).


---

## 8. What the sign firmware says (CC784NIR EPROM, 32 KB, code in first 15 KB)

I disassembled the Z80 image. The findings below override anything above where
they differ; everything here is read directly from the code.

### 8.1 Hardware as inferred

* Z80, ROM 0x0000–0x3BFF, RAM 0x4000–0x5FFF (top of RAM 0x5EF1–0x5FFF is the
  packet receive buffer + parser state). Sign address is kept in RAM with a
  complement byte, i.e. it survives power-off only if RAM is battery-backed.
* **Serial is fully bit-banged.** RX is sampled on I/O port `0xC0` bit 3, TX
  is bit 4 of a latch at memory address `0x8000`. Timing: 8 MHz crystal →
  74HC4020 ÷1024 → 7812.5 Hz interrupt; the bit engines run every 6th
  interrupt (1302 Hz) with a 4,4,5-tick bit table ⇒ 300.5 baud.
  **So the baud rate is hard-wired to 300**; the 1200–9600 options in NETCC are
  for other models. 8 data bits, no parity; the sign checks one stop bit on
  receive and sends about two on transmit.
* Port `0xC0` bit 1 is an IR remote receiver (pulse-width decoded state
  machine) — that is the "NIR" part. Ports `0x48`–`0x4F` + `0x80` drive the
  LED matrix (86 columns).
* An NMI-driven clock from the 60 Hz mains keeps the time (needs an AC adapter).
* RAM (HY6264, 8 KB) is not battery-backed on this unit — address and messages
  are lost at power-off.
* ROM ID string at 0x0048: `78409O1702930205`.

### 8.2 Frame parser (confirms §2)

```
idle ──B1──> addr ──> flag(0x80) ──> len ──> len×payload ──> cksum
```

* Checksum is the 8-bit sum of the payload bytes only — exactly as NETCC does it.
* The address byte must equal the sign's own address, **or be `0x2A`**.
  Anything else: the frame is silently discarded, no NAK.
* Reply: `0x06` if checksum OK, `0x15` if not. **Broadcast (`0x2A`) frames get
  no reply at all** but are still processed.
* `len = 0` is legal (just ACKs).
* After the ACK is fully shifted out, the packet is processed **with
  interrupts disabled**, so any bytes arriving during processing are lost.
  Wait for the ACK, then a little longer, before the next frame. For broadcast
  frames (no ACK) pad ~0.5 s between frames.
* **Default address is 0.** If the RAM has lost its contents (very likely after
  20 years) the sign only answers to `addr = 0x00` or `0x2A` until you set an
  address from its own menu. NETCC's "address 1" will be ignored. Use `0x2A`
  to get started.

### 8.3 Payload command set — the complete list

The parser walks the payload byte by byte. Anything not listed is inserted
into the current message as text/attribute data.

| Byte(s) | Action |
|---|---|
| `00 01 05 08 0A 0B 0C 1C 1D 7F` | Ignored |
| `02 n` | Speed = `0xF0 \| (n & 7)` (alternative to sending `F0`–`F7` directly) |
| `03` | Clear all messages |
| `04 d d [d d …] ['D'\|'d']` | Display sequence; each channel is **two ASCII digits (00–99)**; optional `D`/`d` terminator |
| `09 d d` | Select channel `dd` (00–99) and set insertion point at its start |
| `0D` | End of packet (stop parsing) |
| `0E` | Delete existing content of the selected channel (so `09 dd 0E` = "replace") |
| `15 n` | Foreground colour by index, n = 0–9 → `8C 8D 8F 87 83 84 8E 80 8B 81` |
| `16 n` | Background colour by index, n = 0–5 → `91 93 93 93 92 90` |
| `17 h h m m a` | Set clock: 4 ASCII digits HHMM, `a` = `Y`/`y` AM, anything else PM. (Bug: a truncated `17` stops the clock.) |
| `1E n` | Insert byte `0xA0 \| (n & 15)` (an alternate colour range, see below) |
| `B3` | Continuation: move insertion point to the end of the selected channel (append) |
| `B4 '0'` | Reply with the 16-byte ROM ID string |
| `B4 '1'` | Reply with two 5-digit ASCII numbers: total and free message memory |
| `B4 '2'` | No-op |
| `B4 '3'` | Reply with a dump of the whole message store (see 8.4) |

So the NETCC-style status query (`17 32`) does nothing useful on this
firmware — that screen was for the network models. Use `B4 '1'` / `B4 '3'`.

### 8.4 Reply frames

```
B4 '0' / '1' :  B1 <addr> <len> <payload> <sum of payload>
B4 '3'       :  B1 <addr> <5 ASCII digits = byte count> <dump…> <sum of dump only>
```

Note: **no `0x80` byte in replies**, and the `'3'` reply's checksum excludes
the 5-digit count. The dump is the sign's internal store: `D0`+n marks the
start of channel n, `03` terminates a channel, `DA` ends the store; NETCC's
`B0 … B0` remark blocks appear verbatim inside.

### 8.5 Rendering codes recognised by the display engine

Confirms the NETCC table (§5) and adds a few:

| Byte | Meaning |
|---|---|
| `10` large, `11` normal, `12` bold, `13` italic, `14` flash, `1F` magic | as §5 |
| `18` crawl, `19` jump, `1A` wipe up, `1B` wipe down, `0F` wipe back | as §5 |
| `06` pause, `07` beep, `03` end of channel | as §5 |
| `5F` | display time |
| `80`–`8F` | foreground colour (`0x80 \| red<<2 \| green`) — all 16 values are accepted |
| `90`–`9F` | background colour |
| `A0`–`AF` | second colour range (used by the `1E n` command; probably the CC900-compatible colours) |
| `F0`–`F7` | speed |
| `B0` remark, `B8` graphic, `BA` wait-key, `BC` rainbow | as §5 |
| `BB` | an extra movement effect not in NETCC (try it) |
| `BD` | restart / reset display state |
| `BE` | an extra display mode not in NETCC (try it) |
| `94`–`9D`, `C0`–`CF`, `E0`–`EF` | extended glyph / graphic characters |

### 8.6 Minimal "hello" using only firmware-verified facts

```
B1 2A 80 09  09 30 30 0E 48 45 4C 4C 4F  EB     (broadcast, channel 00, "HELLO")
```
then, if it doesn't start showing on its own:
```
B1 2A 80 03  04 30 30  64                        (sequence: channel 00)
```
