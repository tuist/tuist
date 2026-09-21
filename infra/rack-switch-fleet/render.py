"""Render a switch's whole configuration from its role and its site.

The output is the device's own configuration-file syntax, so it can be compared
line for line against `show running-config` and, once the TFTP round-trip is
known to carry text, pushed back whole.

Two things are deliberately left out of the rendered state:

- the local admin login, which `rack:prep-switch` owns out of 1Password. A
  rendered config is committed, and a password hash does not belong in git.
- anything whose syntax has not been read off a live unit. Guessing a command
  and pushing it is how a switch is lost.
"""

import models

UNMANAGED_PREFIXES = ("user name",)


def _quote(value):
    return '"%s"' % value


def _globals(site, device):
    site_services = site["services"]
    out = [
        "vlan %d" % site["management"]["vlan"],
        " name %s" % _quote(site["management"]["vlan_name"]),
        "#",
        "hostname %s" % _quote(device["name"]),
        "serial_port baud_rate %d" % device["console_baud"],
        "#",
        "no system-time dst",
        "#",
        "telnet enable" if site_services["telnet"] else "telnet disable",
        "no service reset-disable",
        "#",
        "spanning-tree",
        "spanning-tree mode %s" % site_services["spanning_tree"],
        "#",
        "snmp-server" if site_services["snmp"] else "no snmp-server",
        "#",
        "ip http server" if site_services["http"] else "no ip http server",
        "#",
        "lldp" if site_services["lldp"] else "no lldp",
        "#",
    ]
    if not site_services["cloud_controller"]:
        out += ["no controller cloud-based", "no controller cloud-based privacy-policy", "#"]
    return out


def _management_interface(site, device):
    return [
        "interface vlan %d" % site["management"]["vlan"],
        "  ip address %s %s" % (device["mgmt_address"], site["management"]["netmask"]),
        "  ipv6 enable",
        "#",
    ]


def _interfaces(site, device):
    out = []
    for _, name in models.ports(device["model"]):
        out.append("interface %s" % name)
        out.append("  spanning-tree")
        out.append("#")
    return out


def check_ports(device):
    """The site's wiring record has to describe ports the model actually has."""
    available = {number for number, _ in models.ports(device["model"])}
    for port in device.get("ports", {}):
        if int(port) not in available:
            raise ValueError(
                f"{device['name']} declares port {port}, which a "
                f"{models.model(device['model'])['product']} does not have"
            )


def render(site, device):
    """The device's whole desired configuration, as config-file text."""
    spec = models.model(device["model"])
    check_ports(device)
    lines = [spec["banner"], "#"]
    lines += _globals(site, device)
    lines += _management_interface(site, device)
    lines += _interfaces(site, device)
    lines.append("end")
    return "\n".join(lines) + "\n"


def device_by_name(site, name):
    for device in site["devices"]:
        if device["name"] == name:
            return device
    known = ", ".join(d["name"] for d in site["devices"])
    raise KeyError(f"{name!r} is not in this site; known devices: {known}")


def apply_order(site):
    """Devices in the order they may be changed, safest blast radius first."""
    return sorted(site["devices"], key=lambda d: d["apply_order"])
