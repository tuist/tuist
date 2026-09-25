# ber1 cable schedule

Rendered by `mise run rack:fleet render` from `sites/ber1.json`. Edit the site
definition, not this file. Mac minis are RackHosts, in the tuist chart's
`rackFleet.hosts`, and are not listed.

| From | Port | To | NIC | Media | Purpose | Status |
|---|---|---|---|---|---|---|
| ber1-ats-1 |  | ber1-edge-a | psu | power | power | planned |
| ber1-ats-2 |  | ber1-edge-b | psu | power | power | planned |
| ber1-mgmt | 1 | ber1-edge-a | i226-lm | copper | management | installed |
| ber1-mgmt | 2 | ber1-edge-b | i226-lm | copper | management | installed |
| ber1-mgmt | 47 | ber1-edge-b | i226-v | copper | edge | installed |
| ber1-mgmt | 48 | ber1-edge-a | i226-v | copper | edge | installed |
| ber1-mgmt |  | ber1-ats-1 | netpack | copper | management | planned |
| ber1-mgmt |  | ber1-ats-2 | netpack | copper | management | planned |
| ber1-mgmt |  | ber1-ats-3 | netpack | copper | management | planned |
| ber1-mgmt |  | ber1-kvm-a | mgmt | copper | management | installed |
| ber1-mgmt |  | ber1-kvm-b | mgmt | copper | management | installed |
| ber1-mgmt |  | ber1-pdu-a | netpack | copper | management | planned |
| ber1-mgmt |  | ber1-pdu-b | netpack | copper | management | planned |
| ber1-mgmt |  | ber1-store-a | i226-lm | copper | management | planned |
| ber1-mgmt |  | ber1-store-b | i226-lm | copper | management | planned |
| ber1-tor-a | 24 | router |  | copper | wan | installed |
| ber1-tor-a | 25 | ber1-edge-a | sfp28-2 | dac | data | installed |
| ber1-tor-a | 26 | ber1-edge-b | sfp28-2 | dac | data | installed |
| ber1-tor-a | 31 | ber1-tor-b |  | dac | isl | planned |
| ber1-tor-a | 32 | ber1-tor-b |  | dac | isl | installed |
| ber1-tor-a |  | ber1-store-a | sfp28-1 | dac | data | planned |
| ber1-tor-b | 25 | ber1-edge-a | sfp28-1 | dac | data | installed |
| ber1-tor-b | 26 | ber1-edge-b | sfp28-1 | dac | data | installed |
| ber1-tor-b | 31 | ber1-tor-a |  | dac | isl | planned |
| ber1-tor-b | 32 | ber1-tor-a |  | dac | isl | installed |
| ber1-tor-b |  | ber1-store-b | sfp28-1 | dac | data | planned |
