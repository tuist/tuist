# Tart private networking to the cache node

## Key result

Two workable models were found, and one is clearly simpler.

### Model A: direct bridged private IP

Direct private guest-to-cache networking is possible on the test Mac.

The working model is:

- Tart VM booted with `--net-bridged=vlan0`
- guest manually assigned a static address in the cache subnet
- guest then reached the cache node directly at `172.16.16.4`

### Model B: NAT guest + host private relay

This is the recommended implementation.

- guest stays on default Tart NAT
- host relays `192.168.64.1:443` -> `172.16.16.4:443`
- guest maps the cache hostname to `192.168.64.1`

This preserves:

- guest public internet
- cache access over the host's private VPC path

## What does not work

### Default Tart NAT

- guest gets `192.168.64.x`
- guest can access the internet
- guest cannot reach `172.16.16.4`

### Bridged `vlan0` with DHCP only

- guest boots
- guest gets only a link-local `169.254.x.x`
- guest cannot reach the cache

## What does work

### Bridged `vlan0` with static private IP

Inside the guest:

```bash
sudo /sbin/ifconfig en0 inet 172.16.16.10 netmask 255.255.252.0 up
```

Then:

```bash
ping 172.16.16.4
curl -ksS https://172.16.16.4/up -D -
```

Both succeeded.

Host-side packet capture confirmed real L2/L3 traffic on the private VLAN.

## Public internet in the same VM

After setting DNS manually inside the guest:

```bash
/usr/sbin/networksetup -setdnsservers Ethernet 1.1.1.1 8.8.8.8
```

the same guest could also reach public internet endpoints.

Observed validated commands:

```bash
ping 8.8.8.8
curl -4 -I https://github.com
```

Both succeeded during the validated run.

## Practical implication

The direct bridged-static-IP model works, but it is not the easiest implementation.

The current recommended implementation is the host-relay model because it avoids:

- per-VM private IP allocation
- guest private-route management
- guest DNS bootstrapping complexity

## Recommended automation model

### Current recommendation

- keep Tart guests on NAT
- run a host relay on `192.168.64.1:443`
- map the cache hostname to `192.168.64.1` inside the guest

### Future optimization if needed

- switch to bridged-static-IP guests only if direct guest private identity becomes necessary

## Open questions

- whether the host relay should stay as `socat`, or become a managed launchd service using a more structured TCP proxy
- how the eventual worker lifecycle should manage cache-hostname injection and cleanup for each guest
- whether multiple simultaneous NAT guests using the same relay remain clean under real CI load

## Current recommendation

- keep Tart as the isolation direction
- use NAT guests plus a host private relay for cache traffic
- keep bridged-static-IP as a fallback or advanced mode
