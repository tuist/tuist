"""Hardware facts per switch model.

Port naming is a property of the model, not of the site, so a config rendered
for a role works on any rack once the model is described here. `verified` says
whether the naming was read off a real unit: an unverified model renders, so the
design can be reviewed, but will not be applied.
"""

MODELS = {
    "sx3832": {
        "product": "TP-Link Omada SX3832",
        "banner": "!SX3832",
        "verified": True,
        "port_groups": [
            {"prefix": "ten-gigabitEthernet", "unit": "1/0", "first": 1, "last": 32},
        ],
    },
    "tl-sg3452": {
        "product": "TP-Link JetStream TL-SG3452",
        "banner": "!TL-SG3452",
        "verified": False,
        "port_groups": [
            {"prefix": "gigabitEthernet", "unit": "1/0", "first": 1, "last": 48},
            {"prefix": "ten-gigabitEthernet", "unit": "1/0", "first": 49, "last": 52},
        ],
    },
}


def model(name):
    if name not in MODELS:
        raise KeyError(f"unknown switch model {name!r}; add it to models.py")
    return MODELS[name]


def ports(name):
    """Every port of the model, in device order, as (number, interface name)."""
    out = []
    for group in model(name)["port_groups"]:
        for n in range(group["first"], group["last"] + 1):
            out.append((n, f"{group['prefix']} {group['unit']}/{n}"))
    return out
