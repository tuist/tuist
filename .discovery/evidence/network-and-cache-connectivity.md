# Evidence: network and cache connectivity

## Cache node facts

Source: SSH discovery on `cschmatzler@51.159.83.73`

```text
tuist-01-test-cache
ens2 UP 51.159.83.73/32
ens6 UP 172.16.16.4/22
default via 62.210.0.1 dev ens2
```

The cache node does have the expected Private Network interface:

- `ens6 = 172.16.16.4/22`

## Cache health

Public HTTPS health check works:

```text
curl -k https://tuist-01-test-cache.par.runners.tuist.dev/up
HTTP/2 200
UP! Version: e47107b5b9736194d4a091c59e530660c5f13988_uncommitted_d376de4cee7219c5
```

## Mac routing reality today

Source: SSH discovery on `m1@51.159.120.232`

```text
route to: 172.16.16.4
destination: default
gateway: 51.159.120.1
interface: en0
```

Relevant interface state:

```text
en0 inet 51.159.120.232 netmask 0xffffff00
```

No private interface or VLAN is present.

## Connectivity tests from the Mac

```text
ping 172.16.16.4
100.0% packet loss
```

```text
curl http://172.16.16.4/up
curl: (28) Connection timed out after 5009 milliseconds
```

```text
curl -I http://172.16.16.4/metrics
curl: (7) Failed to connect to 172.16.16.4 port 80 after 4008 ms
```

## VLAN state on the Mac

```text
networksetup -listVLANs
There are no VLANs currently configured on this system.
```

## VLAN tag discovery

The VLAN tag was discovered empirically by capturing tagged frames on the Mac's `en0` while the cache node sent ARP traffic for `172.16.16.3`:

```text
ethertype 802.1Q (0x8100) ... vlan 1597 ... ARP who-has 172.16.16.3 tell 172.16.16.4
```

This matched the Scaleway Private Network trunk carrying the cache node's private traffic.

## macOS VLAN bring-up

With passwordless sudo enabled on the Mac, this command worked:

```text
sudo networksetup -createVLAN pn en0 1597
```

After DHCP settled:

```text
vlan0 inet 172.16.16.3/22
route to 172.16.16.4 via vlan0
```

## Interpretation

- The cache side is already on the Private Network.
- The Mac side required a local VLAN interface before it became usable.
- The VLAN setup on the Mac is now understood and reproducible.
- A second issue was uncovered on the cache node: it was missing the connected route for `172.16.16.0/22`.

## Cache-node routing bug

Before the temporary fix, the cache node resolved the Mac's private address over the public gateway:

```text
ip route get 172.16.16.3
172.16.16.3 via 62.210.0.1 dev ens2 src 51.159.83.73
```

The cause was visible on `ens6`:

```text
inet 172.16.16.4/22 scope global dynamic noprefixroute ens6
```

There was no `172.16.16.0/22` route in the main routing table until it was added manually.

Temporary validation fix:

```text
sudo ip route add 172.16.16.0/22 dev ens6 src 172.16.16.4
```

After adding that route:

```text
ip route get 172.16.16.3
172.16.16.3 dev ens6 src 172.16.16.4
```

And private connectivity fully worked:

```text
Mac -> cache ping: success
Mac -> https://172.16.16.4/up: HTTP/2 200
Cache -> Mac ping: success
```

## Declarative fix deployed

The route fix is now deployed through NixOS on the cache node.

Post-deploy verification:

```text
ip route get 172.16.16.3
172.16.16.3 dev ens6 src 172.16.16.4
```

The connected route is present in the main table:

```text
172.16.16.0/22 dev ens6 scope link src 172.16.16.4
```
