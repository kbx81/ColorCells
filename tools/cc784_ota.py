#!/usr/bin/env python3
"""
cc784_ota.py - build and deliver OTA firmware images for the CC784 (CC784_ota.md).

    cc784_ota.py pack BUILD.bin [-s SEQ] [-o BANK.bin] [--t48 CHIP.bin]
        Fill in the trailer page of one 16 K bank image (sequence number, state
        GOOD, image CRC, trailer CRC). --t48 also writes the 32 K chip image for
        minipro: the same app in both banks, bank 0 at SEQ and bank 1 at SEQ-1.

    cc784_ota.py diff OLD.bin NEW.bin
        The 64-byte pages that differ, and the transfer time at 300 baud.

    cc784_ota.py info (-p PORT | -H HOST -k KEY) [-a ADDR]
        Which bank the sign is running and what both trailers say.

    cc784_ota.py push BANK.bin (-p PORT | -H HOST -k KEY) [-a ADDR] [-s SEQ] [-n]
        Update the sign: read both trailers, CRC every page of the idle bank,
        send only the pages that differ, write the trailer, reboot, confirm.
        -n stops after the page comparison. The stub pages must already match.

Trailer at 3FC0: +0 "OTA1", +4 seq, +5 state, +6 CRC-16 of 0200..3FBF, +8 CRC-16
of bytes +0..+7, little-endian words. CRC-16/XMODEM: poly 1021, init 0.
"""
import argparse, os, pathlib, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

BANK = 0x4000
PAGE = 64
STUB_END = 0x0200          # STUB_END in cc784nir.asm; pages below it are never sent
TRAILER = 0x3FC0
MAGIC = b'OTA1'
STATE_TRIAL, STATE_TRIED, STATE_GOOD = 1, 2, 3


def crc16(data, crc=0):
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def trailer(seq, state, image_crc):
    t = MAGIC + bytes([seq & 0xFF, state]) + image_crc.to_bytes(2, 'little')
    return t + crc16(t).to_bytes(2, 'little') + b'\xff' * (PAGE - 10)


def pack(bank, seq, state=STATE_GOOD):
    """bank: 16 K image with an erased trailer -> the same with the trailer filled"""
    bank = bytes(bank[:BANK]).ljust(BANK, b'\xff')
    return bank[:TRAILER] + trailer(seq, state, crc16(bank[STUB_END:TRAILER]))


def parse_trailer_bytes(t):
    """the first 10 trailer bytes -> dict, or None if magic or trailer CRC is wrong"""
    if t[:4] != MAGIC or crc16(t[:8]) != int.from_bytes(t[8:10], 'little'):
        return None
    return {'seq': t[4], 'state': t[5], 'crc': int.from_bytes(t[6:8], 'little')}


def parse_trailer(bank):
    t = parse_trailer_bytes(bank[TRAILER:TRAILER + 10])
    if t:
        t['crc_ok'] = crc16(bank[STUB_END:TRAILER]) == t['crc']
    return t


def parse_info(reply):
    """B5 'I' reply -> (running bank, trailer dict or None for bank 0, same for bank 1)"""
    return reply[0], parse_trailer_bytes(reply[1:11]), parse_trailer_bytes(reply[11:21])


def changed_pages(old, new):
    return [p for p in range(BANK // PAGE)
            if old[p * PAGE:(p + 1) * PAGE] != new[p * PAGE:(p + 1) * PAGE]]


# ---- talking to the sign ------------------------------------------------------
class Ota:
    """the B5 command set over a cc784.Sign (any link); replies come back parsed"""
    def __init__(self, sign):
        self.sign = sign

    def cmd(self, payload, reply=True):
        if not self.sign.send_frame(payload):
            raise RuntimeError('no ACK for %s' % payload[:2])
        if not reply:
            return None
        raw = self.sign.read_reply()
        if len(raw) < 4 or raw[0] != 0xB1:
            raise RuntimeError('no reply frame, got %s' % raw.hex())
        n = raw[2]
        data = raw[3:3 + n]
        if len(data) != n or sum(data) & 0xFF != raw[3 + n]:
            raise RuntimeError('bad reply frame %s' % raw.hex())
        return data

    def info(self):
        return parse_info(self.cmd(b'\xb5I'))

    def page_crcs(self):
        out = []
        for first in range(0, BANK // PAGE, 42):
            n = min(42, BANK // PAGE - first)
            r = self.cmd(b'\xb5C' + bytes([first, n]))
            out += [int.from_bytes(r[i:i + 2], 'little') for i in range(0, 2 * n, 2)]
            print('  crc %3d/256' % len(out), end='\r', flush=True)
        print()
        return out

    def status(self, payload, what):
        r = self.cmd(payload)
        if r != b'\x00':
            raise RuntimeError('%s failed: status %d' % (what, r[0] if r else -1))


def describe(running, t0, t1):
    for b, t in ((0, t0), (1, t1)):
        tag = 'running' if b == running else 'idle   '
        print('bank %d (%s): %s' % (b, tag, 'seq %d, state %d, image crc %04X' % (t['seq'], t['state'], t['crc']) if t else 'no valid trailer'))


def push(sign, bank, seq=None, dry_run=False):
    sign.quiet = True
    ota = Ota(sign)
    running, t0, t1 = ota.info()
    idle = running ^ 1
    describe(running, t0, t1)
    if seq is None:
        seq = (max(t['seq'] for t in (t0, t1) if t) + 1) & 0xFF if (t0 or t1) else 1
    print('new sequence number %d; reading the idle bank\'s page CRCs' % seq)
    have = ota.page_crcs()
    want = [crc16(bank[p * PAGE:(p + 1) * PAGE]) for p in range(BANK // PAGE)]
    pages = [p for p in range(BANK // PAGE - 1) if have[p] != want[p]]      # the trailer is written by F
    stub = [p for p in pages if p < STUB_END // PAGE]
    if stub:
        raise RuntimeError('stub pages %s differ from the image: this image needs the T48' % stub)
    print('%d pages to send, ~%d s' % (len(pages), len(pages) * 3))
    if dry_run:
        return
    ota.status(b'\xb5B', 'begin')          # from here the panel shows UPDATING
    try:
        _send_pages(ota, bank, pages, seq)
    except Exception:
        print('update failed; rebooting the sign into its current bank')
        try:
            ota.cmd(b'\xb5R', reply=False)   # the idle trailer is erased: the old bank boots
        except Exception:
            pass
        raise
    time.sleep(8)                            # stub CRC pass, app init, first restart
    running, t0, t1 = ota.info()
    t = t1 if running == 1 else t0
    ok = running == idle and t and t['seq'] == seq
    print('OK' if ok else 'NOT RUNNING THE NEW IMAGE')
    describe(running, t0, t1)
    return ok


def _send_pages(ota, bank, pages, seq):
    done = 0
    while pages:
        run = [pages[0]]
        while pages[len(run):len(run) + 1] == [run[-1] + 1] and len(run) < 3:
            run.append(run[-1] + 1)
        pages = pages[len(run):]
        data = bank[run[0] * PAGE:(run[-1] + 1) * PAGE]
        ota.status(b'\xb5W' + bytes([run[0]]) + crc16(data).to_bytes(2, 'little') + data, 'write pages %s' % run)
        done += len(run)
        print('  written %d, %d to go' % (done, len(pages)))
    image_crc = crc16(bank[STUB_END:TRAILER])
    ota.status(b'\xb5F' + bytes([seq]) + image_crc.to_bytes(2, 'little'), 'finish')
    print('image verified on the sign, trailer written (seq %d); rebooting' % seq)
    ota.cmd(b'\xb5R', reply=False)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('pack')
    p.add_argument('build'); p.add_argument('-s', '--seq', type=int, default=1)
    p.add_argument('-o', '--out'); p.add_argument('--t48')
    d = sub.add_parser('diff')
    d.add_argument('old'); d.add_argument('new')
    u = sub.add_parser('push')
    u.add_argument('bank'); u.add_argument('-s', '--seq', type=int)
    u.add_argument('-n', '--dry-run', action='store_true')
    i = sub.add_parser('info')
    for x in (u, i):
        x.add_argument('-p', '--port'); x.add_argument('-H', '--host')
        x.add_argument('-k', '--key', default=os.environ.get('ESPHOME_KEY'))
        x.add_argument('-a', '--addr', type=int, default=1); x.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args()

    if a.cmd in ('push', 'info'):
        import cc784
        if a.cmd == 'push':
            bank = pathlib.Path(a.bank).read_bytes()[:BANK]
            if not parse_trailer(bank):
                sys.exit('%s has no valid trailer: run pack first' % a.bank)
        if a.host:
            import cc784_esphome
            link = cc784_esphome.ESPHomeLink(a.host, a.key, verbose=a.verbose)
        elif a.port:
            link = cc784.SerialLink(a.port)
        else:
            ap.error('%s needs -p PORT or -H HOST' % a.cmd)
        try:
            sign = cc784.Sign(link, a.addr, verbose=a.verbose)
            if a.cmd == 'info':
                sign.quiet = True
                describe(*Ota(sign).info())
                sys.exit(0)
            sys.exit(0 if push(sign, bank, a.seq, a.dry_run) else 1)
        finally:
            link.close()

    if a.cmd == 'pack':
        build = pathlib.Path(a.build).read_bytes()
        bank = pack(build, a.seq)
        out = pathlib.Path(a.out or pathlib.Path(a.build).with_suffix('.bank.bin'))
        out.write_bytes(bank)
        t = parse_trailer(bank)
        print('%s: seq %d, image crc %04X' % (out, t['seq'], t['crc']))
        if a.t48:
            pathlib.Path(a.t48).write_bytes(bank + pack(build, a.seq - 1))
            print('%s: bank 0 seq %d, bank 1 seq %d' % (a.t48, a.seq, (a.seq - 1) & 0xFF))
    else:
        old = pathlib.Path(a.old).read_bytes()[:BANK]
        new = pathlib.Path(a.new).read_bytes()[:BANK]
        pages = changed_pages(old, new)
        stub = [p for p in pages if p < STUB_END // PAGE]
        if stub:
            print('WARNING: stub pages differ: %s - these cannot be sent over the air' % stub)
        n = len(pages) - len(stub)
        secs = n * (PAGE + 8) * 10 / 300 + (n / 3) * 1.5
        print('%d of %d pages differ; ~%d s at 300 baud (3 pages per frame)' % (n, BANK // PAGE, secs))
        print(' '.join('%02X' % p for p in pages))


if __name__ == '__main__':
    main()
