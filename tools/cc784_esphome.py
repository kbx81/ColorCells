#!/usr/bin/env python3
"""
cc784_esphome.py - drive a Color Cells CC784 sign through an ESPHome serial_proxy.

    pip install aioesphomeapi          (cc784.py must be in the same directory)

    cc784_esphome.py -H sign-bridge.local -k 'AbCd...xyz=' msg 0 "@BHELLO"
    cc784_esphome.py -H 192.168.1.42 -k ... -a 0 time
    cc784_esphome.py -H sign-bridge.local -k ... --list      # show serial_proxy instances

Transport options (everything else is identical to cc784.py):
    -H HOST      ESPHome device: mDNS name (foo.local / foo), or IP
    -k KEY       Native API encryption key: the 44-char base64 string from your YAML
                 (api: encryption: key:). Also read from $ESPHOME_KEY.
    -P PORT      Native API port (default 6053)
    -i INSTANCE  serial_proxy instance: its configured name, or its index (default 0)
    --list       list the device's serial_proxy instances and exit

The proxy UART is reconfigured to the chosen rate (-b, default 300), 8 data bits,
no parity, 2 stop bits on connect (serial_proxy_configure), so the YAML baud_rate
does not matter.
Writes are fed to the proxy in 32-byte pieces at the line rate: handing it a
whole 259-byte frame at once lost bytes and dropped the API connection.
"""
import os, sys, asyncio, threading, queue, argparse, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cc784                                  # shared protocol + commands

try:
    from aioesphomeapi import APIClient, SerialProxyParity
except ImportError:
    sys.exit("aioesphomeapi is required:  pip install aioesphomeapi")


class ESPHomeLink:
    """Sync link (write/read/reset_input) over an async aioesphomeapi connection.

    The asyncio loop runs on a background thread; the command code in cc784.py
    stays synchronous and pulls received bytes from a thread-safe queue."""

    def __init__(self, host, key, port=6053, instance=None, verbose=False, list_only=False, chunk=32, baud=300):
        self.baud = baud
        self.host, self.key, self.port, self.verbose = host, key, port, verbose
        self.chunk = chunk
        self.instance_sel, self.list_only = instance, list_only
        self.instance = None
        self.rx = queue.Queue()
        self.loop = asyncio.new_event_loop()
        self.thread = threading.Thread(target=self.loop.run_forever, daemon=True)
        self.thread.start()
        self._run(self._connect())

    # -- asyncio side ---------------------------------------------------------
    def _run(self, coro, timeout=30):
        return asyncio.run_coroutine_threadsafe(coro, self.loop).result(timeout)

    async def _connect(self):
        self.cli = APIClient(self.host, self.port, password=None, noise_psk=self.key)
        await self.cli.connect(login=True)
        info = await self.cli.device_info()
        proxies = list(info.serial_proxies)
        if not proxies:
            raise SystemExit("%s (%s) has no serial_proxy instances" % (info.name, self.host))
        if self.list_only:
            print("serial_proxy instances on %s:" % info.name)
            for i, p in enumerate(proxies):
                print("  [%d] %s  (%s)" % (i, p.name, p.port_type.name if p.port_type else '?'))
            raise SystemExit(0)
        # pick instance by index or by name
        sel = self.instance_sel
        if sel is None:
            self.instance = 0
        elif isinstance(sel, int) or sel.isdigit():
            self.instance = int(sel)
        else:
            names = [p.name for p in proxies]
            if sel not in names:
                raise SystemExit("no serial_proxy named %r; have: %s" % (sel, ', '.join(names)))
            self.instance = names.index(sel)
        if not 0 <= self.instance < len(proxies):
            raise SystemExit("instance %d out of range (device has %d)" % (self.instance, len(proxies)))
        if self.verbose:
            print("  using %s serial_proxy[%d] '%s'" % (info.name, self.instance, proxies[self.instance].name))

        self._unsub = self.cli.subscribe_serial_proxy_data(self._on_data)
        r = await self.cli.serial_proxy_subscribe_await_response(self.instance)
        if r is not None and r.status is not None and r.status.name not in ('OK', 'ASSUMED_SUCCESS'):
            raise SystemExit("subscribe failed: %s %s" % (r.status.name, r.error_message))
        r = await self.cli.serial_proxy_configure_await_response(
            self.instance, self.baud, flow_control=False, parity=SerialProxyParity.NONE,
            stop_bits=2, data_size=8)
        if r is not None and r.status is not None and r.status.name not in ('OK', 'ASSUMED_SUCCESS'):
            raise SystemExit("configure failed: %s %s" % (r.status.name, r.error_message))

    def _on_data(self, msg):
        if msg.instance == self.instance and msg.data:
            for b in msg.data:
                self.rx.put(b)

    async def _write(self, data):
        self.cli.serial_proxy_write(self.instance, data)

    async def _close(self):
        try:
            self._unsub()
            await self.cli.serial_proxy_unsubscribe_await_response(self.instance, timeout=3)
        except Exception:
            pass
        await self.cli.disconnect()

    # -- sync link interface used by cc784.Sign --------------------------------
    def write(self, data: bytes):
        # The proxy's UART buffer is shallow: a 259-byte frame handed over at once
        # lost bytes and then dropped the API connection. Feed it in pieces paced
        # at the line rate (300 baud = 27 bytes/s) so it never holds more than one.
        data = bytes(data)
        if self.chunk <= 0:                      # whole frame in one write
            self._run(self._write(data))
            return
        for i in range(0, len(data), self.chunk):
            piece = data[i:i + self.chunk]
            self._run(self._write(piece))
            if i + self.chunk < len(data):
                time.sleep(len(piece) * 10.0 / self.baud)

    def read(self, n: int, timeout: float) -> bytes:
        out = bytearray(); end = time.time() + timeout
        while len(out) < n:
            remaining = end - time.time()
            if remaining <= 0:
                break
            try:
                out.append(self.rx.get(timeout=remaining))
            except queue.Empty:
                break
        return bytes(out)

    def reset_input(self):
        while True:
            try: self.rx.get_nowait()
            except queue.Empty: return

    def close(self):
        try:
            self._run(self._close(), timeout=10)
        finally:
            self.loop.call_soon_threadsafe(self.loop.stop)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-H', '--host', required=True, help='ESPHome device mDNS name or IP')
    ap.add_argument('-k', '--key', default=os.environ.get('ESPHOME_KEY'),
                    help='Native API encryption key (or set $ESPHOME_KEY)')
    ap.add_argument('-P', '--api-port', type=int, default=6053)
    ap.add_argument('-i', '--instance', default=None, help='serial_proxy name or index (default 0)')
    ap.add_argument('--list', action='store_true', help='list serial_proxy instances and exit')
    ap.add_argument('--chunk', type=int, default=32,
                    help='bytes per proxy write, paced at the line rate (default 32; 0 = one write)')
    cc784.add_common_args(ap)
    a = ap.parse_args()
    if not a.key:
        ap.error("an encryption key is required (-k or $ESPHOME_KEY)")
    link = ESPHomeLink(a.host, a.key, a.api_port, a.instance, a.verbose, a.list, a.chunk, baud=a.baud)
    try:
        cc784.run(link, a, ap)
    finally:
        link.close()


if __name__ == '__main__':
    main()
