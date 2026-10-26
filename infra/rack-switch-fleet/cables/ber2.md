# ber2 cable schedule

Rendered by `mise run rack:fleet render` from `sites/ber2.json`. Edit the site
definition, not this file. A Mac mini's serial, address and outlet are its
RackHost's, in the tuist chart's `rackFleet.hosts`.

| From | Port | To | NIC | Media | Purpose | Status |
|---|---|---|---|---|---|---|
| ber2-ats-a |  | ber2-pdu-a | inlet | power | power | planned |
| ber2-ats-b |  | ber2-pdu-b | inlet | power | power | planned |
| ber2-pdu-a |  | ber2-kvm-a | psu | power | power | planned |
| ber2-pdu-b |  | ber2-kvm-b | psu | power | power | planned |
| ber2-tor-a | 23 | ber2-pdu-b | netpack | copper | management | planned |
| ber2-tor-a | 24 | ber2-ats-b | netpack | copper | management | planned |
| ber2-tor-a | 25 | ber2-tor-b |  | dac | isl | installed |
| ber2-tor-a | 26 | ber2-tor-b |  | dac | isl | installed |
| ber2-tor-a | 27 | first carrier |  | fibre | wan | installed |
| ber2-tor-a | 28 | ber2-edge-b | bmc | copper | management | planned |
| ber2-tor-a | 29 | ber2-edge-a | n225p-1 | dac | data | planned |
| ber2-tor-a | 30 | ber2-edge-b | n225p-1 | dac | data | planned |
| ber2-tor-a | 31 | ber2-store-a | n225p-1 | dac | data | planned |
| ber2-tor-a | 32 | ber2-kvm-b | mgmt | copper | management | planned |
| ber2-tor-b | 23 | ber2-pdu-a | netpack | copper | management | planned |
| ber2-tor-b | 24 | ber2-ats-a | netpack | copper | management | planned |
| ber2-tor-b | 25 | ber2-tor-a |  | dac | isl | installed |
| ber2-tor-b | 26 | ber2-tor-a |  | dac | isl | installed |
| ber2-tor-b | 27 | second carrier |  | fibre | wan | planned |
| ber2-tor-b | 28 | ber2-edge-a | bmc | copper | management | planned |
| ber2-tor-b | 29 | ber2-edge-a | n225p-2 | dac | data | planned |
| ber2-tor-b | 30 | ber2-edge-b | n225p-2 | dac | data | planned |
| ber2-tor-b | 31 | ber2-store-a | bmc | copper | management | planned |
| ber2-tor-b | 32 | ber2-kvm-a | mgmt | copper | management | planned |
| feed-a |  | ber2-ats-a | source-1 | power | feed | planned |
| feed-a |  | ber2-ats-b | source-1 | power | feed | planned |
| feed-a |  | ber2-edge-a | psu-1 | power | feed | planned |
| feed-a |  | ber2-edge-b | psu-1 | power | feed | planned |
| feed-a |  | ber2-store-a | psu-1 | power | feed | planned |
| feed-a |  | ber2-tor-a | psu-1 | power | feed | installed |
| feed-a |  | ber2-tor-b | psu-1 | power | feed | installed |
| feed-b |  | ber2-ats-a | source-2 | power | feed | planned |
| feed-b |  | ber2-ats-b | source-2 | power | feed | planned |
| feed-b |  | ber2-edge-a | psu-2 | power | feed | planned |
| feed-b |  | ber2-edge-b | psu-2 | power | feed | planned |
| feed-b |  | ber2-store-a | psu-2 | power | feed | planned |
| feed-b |  | ber2-tor-a | psu-2 | power | feed | installed |
| feed-b |  | ber2-tor-b | psu-2 | power | feed | installed |
