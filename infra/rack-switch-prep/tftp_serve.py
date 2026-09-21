#!/usr/bin/env python3
"""Serve one file over TFTP, read-only, until killed.

The switch fetches its SSH key over TFTP and always asks on port 69, so this
needs root. It is a separate process precisely so the rest of the provisioning
runs as the operator, whose 1Password session does not survive sudo.
"""

import os
import socket
import struct
import sys

RRQ, DATA, ACK, ERROR = 1, 3, 4, 5
BLOCK = 512


def serve(path: str, port: int) -> None:
    payload = open(path, "rb").read()
    offered = os.path.basename(path)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", port))
    print(f"tftp ready on {port} serving {offered} ({len(payload)} bytes)", flush=True)

    while True:
        request, client = sock.recvfrom(2048)
        if struct.unpack("!H", request[:2])[0] != RRQ:
            continue
        requested = request[2:].split(b"\x00")[0].decode("utf-8", "replace")
        print(f"request from {client[0]} for {requested}", flush=True)

        session = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        session.settimeout(5)
        try:
            block = 1
            for start in range(0, max(len(payload), 1), BLOCK):
                chunk = payload[start:start + BLOCK]
                for _ in range(5):
                    session.sendto(struct.pack("!HH", DATA, block) + chunk, client)
                    try:
                        reply, _ = session.recvfrom(1024)
                    except socket.timeout:
                        continue
                    code, acked = struct.unpack("!HH", reply[:4])
                    if code == ACK and acked == block:
                        break
                    if code == ERROR:
                        raise OSError(reply[4:].split(b"\x00")[0].decode("utf-8", "replace"))
                else:
                    raise OSError(f"no ack for block {block}")
                block += 1
            print(f"sent {offered} to {client[0]}", flush=True)
        except OSError as error:
            print(f"transfer to {client[0]} failed: {error}", flush=True)
        finally:
            session.close()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: tftp_serve.py <file> [port]", file=sys.stderr)
        sys.exit(2)
    serve(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 69)
