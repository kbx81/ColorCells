#!/usr/bin/env python3
"""
cc784.py - talk to a Color Cells CC784 LED sign (300 baud, bit-banged protocol).

    pip install pyserial

Examples
    cc784.py sniff                      # just print whatever the sign sends (wiring check)
    cc784.py --unsafe id                # ROM ID string (B4 '0')   -- see --unsafe!
    cc784.py --unsafe mem               # memory figures (B4 '1')
    cc784.py --unsafe dump              # dump the message store (B4 '3')
    cc784.py msg 0 "HELLO WORLD"        # load channel 0 and display it
    cc784.py msg 1 "@B BOLD @F FLASH @R RED"  # single-letter escapes, see ESC
    cc784.py msg 2 "@{lime}LIME @{d-red}DIM RED @{bg yellow}@{black}ON YELLOW"
                                         # braced: 16 firmware colour names, "bg <colour>",
                                         # "speed N", attribute names, or a raw hex byte @{9f}
    cc784.py clear 0 1 2                # clear channels
    cc784.py clearall
    cc784.py seq 0 1 2                  # display sequence
    cc784.py time                       # set clock from the PC
    cc784.py raw 09 30 30 0e 48 49      # send an arbitrary payload
    cc784.py stop                       # bare 0x01: stop the display, enter the editor
    cc784.py start                      # bare 0x0D: resume running (only if stopped)

Options
    -p PORT      serial device (default /dev/tty.usbserial-110)
    -a ADDR      sign address 0-255 or '*' (default '*' = broadcast, no ACK expected)
    -g SEC       gap between bytes (default 0 - firmware doesn't need one; try 0.05 if flaky)
    -t SEC       reply timeout (default 3)
    -v           hex-dump everything sent/received

'stop' and 'start' send one bare byte each, not a B1 frame: they take the
keystroke path rather than the packet parser, so -a is irrelevant to them and
nothing is ACKed. While stopped the sign is in its editor and accepts typed
characters straight off the wire, so you can compose a message by hand.

Wiring notes: the sign transmits on DB9 pin 3 and receives on pin 2 (DTE-like),
so a PC needs a crossover. If 'sniff' shows nothing and 'id' gets no reply, swap
TX/RX. The sign only ACKs frames sent to its own address; a broadcast ('*')
frame is processed but never answered - except the B4 queries, which always reply.
"""
import sys, time, argparse, datetime

try:
    import serial
except ImportError:          # only needed for the local-port front-end
    serial = None

ACK, NAK, START, DONE = 0x06, 0x15, 0xB1, 0x04   # DONE: patched firmware, after a flag-81 frame

# ---- message escapes -------------------------------------------------------
# Single-letter form:  @B bold, @R red ...   (see ESC)
# Braced form:         @{lime} @{d-red} @{bg red} @{bg yellow} @{9f} @{speed 3}
#   colour names are the firmware's own (menu strings), code = 0x80 + index:
FORE = ['black', 'd-gre', 'm-gre', 'green', 'd-red', 'd-yel', 'd-lim', 'lime',
        'm-red', 'd-ora', 'm-yel', 'lemon', 'red', 'orange', 'gold', 'yellow']
#   i.e. 0x80 | red<<2 | green with red/green intensity 0..3.
BACK = {'black': 0x90, 'red': 0x91, 'green': 0x92, 'yellow': 0x93}
ESC = {
    'N': 0x11, 'B': 0x12, 'I': 0x13, 'F': 0x14, 'L': 0x10, 'M': 0x1F,  # normal bold italic flash large magic
    'C': 0x18, 'J': 0x19, 'U': 0x1A, 'D': 0x1B, 'W': 0x0F,             # crawl jump wipe-up wipe-down wipe-back
    'P': 0x06, 'S': 0x07, 'T': 0x5F, 'A': 0xBC, 'X': 0xBA, 'H': 0xB9,  # pause beep time rainbow wait thin(H)
    'R': 0x8C, 'O': 0x8D, 'Y': 0x8F, 'G': 0x83, 'K': 0x80,             # fore: red orange yellow green black
    'r': 0x91, 'g': 0x92, 'y': 0x93, 'k': 0x90,                        # back: red green yellow black
    '0': 0xF0, '1': 0xF1, '2': 0xF2, '3': 0xF3, '4': 0xF4, '5': 0xF5, '6': 0xF6, '7': 0xF7,  # speed
    '@': ord('@'),
}
NAMED = {n: 0x80 + i for i, n in enumerate(FORE)}
NAMED.update({'bg ' + n: v for n, v in BACK.items()})
NAMED.update({'speed %d' % i: 0xF0 + i for i in range(8)})
NAMED.update({'normal': 0x11, 'bold': 0x12, 'italic': 0x13, 'flash': 0x14, 'large': 0x10,
              'thin': 0xB9, 'magic': 0x1F, 'crawl': 0x18, 'jump': 0x19, 'wipe up': 0x1A,
              'wipe down': 0x1B, 'wipe back': 0x0F, 'pause': 0x06, 'beep': 0x07, 'time': 0x5F,
              'rainbow': 0xBC, 'wait': 0xBA, 'remark': 0xB0, 'graphic': 0xB8,
              'tiny': 0xBE, 'restart': 0xBD, 'fx-bb': 0xBB})

def encode_text(s: str) -> bytes:
    out = bytearray(); i = 0
    while i < len(s):
        c = s[i]
        if c == '@' and i + 1 < len(s) and s[i + 1] == '{' and '}' in s[i:]:
            j = s.index('}', i)
            name = s[i + 2:j].strip().lower()
            if name in NAMED:
                out.append(NAMED[name])
            elif len(name) == 2 and all(ch in '0123456789abcdef' for ch in name):
                out.append(int(name, 16))                    # raw byte, e.g. @{9f}
            else:
                sys.exit("unknown escape @{%s}. Colours: %s; backgrounds: %s"
                         % (name, ', '.join(FORE), ', '.join('bg ' + b for b in BACK)))
            i = j + 1
        elif c == '@' and i + 1 < len(s) and s[i + 1] in ESC:
            out.append(ESC[s[i + 1]]); i += 2
        else:
            out.append(ord(c) & 0xFF); i += 1
    return bytes(out)

# ---- framing --------------------------------------------------------------
def frame(addr: int, payload: bytes, flag: int = 0x80) -> bytes:
    """flag 0x80 = firmware processes the packet inside the interrupt (NETCC default).
    Any other value defers processing to the main loop, which only looks at the end
    of the current display cycle - and while a deferred packet is pending, the
    next frame's address byte 01 drops the sign into the editor (firmware notes
    B9). Stock firmware needed deferred mode for B4 queries (stack overflow, B1);
    the patched firmware does not."""
    if not 0 <= len(payload) <= 254:
        raise ValueError("payload must be 0..254 bytes")
    return bytes([START, addr, flag, len(payload)]) + payload + bytes([sum(payload) & 0xFF])

def chan(n: int) -> bytes:
    return b'%02d' % n            # two ASCII digits, 00-99

def hexs(b: bytes) -> str:
    return ' '.join('%02X' % x for x in b)

def printable(b: bytes) -> str:
    return ''.join(chr(x) if 32 <= x < 127 else '<%02X>' % x for x in b)

# ---- transports ---------------------------------------------------------------
# A link needs three methods: write(bytes), read(n, timeout) -> bytes (possibly
# short/empty on timeout), reset_input(). cc784_esphome.py supplies one that
# talks through an ESPHome serial_proxy instead of a local port.
class SerialLink:
    def __init__(self, port):
        self.ser = serial.Serial(port, baudrate=300, bytesize=8, parity='N',
                                 stopbits=2, timeout=0.2, rtscts=False, dsrdtr=False)
    def write(self, data: bytes):
        self.ser.write(data); self.ser.flush()
    def read(self, n: int, timeout: float) -> bytes:
        self.ser.timeout = timeout
        return self.ser.read(n)
    def reset_input(self):
        self.ser.reset_input_buffer()
    def close(self):
        self.ser.close()

class Sign:
    def __init__(self, link, addr, gap=0.0, timeout=3.0, verbose=False):
        self.link = link
        self.addr, self.gap, self.timeout, self.verbose = addr, gap, timeout, verbose
        self.post_ack = 1.0          # pause after each frame: the sign is deaf while it processes
        self.quiet = False           # suppress the per-frame ACK line (bulk senders)
        self.done = False            # patched firmware: flag 81, wait for the DONE byte instead of sleeping

    def send_frame(self, payload: bytes, expect_ack=None, retries=3, flag=None, reply_follows=False):
        """flag defaults to 81 in done mode (ACK, processing, then a 04 DONE byte)
        and 80 otherwise. With reply_follows the caller reads the reply itself and
        then calls wait_done()."""
        if flag is None:
            flag = 0x81 if self.done else 0x80
        f = frame(self.addr, payload, flag)
        if expect_ack is None:
            expect_ack = self.addr != 0x2A
        for attempt in range(1, retries + 1):
            self.link.reset_input()
            if self.verbose: print("  TX:", hexs(f))
            if self.gap > 0:
                for b in f:
                    self.link.write(bytes([b])); time.sleep(self.gap)
            else:
                self.link.write(f)
            if not expect_ack:
                if not reply_follows:
                    time.sleep(len(f) * 10 / 300.0 + self.post_ack)   # no ACK to wait for: wire time, then the deaf window
                return True
            # the ACK follows the last byte, and 300 baud moves ~27 bytes/s: a long
            # frame is still on the wire when a fixed timeout would expire, and a
            # retry mid-frame is what desyncs the parser
            r = self.read_bytes(1, self.timeout + len(f) * 10 / 300.0)
            if r == bytes([ACK]):
                if not self.quiet: print("  ACK")
                # the ACK goes out BEFORE the packet is processed, and processing
                # runs with interrupts off: ~0.25 s on an empty store, ~0.75 s
                # when it is nearly full (init_sequence rescans the store for
                # every channel in the sequence). Anything sent meanwhile is lost
                # without a NAK. The patched firmware sends DONE (04) the moment
                # it can hear again if the flag was 81; stock needs the pause.
                if reply_follows:
                    return True
                if flag & 1:
                    self.wait_done()
                else:
                    time.sleep(self.post_ack)
                return True
            if r == bytes([NAK]):
                print("  NAK (checksum rejected) - retrying"); continue
            print("  no reply (attempt %d/%d)%s" % (attempt, retries,
                  "" if r == b"" else " got " + hexs(r)))
        return False

    def wait_done(self, timeout=5.0):
        """wait for the DONE byte that follows processing of a flag-81 frame; fall
        back to the fixed pause if it does not come"""
        end = time.time() + timeout
        while time.time() < end:
            b = self.link.read(1, 0.2)
            if b == bytes([DONE]):
                return True
        print("  no DONE within %.0f s; pausing instead" % timeout)
        time.sleep(self.post_ack)
        return False

    def read_bytes(self, n, timeout):
        end = time.time() + timeout; buf = bytearray()
        while len(buf) < n and time.time() < end:
            buf += self.link.read(n - len(buf), min(0.2, max(0.0, end - time.time())))
        if self.verbose and buf: print("  RX:", hexs(buf))
        return bytes(buf)

    def read_reply(self, timeout=None, dump=False):
        """Read a reply frame B1 addr ... . Returns (raw_bytes) or b''.
        The frame's own header says how long it is: a length byte, or for the
        store dump (dump=True) five ASCII digits. Reads until that many bytes
        have arrived (a 15 K dump takes ten minutes at 300 baud) or the line
        goes quiet."""
        timeout = timeout or self.timeout
        t0 = time.time(); end = t0 + timeout; buf = bytearray(); expected = None
        while time.time() < end:
            b = self.link.read(1, 0.2)
            if not b:
                continue
            buf += b
            end = max(end, time.time() + 2.0)        # keep going while bytes flow
            if expected is None:
                f = buf[1:] if buf[:1] == bytes([ACK]) else buf   # the ACK comes first when addressed
                if f[:1] == bytes([START]):
                    if dump and len(f) >= 7 and f[2:7].isdigit():
                        expected = len(buf) - len(f) + 7 + int(f[2:7]) + 1
                    elif not dump and len(f) >= 3:
                        expected = len(buf) - len(f) + 4 + f[2]
                if expected:
                    end = max(end, time.time() + (expected - len(buf)) * 10 / 300.0 + 2.0)
            if expected and len(buf) >= expected:
                break
        if self.verbose and buf: print("  RX:", hexs(buf))
        return bytes(buf)

    def query(self, n: str):
        # queries always reply, even to broadcast; ACK (if addressed) comes first.
        # Immediate mode (0x80): the patched firmware's relocated stack makes it
        # safe, and the reply follows the ACK at once. Deferred mode (0x00) was
        # the stock workaround, but its reply only comes at the end of the
        # current display cycle, and while it is pending the next frame's
        # address byte 01 drops the sign into the editor (firmware notes B9).
        self.send_frame(b'\xB4' + n.encode(), expect_ack=False, reply_follows=True)
        raw = self.read_reply(dump=(n == '3'))
        if self.done:
            self.wait_done()
        return raw

# ---- commands ---------------------------------------------------------------
def parse_reply(raw: bytes, kind: str):
    if not raw:
        print("  (no reply)"); return
    if raw[:1] == bytes([ACK]): print("  ACK"); raw = raw[1:]
    if raw[:1] != bytes([START]):
        print("  unexpected:", hexs(raw)); return
    if kind == 'dump':
        cnt = raw[2:7]; data = raw[7:-1]; ck = raw[-1]
        print("  from addr %d, sign says %s bytes, got %d, checksum %s" %
              (raw[1], cnt.decode(errors='replace'), len(data),
               "OK" if sum(data) & 0xFF == ck else "BAD"))
        # walk the store: a channel marker is TWO bytes, D0+tens then D0+units
        # (channel 42 -> D4 D2); 03 ends a channel's text, DA ends the store.
        i = 0; shown = 0
        while i < len(data):
            b = data[i]
            if b == 0xDA:
                break
            if 0xD0 <= b <= 0xD9 and i + 1 < len(data) and 0xD0 <= data[i + 1] <= 0xD9:
                chn = (b - 0xD0) * 10 + (data[i + 1] - 0xD0); i += 2
                text = bytearray()
                while i < len(data) and data[i] != 0x03:
                    text.append(data[i]); i += 1
                i += 1                                  # skip the 03
                if text:
                    print("   ch %2d: %s" % (chn, printable(text))); shown += 1
            else:
                i += 1
        print("   (%d channel%s with text)" % (shown, '' if shown == 1 else 's'))
    else:
        ln = raw[2]; data = raw[3:3 + ln]; ck = raw[3 + ln] if len(raw) > 3 + ln else None
        ok = ck is not None and sum(data) & 0xFF == ck
        print("  from addr %d, len %d, checksum %s: %s" %
              (raw[1], ln, "OK" if ok else "BAD/short", printable(data)))
        if kind == 'mem' and len(data) == 10:
            print("  total %s bytes, free %s bytes" % (data[:5].decode(), data[5:].decode()))

def add_common_args(ap):
    ap.add_argument('-a', '--addr', default='*', help="sign address 0-255 or '*' (broadcast; a broadcast frame gets no ACK and no DONE)")
    ap.add_argument('-g', '--gap', type=float, default=0.0, help='gap between bytes (s)')
    ap.add_argument('-t', '--timeout', type=float, default=3.0, help='reply timeout (s)')
    ap.add_argument('-v', '--verbose', action='store_true')
    ap.add_argument('--done', action='store_true',
                    help='patched firmware (patch 16+): wait for its DONE byte after each frame instead of pausing')
    ap.add_argument('--unsafe', action='store_true',
                    help='allow the B4 queries (id/mem/dump). On CC784NIR firmware these overflow '
                         'the 64-byte stack and corrupt RAM (sequence table, TX engine); use only '
                         'with patched firmware')
    ap.add_argument('cmd', nargs='?', default='sniff')
    ap.add_argument('args', nargs='*')

def run(link, a, ap):
    """Execute command a.cmd with a.args over the given link. Shared by both front-ends."""
    addr = 0x2A if a.addr == '*' else int(a.addr, 0)
    s = Sign(link, addr, a.gap, a.timeout, a.verbose)
    s.done = a.done
    c, args = a.cmd, a.args

    if c == 'sniff':
        print("listening (300 8N2)... ctrl-C to stop")
        try:
            while True:
                b = link.read(64, 0.5)
                if b: print(hexs(b), " ", printable(b))
        except KeyboardInterrupt: pass

    elif c in ('id', 'mem', 'dump'):
        if not a.unsafe:
            sys.exit("'%s' sends a B4 query, which crashes/corrupts the stock CC784NIR firmware "
                     "(stack overflow). Add --unsafe if you really want to." % c)
        parse_reply(s.query({'id': '0', 'mem': '1', 'dump': '3'}[c]), c)

    elif c == 'msg':
        ch = int(args[0]); text = encode_text(' '.join(args[1:]))
        body = b'\x09' + chan(ch) + b'\x0E' + text
        if len(body) + 3 <= 254:
            s.send_frame(body + b'\x04' + chan(ch))         # load and display
        else:                                               # long: split like NETCC does
            head, rest = body[:4], body[4:]
            first = True
            while rest:
                part, rest = rest[:250], rest[250:]
                typ = b'\x0E' if first else b'\xB3'
                s.send_frame(b'\x09' + chan(ch) + typ + part); first = False
            s.send_frame(b'\x04' + chan(ch))

    elif c == 'clear':
        s.send_frame(b''.join(b'\x09' + chan(int(x)) + b'\x0E' for x in args))
    elif c == 'clearall':
        s.send_frame(b'\x03')
    elif c == 'seq':
        s.send_frame(b'\x04' + b''.join(chan(int(x)) for x in args))
    elif c == 'time':
        # the protocol carries no seconds, and the sign starts the new minute at
        # :00 (patch 23), so the frame is timed to be processed on the minute:
        # 7 bytes on the wire take 0.23 s
        now = datetime.datetime.now()
        target = (now + datetime.timedelta(minutes=1)).replace(second=0, microsecond=0)
        wait = (target - now).total_seconds() - 0.3
        if wait > 0:
            print("  waiting %.0f s for the top of the minute" % wait); time.sleep(wait)
        h = target.hour % 12 or 12
        s.send_frame(b'\x17' + b'%02d%02d' % (h, target.minute) + (b'Y' if target.hour < 12 else b'N'))
        print("  set to %02d:%02d %s" % (h, target.minute, 'AM' if target.hour < 12 else 'PM'))
    elif c == 'raw':
        s.send_frame(bytes(int(x, 16) for x in args))
        r = s.read_reply(1.5)
        if r: print("  reply:", hexs(r), " ", printable(r))

    elif c in ('stop', 'start'):
        # Bare bytes, not framed packets - these go through rx_consume's
        # keystroke path, not the B1 parser, so there is no address, no
        # checksum and no ACK. 0x01 is caught at 0x02F1 (CP 1 -> key_handler)
        # and drops the sign into the editor; 0x0D is the STOP/START key's
        # own character (CP 13 -> editor_exit in the editor dispatch) and resumes
        # the display. 0x0D only does anything if the sign is already stopped.
        #
        # While stopped, rx_consume returns immediately on MENU_ACTIVE, so the
        # packet parser is bypassed entirely - ordinary commands are swallowed
        # as keystrokes and echoed back instead of being executed. Send 'start'
        # before anything else.
        #
        # Beware the reverse, too: a bare 0x01 arriving while the parser is
        # idle always means "stop". Any frame to address 1 contains a 0x01, so
        # a desynced or interleaved frame (retries at 300 baud will do it) can
        # drop the sign into the editor on its own. Seen in practice.
        b = 1 if c == 'stop' else 13
        link.reset_input()
        link.write(bytes([b]))
        print("  sent %02X - %s" % (b, "stopped; sign is now in the editor and "
                                       "takes typed characters directly"
                                       if c == 'stop' else "running"))
        r = s.read_reply(1.5)      # the editor echoes keys when KEY_ECHO_TX is set
        if r: print("  reply:", hexs(r), " ", printable(r))
    else:
        ap.error("unknown command " + c)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-p', '--port', default='/dev/tty.usbserial-110')
    add_common_args(ap)
    a = ap.parse_args()
    if serial is None:
        sys.exit("pyserial is required:  pip install pyserial")
    link = SerialLink(a.port)
    try:
        run(link, a, ap)
    finally:
        link.close()

if __name__ == '__main__':
    main()
