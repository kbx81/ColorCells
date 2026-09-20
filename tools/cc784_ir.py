#!/usr/bin/env python3
"""
cc784_ir.py - Color Cells CC784NIR infrared remote protocol: key map and frame encoder.

Derived from the firmware decoder (ir_st_* at ROM 0x1482) and a logic-analyzer capture
of the sign's own IR receiver output; encoder verified by simulating the firmware
decoder over every code and sampling phase.

    cc784_ir.py map                       # print the 62-key table
    cc784_ir.py raw Y STOP                # remote_transmitter raw code lists (ESPHome)
    cc784_ir.py raw 7 36                  # ...by key index
    cc784_ir.py yaml Y                    # a ready-to-paste ESPHome button action

FRAME (times as TRANSMITTED, i.e. carrier on/off; the sign's receiver stretches every
burst by ~250 us and the firmware timing is built around that):

    burst 600us                        leader
    gap   until t = 3140us             (measured from leader start)
    burst 512 / gap 512                start cell
    6 x data cell (1024us):            bit 1 = burst 512 then gap 512
                                       bit 0 = gap 512 then burst 512
    code = 0x80 | key_index (0..61); 0xBE = key released

    Holding a key repeats the frame every ~90 ms. The firmware registers a key on
    its SECOND frame (debounce), auto-repeats after ~1 s at ~4/s (STOP/START never
    repeats), and clears on the release frame. So one keystroke = key frame,
    90 ms, key frame, 90 ms, release frame.
    Carrier: the sign's module is a 38/40 kHz type; part number not yet read.
"""
import sys

HALF = 512
LEADER = 600
START_AT = 3140
REPEAT_MS = 90
RELEASE = 0x3E

# Key index -> (unshifted, shifted) as the firmware's charsets resolve them
# (IR_KEY_TABLE -> glyph index -> CHARSET_UPPER / CHARSET_UPPER2). Control values are
# the editor/message control bytes; labels in <> are the remote's key legends
# (confirmed by the owner) or the sign's own attribute names.
KEYS = {
     0: ('T', 'T'),          1: ('C', 'C'),          2: ('Z', 'Z'),          3: ('%', "'"),
     4: ('W', 'W'),          5: ('<DEL 7F>', '<DEL 7F>'), 6: (')', '&'),      7: ('Y', 'Y'),
     8: ('P', 'P'),          9: ('R', 'R'),         10: ('7', '7'),         11: ('4', '4'),
    12: ('3', '3'),         13: ('<RIGHT 0A>', '<RIGHT-8 0C>'),   14: ('1', '1'),         15: ('U', 'U'),
    16: ('S', 'S'),         17: ('H', 'H'),         18: ('+', '-'),         19: ('*', '#'),
    20: ('9', '9'),         21: ('<UPPER/LOWER 1C>', '<EUROPE B6>'),   22: ('(', '$'),         23: ('X', 'X'),
    24: ('Q', 'Q'),         25: ('M', 'M'),         26: ('8', '8'),         27: ('5', '5'),
    28: ('6', '6'),         29: ('<SHIFT>', '<SHIFT>'), 30: ('2', '2'),      31: ('V', 'V'),
    32: ('J', 'J'),         33: ('O', 'O'),         34: ('<COLOR 15>', '<BGRND 16>'),   35: ('<BEEP 07>', '<WIPE-BACK 0F>'),
    36: ('<STOP/START 0D>', '<FUNC B7>'), 37: ('<SPACE>', '<SPACE>'), 38: ('B', 'B'),  39: ('E', 'E'),
    40: ('F', 'F'),         41: ('K', 'K'),         42: ('<GRAPH 1E>', '<TIME 5F>'),      43: ('<NORMAL 11>', '<ADJ-TIME 17>'),
    44: ('<CLEAR 0E>', '<CLEAR-ALL 03>'), 45: ('<LEFT 08>', '<LEFT-8 0B>'), 46: ('<BOLD 12>', '<CRAWL 18>'), 47: ('A', 'A'),
    48: ('I', 'I'),         49: ('N', 'N'),         50: ('<JUMP 19>', '<JUMP 19>'), 51: ('<WIPE-UP 1A>', '<WIPE-DOWN 1B>'),
    52: ('<PROG 09>', '<SPEED 02>'),   53: ('.', ':'),         54: ('<MAGIC 1F>', '<RESTART BD>'), 55: ('D', 'D'),
    56: ('G', 'G'),         57: ('L', 'L'),         58: ('<FLASH 14>', '<FLASH 14>'), 59: ('<LARGE 10>', '<ITALIC 13>'),
    60: ('<SEQ 04>', '<HOLD BB>'),   61: ('0', '0'),
}
# Special handling in the firmware:
#   36 (STOP/START): in display mode stops the display and enters the editor/menu; never auto-repeats
#   44 (CLEAR): shifted = CLEAR ALL (prompts CLR ALL Y/N)
#   37 (SPACE): code 0xA5 is also recognised directly by rx_consume
#   29 (SHIFT): toggles the shifted charset; not passed through the table
#   47 ('A')  : code 0xAF is also treated like STOP/START when leaving the editor (editor_exit)

def key_index(name):
    """key by index ("36"), by label ("Y", "STOP", "CLEAR", "SHIFT"), or by control byte ("0e")"""
    n = name.strip().upper()
    if n.isdigit() and len(n) == 2 and int(n) < 62:
        return int(n)
    for i, (u, s) in KEYS.items():
        for lab in (u, s):
            core = lab.strip('<>')
            if n in (lab, core) or n == core.split()[0] or n == core.split('/')[0]:
                return i
            if len(core.split()) == 2 and n == core.split()[1]:      # hex control byte
                return i
    raise SystemExit('unknown key %r (use "map")' % name)

def data_bits(code):
    """the 6 cell values the firmware must sample to reconstruct `code`"""
    idx = code & 0x3F
    for bits in range(64):
        shift = 0
        for k in range(6):
            v = (bits >> k) & 1
            shift = ((shift >> 1) | ((shift & 1) << 7)) & 0xFF
            shift |= v << 1
        if (((shift >> 4) | (shift << 4)) & 0xFF) & 0x3F == idx:
            return [(bits >> k) & 1 for k in range(6)]
    raise ValueError

def frame(code):
    """list of (burst_us, gap_us) -> flattened ESPHome raw list [+on, -off, ...]"""
    segs = [(0, LEADER)]
    t = START_AT
    segs.append((t, t + HALF)); t += 2 * HALF
    for v in data_bits(code):
        segs.append((t, t + HALF) if v else (t + HALF, t + 2 * HALF)); t += 2 * HALF
    segs.sort()
    merged = []
    for a, b in segs:
        if merged and a <= merged[-1][1]: merged[-1][1] = max(merged[-1][1], b)
        else: merged.append([a, b])
    raw = []
    for i, (a, b) in enumerate(merged):
        if i: raw.append(-(a - merged[i - 1][1]))
        raw.append(b - a)
    return raw

def keystroke(idx):
    """three frames: key, key (debounce), release — with 90 ms spacing expressed as trailing gaps"""
    k = frame(0x80 | idx); r = frame(0x80 | RELEASE)
    def pad(f):
        total = sum(abs(x) for x in f)
        return f + [-(REPEAT_MS * 1000 - total)]
    return pad(k) + pad(k) + r

def main():
    if len(sys.argv) < 2 or sys.argv[1] == 'map':
        print('idx  code  unshifted        shifted')
        for i, (u, s) in KEYS.items():
            print('%2d   0x%02X  %-16s %s' % (i, 0x80 | i, u, s))
        print('62   0xBE  <RELEASE>')
        return
    cmd, names = sys.argv[1], sys.argv[2:]
    if cmd == 'raw':
        for n in names:
            i = key_index(n)
            print('# key %d %s' % (i, KEYS[i][0]))
            print('code: [%s]' % ', '.join(('+%d' if x > 0 else '%d') % x for x in keystroke(i)))
    elif cmd == 'yaml':
        for n in names:
            i = key_index(n)
            print('- remote_transmitter.transmit_raw:\n    carrier_frequency: 38kHz   # try 40kHz if unresponsive\n    code: [%s]'
                  % ', '.join(('+%d' if x > 0 else '%d') % x for x in keystroke(i)))
    else:
        raise SystemExit('commands: map | raw KEY... | yaml KEY...')

if __name__ == '__main__':
    main()
