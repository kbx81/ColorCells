#!/usr/bin/env python3
"""
cc784_ota.py - build and deliver OTA firmware images for the CC784 (ota.md).

    cc784_ota.py pack BUILD.bin [-s SEQ] [-o BANK.bin] [--t48 CHIP.bin]
        Fill in the trailer page of one 16 K bank image (sequence number, state
        GOOD, image CRC, trailer CRC). --t48 also writes the 32 K chip image for
        minipro: the same app in both banks, bank 0 at SEQ and bank 1 at SEQ-1.

    cc784_ota.py diff OLD.bin NEW.bin
        The 64-byte pages that differ, and the transfer time at 300 baud.

    cc784_ota.py info (-p PORT | -H HOST -k KEY [-i INSTANCE]) [-a ADDR]
        Which bank the sign is running and what both trailers say.

    cc784_ota.py push BANK.bin (-p PORT | -H HOST -k KEY) [-a ADDR] [-s SEQ] [-n] [--trial]
        Update the sign: read both trailers, CRC every page of the idle bank,
        send only the pages that differ, write the trailer, reboot, and confirm
        the new image once it answers. --trial leaves it unconfirmed (a power
        cycle reverts it) until `confirm`. -n stops after the page comparison.
        The stub pages must already match.

    cc784_ota.py confirm / rollback (-p PORT | -H HOST -k KEY)
        Mark the running image GOOD, or reboot into the other bank.

Trailer at 3FC0: +0 "OTA1", +4 seq, +5 state, +6 CRC-16 of 0240..3FBF, +8 CRC-16
of bytes +0..+7, little-endian words. CRC-16/XMODEM: poly 1021, init 0.
State: 1 TRIAL (written by F), 2 TRIED (the stub booted it once), 3 GOOD.
"""
import argparse, os, pathlib, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

BANK = 0x4000
PAGE = 64
STUB_END = 0x0240          # STUB_END in cc784nir.asm; pages below it are never sent
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


FEATURE_DONE, FEATURE_MAINS, FEATURE_TRIAL = 0x01, 0x02, 0x04
STATE_NAMES = {STATE_TRIAL: 'TRIAL', STATE_TRIED: 'TRIED', STATE_GOOD: 'GOOD'}


def parse_info(reply):
    """B5 'I' reply -> (running bank, trailer dict or None for bank 0, same for bank 1).
    Byte 21, when present, is the firmware's features byte (bit 0: DONE handshake)."""
    return reply[0], parse_trailer_bytes(reply[1:11]), parse_trailer_bytes(reply[11:21])


def features(reply):
    return reply[21] if len(reply) > 21 else 0


def changed_pages(old, new):
    return [p for p in range(BANK // PAGE)
            if old[p * PAGE:(p + 1) * PAGE] != new[p * PAGE:(p + 1) * PAGE]]


# ---- talking to the sign ------------------------------------------------------
class Ota:
    """the B5 command set over a cc784.Sign (any link); replies come back parsed"""
    def __init__(self, sign):
        self.sign = sign

    def cmd(self, payload, reply=True):
        if not reply:                                   # R: the sign resets, nothing follows
            if not self.sign.send_frame(payload, flag=0x80, reply_follows=True):
                raise RuntimeError('no ACK for %s' % payload[:2])
            return None
        if not self.sign.send_frame(payload, reply_follows=True):
            raise RuntimeError('no ACK for %s' % payload[:2])
        raw = self.sign.read_reply()
        if len(raw) < 4 or raw[0] != 0xB1:
            raise RuntimeError('no reply frame, got %s' % raw.hex())
        n = raw[2]
        data = raw[3:3 + n]
        if len(data) != n or sum(data) & 0xFF != raw[3 + n]:
            raise RuntimeError('bad reply frame %s' % raw.hex())
        if self.sign.done:
            self.sign.wait_done()
        else:
            time.sleep(self.sign.post_ack)
        return data

    def info(self):
        """also switches the link to the DONE handshake when the firmware offers it"""
        raw = self.cmd(b'\xb5I')
        self.features = features(raw)
        self.sign.done = bool(self.features & FEATURE_DONE)
        return parse_info(raw)

    def set_state(self, state, seq):
        """K: rewrite the running bank's trailer with this state and sequence number"""
        self.status(b'\xb5K' + bytes([state, seq & 0xFF]), 'set state')

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
        print('bank %d (%s): %s' % (b, tag, 'seq %d, %s, image crc %04X' % (t['seq'], STATE_NAMES.get(t['state'], t['state']), t['crc']) if t else 'no valid trailer'))


def confirm(ota):
    """mark the running bank GOOD (after a trial boot it is TRIED)"""
    running, t0, t1 = ota.info()
    t = t1 if running else t0
    if not t:
        raise RuntimeError('the running bank has no valid trailer')
    if t['state'] == STATE_GOOD:
        print('already GOOD'); return True
    ota.set_state(STATE_GOOD, t['seq'])
    running, t0, t1 = ota.info()
    t = t1 if running else t0
    ok = t and t['state'] == STATE_GOOD
    print('confirmed' if ok else 'CONFIRM FAILED'); describe(running, t0, t1)
    return ok


def rollback(ota):
    """boot the other bank next: give the running bank a lower sequence number, reboot"""
    running, t0, t1 = ota.info()
    mine, other = (t1, t0) if running else (t0, t1)
    if not other or other['state'] != STATE_GOOD:
        raise RuntimeError('the other bank is not a GOOD image to roll back to')
    ota.set_state(STATE_GOOD, other['seq'] - 1)
    ota.cmd(b'\xb5R', reply=False)
    time.sleep(8)
    running2, t0, t1 = ota.info()
    ok = running2 != running
    print('rolled back' if ok else 'STILL ON THE SAME BANK'); describe(running2, t0, t1)
    return ok


def push(sign, bank, seq=None, dry_run=False, trial=False, all_pages=False):
    sign.quiet = True
    ota = Ota(sign)
    running, t0, t1 = ota.info()
    idle = running ^ 1
    describe(running, t0, t1)
    if seq is None:
        seq = (max(t['seq'] for t in (t0, t1) if t) + 1) & 0xFF if (t0 or t1) else 1
    if all_pages:
        # no C command: a sign running a build older than patch 35's ota_copy crashes when a mains
        # NMI lands while C has the idle bank mapped in and the two images
        # differ at nmi_entry
        print('new sequence number %d; sending every page' % seq)
        pages = list(range(STUB_END // PAGE, BANK // PAGE - 1))
    else:
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
    ota.status(b'\xb5B', 'begin')          # from here the panel shows >FW ^<
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
    if not ok:
        print('NOT RUNNING THE NEW IMAGE'); describe(running, t0, t1); return False
    if ota.features & FEATURE_TRIAL and t['state'] != STATE_GOOD:
        if trial:
            print('running the new image as a TRIAL: confirm it with `confirm`, or power-cycle to revert')
        else:
            ota.set_state(STATE_GOOD, seq)
            running, t0, t1 = ota.info()
            t = t1 if running == 1 else t0
            ok = t and t['state'] == STATE_GOOD
    print('OK' if ok else 'CONFIRM FAILED')
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
    u.add_argument('--trial', action='store_true', help='leave the new image unconfirmed: a power cycle reverts it until `confirm`')
    u.add_argument('--all', action='store_true', help='send every page without reading the idle bank first (a build older than patch 35\'s ota_copy fix can crash on the C command)')
    i = sub.add_parser('info')
    c = sub.add_parser('confirm'); r = sub.add_parser('rollback')
    for x in (u, i, c, r):
        x.add_argument('-p', '--port'); x.add_argument('-H', '--host')
        x.add_argument('-k', '--key', default=os.environ.get('ESPHOME_KEY'))
        x.add_argument('-i', '--instance', default=None, help='serial_proxy instance on the ESPHome device: name or index (default 0)')
        x.add_argument('-b', '--baud', type=int, default=300, choices=(300, 600, 1200, 2560), help='line rate (patch 30 firmware follows the host, 2560 from patch 52; default 300)')
        x.add_argument('-a', '--addr', type=int, default=1); x.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args()

    if a.cmd in ('push', 'info', 'confirm', 'rollback'):
        import cc784
        if a.cmd == 'push':
            bank = pathlib.Path(a.bank).read_bytes()[:BANK]
            if not parse_trailer(bank):
                sys.exit('%s has no valid trailer: run pack first' % a.bank)
        if a.host:
            import cc784_esphome
            link = cc784_esphome.ESPHomeLink(a.host, a.key, instance=a.instance, verbose=a.verbose, baud=a.baud)
        elif a.port:
            link = cc784.SerialLink(a.port, a.baud)
        else:
            ap.error('%s needs -p PORT or -H HOST' % a.cmd)
        try:
            sign = cc784.Sign(link, a.addr, timeout=8.0, verbose=a.verbose, baud=a.baud)   # the sign restarts its display after every command: up to ~4 s deaf
            sign.quiet = True
            if a.cmd == 'info':
                describe(*Ota(sign).info()); sys.exit(0)
            if a.cmd == 'confirm':
                sys.exit(0 if confirm(Ota(sign)) else 1)
            if a.cmd == 'rollback':
                sys.exit(0 if rollback(Ota(sign)) else 1)
            sys.exit(0 if push(sign, bank, a.seq, a.dry_run, a.trial, a.all) else 1)
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
