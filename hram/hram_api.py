#!/usr/bin/env python3
"""
hram_api.py : serwer HTTP warstwy HRAM (osobny od aplikacji).

Aplikacja mobilna laczy sie z nim przez HTTP/JSON. Warstwa pamieci
zyje wlasnym zyciem - mozna ja uruchomic bez aplikacji.

Uruchomienie:
    python3 hram/hram_api.py --port 8787

Endpointy:
    GET  /hram/status   -> trzy liczby: VA, fizyczna, realnie zapisywalna
    GET  /hram/hyper?bytes=256 -> hiperprzelicznik (arytmetyka)
    POST /hram/bench    {"bytes": 67108864} -> realny pomiar
    POST /hram/write    {"offset":0,"bytes":1048576}
    GET  /hram/health
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ALEN_BITS = 50
VA_SIZE = 1 << ALEN_BITS          # 1 125 899 906 842 624 B
HERE = os.path.dirname(os.path.abspath(__file__))
HRAM_BIN = os.path.join(HERE, "hram")


def backend_dir():
    return "/data" if os.path.isdir("/data") else HERE


def real_capacity():
    try:
        v = shutil.disk_usage(backend_dir())
        return v.free
    except OSError:
        return 0


def backend_file_size():
    p = os.path.join(backend_dir(), "hram_backend.bin")
    try:
        return os.path.getsize(p)
    except OSError:
        return 0


def zram_ratio():
    try:
        with open("/sys/block/zram0/mm_stat") as f:
            parts = f.read().split()
        orig, comp = int(parts[0]), int(parts[1])
        if comp > 0:
            return round(orig / comp, 3)
    except (OSError, IndexError, ValueError):
        pass
    return None


def hyper_calc(nbytes):
    """1 bit = 10^15 GB = 10^24 B. Czysta arytmetyka."""
    bits = nbytes * 8
    gb = bits * 1e15
    total_bytes = gb * 1e9
    addr_bits = 0
    cap = 1
    while cap < total_bytes and addr_bits < 512:
        cap *= 2
        addr_bits += 1
    return {
        "assumption": "1 bit = 10^15 GB = 10^24 B",
        "is_arithmetic_only": True,
        "input_bytes": nbytes,
        "input_bits": bits,
        "GB": gb, "TB": gb / 1e3, "PB": gb / 1e6,
        "EB": gb / 1e9, "ZB": gb / 1e12, "YB": gb / 1e15,
        "total_bytes": total_bytes,
        "address_bits_needed": addr_bits,
        "verdict": "NIEWYKONALNE - takiej pojemnosci nie da sie "
                   "zaadresowac ani zapisac na zadnym sprzecie",
        "reference_limits": {
            "ARM64_48bit": "256 TB",
            "x86_64_57bit": "128 PB",
            "Kurroma_128_50bit": "1,126 PB",
        },
    }


def run_hram(args, timeout=120):
    try:
        r = subprocess.run([HRAM_BIN] + args, capture_output=True,
                           text=True, timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except FileNotFoundError:
        return 127, "", "brak binarki hram - zbuduj: cc -O2 -o hram/hram hram/hram.c"
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        sys.stderr.write("[hram_api] " + (fmt % a) + "\n")

    def _send(self, code, obj):
        body = json.dumps(obj, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)

        if u.path == "/hram/health":
            return self._send(200, {"ok": True, "service": "hram",
                                    "version": "1.0"})

        if u.path == "/hram/status":
            real = real_capacity()
            return self._send(200, {
                "reserved_va_bytes": VA_SIZE,
                "reserved_va_pb": round(VA_SIZE / 1e15, 6),
                "address_bits": ALEN_BITS,
                "physical_bytes": real,
                "physical_gb": round(real / 1e9, 3),
                "backend_file_bytes": backend_file_size(),
                "writable_bytes": real,
                "writable_gb": round(real / 1e9, 3),
                "zram_compression_ratio": zram_ratio(),
                "note": "reserved_va to rezerwacja adresowa, nie fizyczna pamiec",
                "backend_dir": backend_dir(),
            })

        if u.path == "/hram/hyper":
            n = int(q.get("bytes", ["256"])[0])
            return self._send(200, hyper_calc(n))

        return self._send(404, {"error": "nieznany endpoint", "path": u.path})

    def do_POST(self):
        u = urlparse(self.path)
        try:
            ln = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(ln) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self._send(400, {"error": "zly JSON"})

        if u.path == "/hram/bench":
            n = int(body.get("bytes", 64 * 1024 * 1024))
            rc, out, err = run_hram(["bench", str(n)])
            return self._send(200 if rc == 0 else 500,
                              {"ok": rc == 0, "stdout": out, "stderr": err,
                               "requested_bytes": n})

        if u.path == "/hram/write":
            off = int(body.get("offset", 0))
            n = int(body.get("bytes", 1024 * 1024))
            rc, out, err = run_hram(["write", str(off), str(n)])
            return self._send(200 if rc == 0 else 507,
                              {"ok": rc == 0, "stdout": out, "stderr": err,
                               "offset": off, "bytes": n})

        return self._send(404, {"error": "nieznany endpoint", "path": u.path})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--host", default="0.0.0.0")
    a = ap.parse_args()
    srv = ThreadingHTTPServer((a.host, a.port), Handler)
    print(f"HRAM API na http://{a.host}:{a.port}")
    print(f"  VA: {VA_SIZE} B (2^{ALEN_BITS})")
    print(f"  backend: {backend_dir()}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nzatrzymano")


if __name__ == "__main__":
    main()
