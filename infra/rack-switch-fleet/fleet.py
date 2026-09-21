#!/usr/bin/env python3
"""Config as code for a rack's switches: render, diff, apply, back up, detect drift.

    render        write each device's desired configuration from the site definition
    diff          compare a device's live configuration with the rendered one
    apply         make a device match its rendered configuration, then prove it did
    backup        capture a device's startup configuration into the repository
    drift         diff every device in the site; non-zero exit when any has drifted
    probe-tftp    ask whether this firmware's TFTP config export is text or binary

Run through `mise run rack:fleet <command>`.
"""

import argparse
import json
import os
import pathlib
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import config_text as ct
import models
import render as render_module
import session as session_module

ROOT = pathlib.Path(__file__).resolve().parent
RUNNING_CONFIG = "show running-config"
STARTUP_CONFIG = "show startup-config"


def load_site(name):
    path = ROOT / "sites" / f"{name}.json"
    if not path.exists():
        known = ", ".join(sorted(p.stem for p in (ROOT / "sites").glob("*.json")))
        raise SystemExit(f"no site definition {path}; known sites: {known}")
    return json.loads(path.read_text())


def selected_devices(site, name):
    if name:
        return [render_module.device_by_name(site, name)]
    return render_module.apply_order(site)


def config_path(site, device):
    return ROOT / "configs" / site["site"] / f"{device['name']}.cfg"


def backup_path(site, device):
    return ROOT / "backups" / site["site"] / f"{device['name']}.cfg"


def open_session(site, device, verbose):
    credentials = site["credentials"]
    return session_module.Session(
        device["mgmt_address"], credentials["username"], credentials["ssh_key"], verbose
    )


def read_config(session, command):
    output = session.run(command)
    return ct.strip_transcript(output, command)


def cmd_render(args):
    site = load_site(args.site)
    stale = []
    for device in selected_devices(site, args.device):
        text = render_module.render(site, device)
        path = config_path(site, device)
        path.parent.mkdir(parents=True, exist_ok=True)
        if args.check:
            if not path.exists() or path.read_text() != text:
                stale.append(path)
            continue
        path.write_text(text)
        print(f"rendered {path.relative_to(ROOT.parent.parent)}")
    if stale:
        for path in stale:
            print(f"stale: {path.relative_to(ROOT.parent.parent)}", file=sys.stderr)
        print("the rendered configs no longer match the site definition; "
              "run `mise run rack:fleet render`", file=sys.stderr)
        return 1
    if args.check:
        print("rendered configs are up to date with the site definition")
    return 0


def device_diff(site, device, verbose):
    desired = render_module.render(site, device)
    with open_session(site, device, verbose) as switch:
        actual = read_config(switch, RUNNING_CONFIG)
    return ct.diff(desired, actual, f"rendered/{device['name']}", f"live/{device['name']}"), actual


def cmd_diff(args):
    site = load_site(args.site)
    drifted = 0
    for device in selected_devices(site, args.device):
        lines, _ = device_diff(site, device, args.verbose)
        if lines:
            drifted += 1
            print(f"\n{device['name']}: drifted")
            for line in lines:
                print(line)
        else:
            print(f"{device['name']}: matches the rendered configuration")
    return 1 if drifted else 0


def cmd_drift(args):
    site = load_site(args.site)
    args.device = None
    status = cmd_diff(args)
    if status:
        print("\nDrift means someone changed a switch outside this repository, most likely "
              "in the web UI during an incident. Fold the change into the site definition "
              "and re-render, or apply to put the switch back.", file=sys.stderr)
    return status


def preceding_devices_clean(site, device, verbose):
    """The apply ordering, enforced rather than written down.

    A device is only safe to change once every switch with a smaller blast
    radius already carries the change and the rack survived it.
    """
    for earlier in render_module.apply_order(site):
        if earlier["apply_order"] >= device["apply_order"]:
            break
        lines, _ = device_diff(site, earlier, verbose)
        if lines:
            return earlier
    return None


def cmd_apply(args):
    site = load_site(args.site)
    device = render_module.device_by_name(site, args.device)
    spec = models.model(device["model"])

    if not spec["verified"]:
        raise SystemExit(
            f"{device['name']} is a {spec['product']}, whose port naming has never been read "
            f"off a live unit. Confirm it, set verified in models.py, then apply."
        )

    if not args.skip_order_check:
        blocker = preceding_devices_clean(site, device, args.verbose)
        if blocker is not None:
            raise SystemExit(
                f"{blocker['name']} has not been brought to its rendered configuration yet, and it "
                f"is applied before {device['name']}.\n\n{blocker['name']}: {blocker['apply_note']}\n\n"
                f"Apply to {blocker['name']} first, confirm the rack is healthy, then come back."
            )

    desired = render_module.render(site, device)
    with open_session(site, device, args.verbose) as switch:
        actual = read_config(switch, RUNNING_CONFIG)
        additions, removals = ct.plan(desired, actual)

        if removals:
            print(f"{device['name']} carries configuration the render does not describe:")
            for context, command in removals:
                print(f"  [{context or 'global'}] {command}")
            print("Turning an arbitrary line into its `no` form is a guess, so these are left "
                  "alone. Fold them into the site definition, or clear them by hand.\n")

        if not additions:
            print(f"{device['name']}: already matches the rendered configuration, nothing to apply")
            return 0

        commands = ct.plan_commands(additions)
        print(f"{device['name']} ({device['mgmt_address']}) would run:")
        for command in commands:
            print(f"  {command}")
        if args.dry_run:
            return 0
        if not args.yes:
            if not sys.stdin.isatty():
                raise SystemExit("nothing to confirm from; re-run with --yes or --dry-run")
            print(f"\n{device['name']}: {device['apply_note']}")
            if input("apply? [y/N] ").strip().lower() != "y":
                return 130

        for command in commands:
            switch.run(command)
        switch.run("copy running-config startup-config")

        after = read_config(switch, RUNNING_CONFIG)

    lines = ct.diff(desired, after, f"rendered/{device['name']}", f"live/{device['name']}")
    if lines:
        print(f"\n{device['name']}: applied, but the switch still does not match the render:")
        for line in lines:
            print(line)
        return 1
    print(f"\n{device['name']}: applied and verified against the rendered configuration")
    return 0


def cmd_backup(args):
    site = load_site(args.site)
    for device in selected_devices(site, args.device):
        with open_session(site, device, args.verbose) as switch:
            startup = read_config(switch, STARTUP_CONFIG)
        path = backup_path(site, device)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(ct.redact(startup))
        print(f"backed up {device['name']} to {path.relative_to(ROOT.parent.parent)}")
    return 0


def cmd_probe_tftp(args):
    """Answer the open question: is the exported config text, or is it opaque?

    If it is text, a change becomes `copy tftp startup-config` of a file rendered
    from this repository, and the restore path and the change path are the same
    code. If it is opaque, config as code here can only ever drive the CLI.
    """
    site = load_site(args.site)
    device = render_module.device_by_name(site, args.device)
    filename = f"{device['name']}-probe.cfg"
    served = pathlib.Path("/private/tftpboot") / filename

    local_address = subprocess.run(
        ["route", "-n", "get", device["mgmt_address"]],
        capture_output=True, text=True,
    ).stdout
    interface = next((l.split()[-1] for l in local_address.splitlines() if "interface:" in l), None)
    if not interface:
        raise SystemExit(f"no route to {device['mgmt_address']}")
    local_ip = subprocess.run(["ipconfig", "getifaddr", interface],
                              capture_output=True, text=True).stdout.strip()
    if not local_ip:
        raise SystemExit(f"no address on {interface} toward {device['mgmt_address']}")

    print(f"serving TFTP from {local_ip} (needs sudo: TFTP is always requested on port 69)")
    subprocess.run(["sudo", "-v"], check=True)
    subprocess.run(["sudo", "touch", str(served)], check=True)
    subprocess.run(["sudo", "chmod", "666", str(served)], check=True)
    subprocess.run(["sudo", "launchctl", "enable", "system/com.apple.tftpd"], check=False)
    subprocess.run(["sudo", "launchctl", "bootstrap", "system",
                    "/System/Library/LaunchDaemons/tftp.plist"], check=False)
    try:
        with open_session(site, device, args.verbose) as switch:
            switch.run(f"copy startup-config tftp ip-address {local_ip} filename {filename}", timeout=180)
        data = served.read_bytes()
    finally:
        subprocess.run(["sudo", "launchctl", "bootout", "system/com.apple.tftpd"], check=False)

    if not data:
        raise SystemExit("the switch wrote nothing; the transfer did not complete")
    printable = sum(1 for b in data if 9 <= b <= 13 or 32 <= b <= 126)
    ratio = printable / len(data)
    destination = ROOT / "backups" / site["site"] / f"{device['name']}-tftp-probe.bin"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
    print(f"\n{len(data)} bytes, {ratio:.0%} printable, saved to {destination}")
    if ratio > 0.95:
        print("TEXT. The config round-trips as readable text, so a change can be a whole-config "
              "replace: render, `copy tftp startup-config`, reboot, re-read, diff.")
        subprocess.run(["sudo", "rm", "-f", str(served)], check=False)
        return 0
    print("OPAQUE. The exported file is not text, so the rendered state cannot be pushed whole. "
          "Config as code here stays CLI-driven, with `show running-config` as the diff source.")
    subprocess.run(["sudo", "rm", "-f", str(served)], check=False)
    return 0


def main():
    parser = argparse.ArgumentParser(prog="rack:fleet", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--site", default="ber1")
    parser.add_argument("--verbose", action="store_true")
    subparsers = parser.add_subparsers(dest="command", required=True)

    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("device", nargs="?")
    render_parser.add_argument("--check", action="store_true",
                               help="fail if the committed configs are out of date")
    render_parser.set_defaults(func=cmd_render)

    diff_parser = subparsers.add_parser("diff")
    diff_parser.add_argument("device", nargs="?")
    diff_parser.set_defaults(func=cmd_diff)

    apply_parser = subparsers.add_parser("apply")
    apply_parser.add_argument("device")
    apply_parser.add_argument("--dry-run", action="store_true")
    apply_parser.add_argument("--yes", action="store_true")
    apply_parser.add_argument("--skip-order-check", action="store_true",
                              help="apply out of order; only for recovering a single switch")
    apply_parser.set_defaults(func=cmd_apply)

    backup_parser = subparsers.add_parser("backup")
    backup_parser.add_argument("device", nargs="?")
    backup_parser.set_defaults(func=cmd_backup)

    drift_parser = subparsers.add_parser("drift")
    drift_parser.set_defaults(func=cmd_drift)

    probe_parser = subparsers.add_parser("probe-tftp")
    probe_parser.add_argument("device")
    probe_parser.set_defaults(func=cmd_probe_tftp)

    args = parser.parse_args()
    try:
        return args.func(args)
    except session_module.SwitchError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
