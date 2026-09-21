# Rack switch prep

First-touch provisioning for the BER1 rack's switches, driven over the USB-C
console port. Run it once per switch, at the bench or in the colo, before the
switch has any usable network identity.

## Why the console and not the network

A factory TP-Link switch sits on 192.168.0.1 with SSH disabled. That address is
the default gateway on most networks it will ever be unboxed on, so the first
thing a new switch does is collide with the router, and the collision is
invisible: the switch answers ARP sometimes, the router answers the rest of the
time, and nothing that tries to reach either is reliable. Configuring over the
network therefore means isolating the switch first, which is fiddly and easy to
get wrong halfway.

The console has none of that. It works with no addressing at all, it works when
the configuration is broken, and it is the same path remote hands will use in
the colo when a switch is unreachable.

## Usage

```
mise run rack:prep-switch ber1-tor-a
mise run rack:prep-switch ber1-tor-b --verbose
mise run rack:prep-switch ber1-mgmt --dry-run
```

Connect a USB-C cable from the machine running the command to the switch's
console port. The script finds the console device itself, handles a
factory-fresh unit and an already-configured one, and leaves the switch with its
hostname, a fixed management address, SSH enabled and the configuration saved to
startup.

Add `--create-credentials` on the very first run of a switch to have the admin
login generated in 1Password.

## What it sets, and what it deliberately does not

It sets the hostname, the VLAN 1 management address from `switches.json`, and
the SSH server, then writes the running config to startup. Everything else
(VLANs, trunks, SNMP, ISL) is fleet configuration that applies to a pair of
switches at once and belongs in a reviewed change, not in per-device bring-up.

It does not import the fleet SSH public key, because these firmwares only accept
a key as a file upload through the web UI. The script prints the exact page to
finish on. Until the key is imported, the switch is password-only, which is why
the credentials live in 1Password rather than in someone's notes.

## Hardware facts worth keeping

- The console runs at **38400 8N1**, not the 115200 these usually default to.
  A remote-hands tech given the wrong speed sees silence, not an error.
- The CLI treats **CR** as submit, and drops characters when a line is written
  in one burst, so the driver types one character at a time. A line-at-a-time
  paste silently produces concatenated commands such as `enableshow system-info`.
- `show` output pages with `Press any key to continue (Q to quit)`; the driver
  answers it. Anything scraping this CLI needs to.
- Firmware lines are not interchangeable: a unit reporting hardware `1.20` takes
  `1.20.x` firmware, while `V1.6` units take `1.0.x`. The `V1.6` builds carry
  higher dates and lower version numbers, so "newest" is the wrong instinct and
  flashing across lines bricks the switch.
- The `ip ssh version 2` command does not exist on these; SSH v2 is on by
  default and v1 is off.

## Inventory

`switches.json` is the source of truth for names and management addresses. The
addresses sit below the DHCP pool on the prep-bay network; in the colo they move
to the management VLAN and this file moves with them. Adding a switch is a pull
request against that file, the same way machine inventory is.
