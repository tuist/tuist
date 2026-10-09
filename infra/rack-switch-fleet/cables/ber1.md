# ber1 cable schedule

Rendered by `mise run rack:fleet render` from `sites/ber1.json`. Edit the site
definition, not this file. A Mac mini's serial, address and outlet are its
RackHost's, in the tuist chart's `rackFleet.hosts`.

| From | Port | To | NIC | Media | Purpose | Status |
|---|---|---|---|---|---|---|
| ber1-ats-1 |  | ber1-edge-a | psu | power | power | installed |
| ber1-ats-1 |  | ber1-kvm-a | psu | power | power | installed |
| ber1-ats-1 |  | ber1-kvm-b | psu | power | power | installed |
| ber1-ats-1 |  | ber1-mgmt | psu | power | power | installed |
| ber1-ats-1 |  | ber1-store-a | psu | power | power | installed |
| ber1-ats-1 |  | ber1-tor-a | psu | power | power | installed |
| ber1-ats-2 |  | ber1-pdu-a | inlet | power | power | planned |
| ber1-ats-3 |  | ber1-pdu-b | inlet | power | power | installed |
| ber1-mgmt | 1 | ber1-edge-a | i226-lm | copper | management | installed |
| ber1-mgmt | 2 | ber1-edge-b | i226-lm | copper | management | installed |
| ber1-mgmt | 3 | ber1-store-a | i226-lm | copper | management | installed |
| ber1-mgmt | 41 | ber1-ats-1 | netpack | copper | management | installed |
| ber1-mgmt | 42 | ber1-ats-2 | netpack | copper | management | planned |
| ber1-mgmt | 43 | ber1-ats-3 | netpack | copper | management | installed |
| ber1-mgmt | 44 | ber1-pdu-a | netpack | copper | management | planned |
| ber1-mgmt | 45 | ber1-pdu-b | netpack | copper | management | installed |
| ber1-mgmt | 47 | ber1-edge-b | i226-v | copper | edge | installed |
| ber1-mgmt | 48 | ber1-edge-a | i226-v | copper | edge | installed |
| ber1-mgmt |  | ber1-kvm-a | mgmt | copper | management | installed |
| ber1-mgmt |  | ber1-kvm-b | mgmt | copper | management | installed |
| ber1-mgmt |  | ber1-store-b | i226-lm | copper | management | planned |
| ber1-pdu-b |  | ber1-edge-b | psu | power | power | installed |
| ber1-pdu-b |  | ber1-store-b | psu | power | power | planned |
| ber1-pdu-b |  | ber1-tor-b | psu | power | power | installed |
| ber1-tor-a | 24 | router |  | copper | wan | installed |
| ber1-tor-a | 25 | ber1-edge-a | sfp28-2 | dac | data | installed |
| ber1-tor-a | 26 | ber1-edge-b | sfp28-2 | dac | data | installed |
| ber1-tor-a | 27 | ber1-store-a | sfp28-1 | dac | data | installed |
| ber1-tor-a | 31 | ber1-tor-b |  | dac | isl | planned |
| ber1-tor-a | 32 | ber1-tor-b |  | dac | isl | installed |
| ber1-tor-b | 2 | ber1-runner-b01 | en0 | copper | data | installed |
| ber1-tor-b | 3 | ber1-runner-b02 | en0 | copper | data | installed |
| ber1-tor-b | 4 | ber1-runner-b03 | en0 | copper | data | installed |
| ber1-tor-b | 25 | ber1-edge-a | sfp28-1 | dac | data | installed |
| ber1-tor-b | 26 | ber1-edge-b | sfp28-1 | dac | data | installed |
| ber1-tor-b | 31 | ber1-tor-a |  | dac | isl | planned |
| ber1-tor-b | 32 | ber1-tor-a |  | dac | isl | installed |
| ber1-tor-b |  | ber1-store-b | sfp28-1 | dac | data | planned |
| feed-a |  | ber1-ats-1 | source-1 | power | feed | installed |
| feed-a |  | ber1-ats-2 | source-1 | power | feed | planned |
| feed-a |  | ber1-ats-3 | source-1 | power | feed | installed |
| feed-b |  | ber1-ats-1 | source-2 | power | feed | installed |
| feed-b |  | ber1-ats-2 | source-2 | power | feed | planned |
| feed-b |  | ber1-ats-3 | source-2 | power | feed | installed |
