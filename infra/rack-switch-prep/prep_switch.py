#!/usr/bin/env python3
"""Prepare a rack switch over its USB-C console port.

A factory switch has no usable network identity: TP-Link ships every unit on
192.168.0.1, which collides with the gateway of almost every network it is
unboxed on, and its SSH server is disabled. The console port is the only
interface that works regardless of addressing, so provisioning starts there and
ends with a switch that is reachable and key-driveable over the network.

Credentials never live in this repo. The admin account is read from (or created
in) 1Password with the `op` CLI, so the same command works for an operator who
has never touched the device.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import pathlib
import re
import select
import shutil
import socket
import subprocess
import sys
import tempfile
import termios
import time

BAUD_RATES = {9600: termios.B9600, 38400: termios.B38400, 115200: termios.B115200}
DEFAULT_BAUD = 38400
INVENTORY = pathlib.Path(__file__).with_name("switches.json")

PROMPT = re.compile(r"[\r\n][\w.-]+[>#]\s*$")
PAGER = re.compile(r"(press any key to continue|--more--|q to quit)", re.I)


class ConsoleError(RuntimeError):
    pass


class Console:
    """A line-oriented session on a switch console.

    These CLIs drop characters when a whole line arrives in one write, and they
    treat CR (not LF) as the submit key, so input is typed a character at a time.
    """

    def __init__(self, device: str, baud: int, echo: bool = False):
        self.fd = os.open(device, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        self.echo = echo
        attrs = termios.tcgetattr(self.fd)
        attrs[0] = 0
        attrs[1] = 0
        attrs[3] = 0
        attrs[2] = termios.CREAD | termios.CLOCAL | termios.CS8
        attrs[4] = attrs[5] = BAUD_RATES[baud]
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        termios.tcflush(self.fd, termios.TCIOFLUSH)

    def read(self, idle: float = 1.5, limit: float = 45.0, until_prompt: bool = False) -> str:
        """Read until the switch prompts again, or until it goes quiet.

        Waiting for silence alone is not enough: this CLI echoes a command well
        before it runs it, so a fixed pause lets the next line arrive mid-echo,
        where it is appended to the previous one and rejected as one bad command.
        """
        out = b""
        deadline = time.time() + limit
        quiet = time.time() + idle
        while time.time() < deadline:
            if select.select([self.fd], [], [], 0.2)[0]:
                try:
                    chunk = os.read(self.fd, 4096)
                except OSError:
                    break
                if chunk:
                    out += chunk
                    quiet = time.time() + idle
                    tail = out[-200:].decode("utf-8", "replace")
                    if PAGER.search(tail):
                        os.write(self.fd, b" ")
                    continue
            settled = time.time() > quiet
            if until_prompt:
                if PROMPT.search(out.decode("utf-8", "replace")) and settled:
                    break
            elif settled:
                break
        text = out.decode("utf-8", "replace").replace("\r", "")
        if self.echo and text.strip():
            print(text, end="", file=sys.stderr, flush=True)
        return text

    def send(self, line: str, idle: float = 1.0, secret: bool = False, until_prompt: bool = True,
             limit: float = 45.0) -> str:
        if self.echo:
            print(f"\n>>> {'*' * 8 if secret else line}", file=sys.stderr, flush=True)
        for char in line:
            os.write(self.fd, char.encode())
            time.sleep(0.02)
        time.sleep(0.3)
        os.write(self.fd, b"\r")
        return self.read(idle=idle, limit=limit, until_prompt=until_prompt)

    def close(self) -> None:
        os.close(self.fd)


def find_console(explicit: str | None) -> str:
    if explicit:
        return explicit
    candidates = sorted(glob.glob("/dev/cu.usbmodem*"))
    if not candidates:
        raise ConsoleError(
            "no USB console found. Connect a USB-C cable from this machine to the "
            "switch's console port, then retry."
        )
    if len(candidates) > 1:
        raise ConsoleError(f"several USB consoles present, pick one with --device: {candidates}")
    return candidates[0]


def op(args: list[str], account: str | None) -> subprocess.CompletedProcess:
    command = ["op", *args]
    if account:
        command += ["--account", account]
    return subprocess.run(command, capture_output=True, text=True)


def read_credentials(item: str, vault: str, account: str | None, create: bool) -> tuple[str, str]:
    """Fetch the switch's admin login, creating it on first run.

    A generated password stays letters and digits: TP-Link firmware rejects many
    symbols, and it does so after the account form is submitted, which on a
    console means starting the dialog again.
    """
    result = op(["item", "get", item, "--vault", vault, "--format=json"], account)
    if result.returncode != 0:
        if not create:
            raise ConsoleError(
                f"1Password item {item!r} not found in vault {vault!r}. "
                "Pass --create-credentials to generate it."
            )
        created = op(
            [
                "item", "create", "--category=login", f"--title={item}", "--vault", vault,
                "--generate-password=letters,digits,24", "--tags=ber1,rack,network",
                "username=tuist",
            ],
            account,
        )
        if created.returncode != 0:
            raise ConsoleError(f"could not create 1Password item: {created.stderr.strip()}")
        result = op(["item", "get", item, "--vault", vault, "--format=json"], account)
        if result.returncode != 0:
            raise ConsoleError(f"could not read back 1Password item: {result.stderr.strip()}")

    fields = {f.get("id"): f.get("value") for f in json.loads(result.stdout).get("fields", [])}
    username, password = fields.get("username"), fields.get("password")
    if not username or not password:
        raise ConsoleError(f"1Password item {item!r} has no username/password")
    return username, password


def login(console: Console, username: str, password: str) -> None:
    """Take the session from wherever it is to a privileged prompt."""
    banner = console.send("", idle=2.0, until_prompt=False)

    if "Set now" in banner or "set an administrator account" in banner:
        console.send("Y", idle=2.0, until_prompt=False)
        console.send(username, idle=2.0, until_prompt=False)
        console.send(password, idle=2.0, secret=True, until_prompt=False)
        banner = console.send(password, idle=3.0, secret=True, until_prompt=False)

    if "User:" in banner or "Username:" in banner or "Login invalid" in banner:
        console.send(username, idle=2.0, until_prompt=False)
        banner = console.send(password, idle=3.0, secret=True, until_prompt=False)

    if "Login invalid" in banner:
        raise ConsoleError(
            "the switch rejected the stored credentials. If this unit was set up by "
            "hand, update the 1Password item, or factory-reset the switch."
        )

    if "#" not in banner:
        banner = console.send("enable", idle=2.0)
    if "#" not in banner:
        raise ConsoleError(f"could not reach a privileged prompt, last output:\n{banner}")


def configure(console: Console, switch: dict, dry_run: bool) -> list[str]:
    commands = [
        "configure",
        f"hostname {switch['name']}",
        "interface vlan 1",
        f"ip address {switch['mgmt_ip']} {switch['mgmt_mask']}",
        "exit",
        "ip ssh server",
        "end",
        "copy running-config startup-config",
    ]
    if dry_run:
        return commands
    for command in commands:
        idle = 6.0 if command.startswith("copy") else 1.5
        output = console.send(command, idle=idle)
        if "Bad command" in output or "Invalid" in output:
            raise ConsoleError(f"switch rejected {command!r}:\n{output}")
    return commands


def local_address_for(peer: str) -> str:
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect((peer, 69))
        return probe.getsockname()[0]
    finally:
        probe.close()


def as_rfc4716(key_path: pathlib.Path, workdir: pathlib.Path) -> pathlib.Path:
    """These switches only accept RSA/DSA keys in RFC4716 form, under a short name."""
    text = key_path.read_text()
    target = workdir / "fleet.pub"
    if text.startswith("---- BEGIN SSH2"):
        target.write_text(text)
        return target
    converted = subprocess.run(["ssh-keygen", "-e", "-f", str(key_path)], capture_output=True, text=True)
    if converted.returncode != 0:
        raise ConsoleError(f"could not convert {key_path} to RFC4716: {converted.stderr.strip()}")
    if "ssh-ed25519" in text:
        raise ConsoleError("this firmware accepts RSA/DSA keys only; ed25519 will be rejected")
    target.write_text(converted.stdout)
    return target


def import_key(console: Console, switch: dict, key_path: pathlib.Path) -> None:
    """Have the switch pull its authorized key over TFTP from this machine.

    The alternative is a file upload in the web UI, which cannot be scripted and
    would leave one hand step per switch.
    """
    workdir = pathlib.Path(tempfile.mkdtemp(prefix="rack-switch-key-"))
    served = as_rfc4716(key_path, workdir)
    workdir.chmod(0o755)
    served.chmod(0o644)
    address = local_address_for(switch["mgmt_ip"])

    print("sudo is needed to serve TFTP on port 69:")
    if subprocess.run(["sudo", "-v"]).returncode != 0:
        raise ConsoleError("sudo declined; the switch can only fetch its key over TFTP")

    server = subprocess.Popen(
        ["sudo", "-n", sys.executable, str(pathlib.Path(__file__).with_name("tftp_serve.py")), str(served)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    try:
        ready = server.stdout.readline()
        if "tftp ready" not in ready:
            raise ConsoleError(f"TFTP server did not start: {ready.strip() or 'no output'}")
        print(f"serving {served.name} from {address}; the switch may take a few minutes")
        console.send("configure")
        output = console.send(
            f"ip ssh download v2 {served.name} ip-address {address}", idle=10.0, limit=420.0
        )
        console.send("end")
        if "Error" in output or "fail" in output.lower():
            raise ConsoleError(f"key download failed:\n{output}")
    finally:
        server.terminate()
        shutil.rmtree(workdir, ignore_errors=True)


def verify(console: Console, switch: dict) -> dict:
    info = console.send("show system-info", idle=4.0)
    address = console.send("show interface vlan 1", idle=3.0)

    def field(pattern: str, text: str) -> str:
        match = re.search(pattern, text)
        return match.group(1).strip() if match else ""

    found = {
        "name": field(r"System Name\s+-\s+(.+)", info),
        "hardware": field(r"Hardware Version\s+-\s+(.+)", info),
        "firmware": field(r"Software Version\s+-\s+(.+)", info),
        "mac": field(r"Mac Address\s+-\s+(.+)", info),
        "serial": field(r"Serial Number\s+-\s+(.+)", info),
        "ip": field(r"ip is ([0-9.]+)", address),
    }
    if found["name"] != switch["name"]:
        raise ConsoleError(f"hostname is {found['name']!r}, expected {switch['name']!r}")
    if found["ip"] != switch["mgmt_ip"]:
        raise ConsoleError(f"management address is {found['ip']!r}, expected {switch['mgmt_ip']!r}")
    return found


def main() -> int:
    inventory = json.loads(INVENTORY.read_text())
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("switch", choices=sorted(inventory["switches"]), help="inventory entry to apply")
    parser.add_argument("--device", help="console device (default: the only /dev/cu.usbmodem*)")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD, choices=sorted(BAUD_RATES))
    parser.add_argument("--vault", default=inventory["vault"], help="1Password vault holding the admin logins")
    parser.add_argument("--account", default=os.environ.get("OP_ACCOUNT"), help="1Password account")
    parser.add_argument("--create-credentials", action="store_true", help="generate the admin login if absent")
    parser.add_argument("--import-key", type=pathlib.Path, metavar="PATH",
                        help="have the switch fetch this SSH public key over TFTP (needs sudo for port 69)")
    parser.add_argument("--dry-run", action="store_true", help="print the commands without touching the switch")
    parser.add_argument("--verbose", action="store_true", help="echo the console session to stderr")
    args = parser.parse_args()

    switch = inventory["switches"][args.switch]
    switch.setdefault("name", args.switch)

    if args.dry_run:
        print(f"would apply to {switch['name']} ({switch['model']}):")
        for command in configure(None, switch, dry_run=True):
            print(f"  {command}")
        return 0

    device = find_console(args.device)
    username, password = read_credentials(
        switch["credential_item"], args.vault, args.account, args.create_credentials
    )

    print(f"console {device} at {args.baud} baud")
    console = Console(device, args.baud, echo=args.verbose)
    try:
        login(console, username, password)
        configure(console, switch, dry_run=False)
        if args.import_key:
            import_key(console, switch, args.import_key.expanduser())
        found = verify(console, switch)
    finally:
        console.close()

    print(f"{found['name']} ready: {found['hardware']}, firmware {found['firmware']}")
    print(f"  serial {found['serial']}, mac {found['mac']}, management {found['ip']}")
    if args.import_key:
        print(f"  fleet key imported; connect with ssh -i {args.import_key.with_suffix('')} tuist@{found['ip']}")
    else:
        print("  SSH is enabled, password-only. Pass --import-key to install the fleet key.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ConsoleError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
