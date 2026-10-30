# larch cable schedule

Rendered by `mise run rack:fleet render` from `sites/larch.json`. Edit the site
definition, not this file. A Mac mini's serial, address and outlet are its
RackHost's, in the tuist chart's `rackFleet.hosts`.

| From | Port | To | NIC | Media | Purpose | Status |
|---|---|---|---|---|---|---|
| feed-a |  | larch-ats-a | source-1 | power | feed | planned |
| feed-a |  | larch-ats-b | source-1 | power | feed | planned |
| feed-a |  | larch-edge-a | psu-1 | power | feed | planned |
| feed-a |  | larch-edge-b | psu-1 | power | feed | planned |
| feed-a |  | larch-store-a | psu-1 | power | feed | planned |
| feed-a |  | larch-tor-a | psu-1 | power | feed | installed |
| feed-a |  | larch-tor-b | psu-1 | power | feed | installed |
| feed-b |  | larch-ats-a | source-2 | power | feed | planned |
| feed-b |  | larch-ats-b | source-2 | power | feed | planned |
| feed-b |  | larch-edge-a | psu-2 | power | feed | planned |
| feed-b |  | larch-edge-b | psu-2 | power | feed | planned |
| feed-b |  | larch-store-a | psu-2 | power | feed | planned |
| feed-b |  | larch-tor-a | psu-2 | power | feed | installed |
| feed-b |  | larch-tor-b | psu-2 | power | feed | installed |
| larch-ats-a |  | larch-pdu-a | inlet | power | power | planned |
| larch-ats-b |  | larch-pdu-b | inlet | power | power | planned |
| larch-tor-a | 23 | larch-pdu-b | netpack | copper | management | planned |
| larch-tor-a | 24 | larch-ats-b | netpack | copper | management | planned |
| larch-tor-a | 25 | larch-tor-b |  | dac | isl | installed |
| larch-tor-a | 26 | larch-tor-b |  | dac | isl | installed |
| larch-tor-a | 27 | Cogent |  | fibre | wan | installed |
| larch-tor-a | 28 | larch-edge-b | bmc | copper | management | planned |
| larch-tor-a | 29 | larch-edge-a | n225p-1 | dac | data | planned |
| larch-tor-a | 30 | larch-edge-b | n225p-1 | dac | data | planned |
| larch-tor-a | 31 | larch-store-a | n225p-1 | dac | data | planned |
| larch-tor-b | 22 | larch-store-a | bmc | copper | management | planned |
| larch-tor-b | 23 | larch-pdu-a | netpack | copper | management | planned |
| larch-tor-b | 24 | larch-ats-a | netpack | copper | management | planned |
| larch-tor-b | 25 | larch-tor-a |  | dac | isl | installed |
| larch-tor-b | 26 | larch-tor-a |  | dac | isl | installed |
| larch-tor-b | 27 | spare |  | fibre | wan | planned |
| larch-tor-b | 28 | larch-edge-a | bmc | copper | management | planned |
| larch-tor-b | 29 | larch-edge-a | n225p-2 | dac | data | planned |
| larch-tor-b | 30 | larch-edge-b | n225p-2 | dac | data | planned |
