# Bringing up a new rack site

The order a new site goes from boxes to taking jobs, written for larch (rack 2,
NTT Berlin 1, handed over on 9 Nov 2026) and meant for every site after it.
The site definition is `infra/rack-switch-fleet/sites/<site>.json`, and the
printed cable schedule is `infra/rack-switch-fleet/cables/<site>.md`.

The order is the one the hardware imposes: the network first, then the servers
that serve it, and the minis' power last. A mini powered before its ToR port
is on the machines VLAN enrolls on the wrong VLAN and keeps that lease (a
lesson from ber1). Nothing below needs a login on site except where a step
says "hands-on".

```
P="--context tuist-k8s-production"
SITE=larch
```

## Before the day (remote)

1. **The site's data is in.** Each item goes in through a PR to the site file
   or the production values. What is still missing for larch:
   - `larch-tor-b`'s label MAC, its `adopted: true`, and
     `larch-edge-b`'s `tor_management` (192.168.61.5/30). This one gates
     the other ToR: tor-b is first in the site's apply order, and the
     controller adopts no switch while one before it is not Ready, which a
     standalone PicOS switch never is. Without it, `larch-tor-a` stays at
     `Adopted=False/WaitingForApplyOrder`. The first edge's way out does
     not depend on it: the bootstrap's WAN path needs no controller.
   - The edges' and storage node's unit sheets from primeLine (serial, UUID,
     NIC MACs and TPM check code) as `rackLinuxFleet.hosts` with
     `site: larch`. Until then they have nothing to enrol against.
   - The ten minis: serial and en0 MAC from each box label, chain (A on
     `larch-tor-a` and `larch-pdu-a`, B on the B side, five each), PDU
     outlet and tray, as site-file nodes now. Declare them as `rackFleet` hosts
     only once the site's WAN is lit: the rack fleet's MachineHealthCheck
     spans every site and tolerates one unhealthy Machine, so ten dark larch
     minis would stop it from remediating a failed ber1 mini.
   - The WAN, once Cogent assigns it: `management.edge.wan.address`,
     `gateway`, `address6` and `gateway6`, and the `bgp` block with the
     aggregates, `site_prefixes: ["95.130.119.32/28"]` and
     `egress.prefix: "95.130.119.32/28"`. `render` then writes larch's
     `bird.conf` and the first edge's static WAN.
   - `contracted_power`: 3000 W from 2026-11-09, 5000 W from 2027-05-09 and
     6000 W from 2027-08-09, and `power_budget: {chain_amps: 11.5,
     other_watts: 600}`. NTT caps the rack at 6 kW and the dual-PSU gear
     draws about 0.6 kW, so the minis stop taking new runner VMs above 2.4 kW,
     4.4 kW and 5.4 kW at the three steps, or above 11.5 A on either chain.
2. **The range can be served from two sites.** Do this before larch's BGP
   session first comes up, or ber1's replies start landing at larch:
   - Create RIPE route objects and ROAs for AS218377 for 95.130.119.16/28
     and 95.130.119.32/28.
   - Get Cogent's written confirmation that they accept /28s from us tagged
     NO_EXPORT on both sessions.
   - Deploy ber1's `site_prefixes`.
   - Check Cogent's looking glass for `95.130.119.16/28` behind AS218377.
3. **Merge in this order:**
   1. Edge ZTP (#14728), and the operator's fix that keeps ARP on the
      edges' ToR management port (#14748).
   2. The larch site (#14735).
   3. The chart's per-site fleet (#14752).
   4. The server's two-site routing (#14757).
   5. Power-aware admission (#14755).
   6. The per-site BGP announcement (#14759), once step 2's checks pass.
   7. The first edge's own WAN and the ToRs' WAN path from zero-touch
      provisioning (#14765), before the site's WAN address goes into the site
      file.

   Paste `infra/tailscale/acls.json` into the admin console after the site
   PR. Production's deploy and `omada-deployment.yml` then run a
   `rack-edge-larch` release with no node yet.
4. **The ToRs are factory-reset and sealed.** Reset the bench unit
   (`larch-tor-a`) and pack the second one (`larch-tor-b`). Each
   provisions itself through zero-touch provisioning from its edge.
5. **Goods-in tickets** are open in NTT's portal for every shipment, and
   every box is labelled with rack, U position and device name.
6. **Print** `cables/larch.md` and the elevation.

## On the day (hands-on), network first

7. **Rack** the ToRs, the edges, the storage node, the two ATSes and, last,
   the 0U PDUs beside NTT's rails. Then the mini trays, still empty of power.
8. **Cable data and management** per `cables/larch.md`, labelled at both
   ends:
   - The ISL: two DACs, ports 25 and 26.
   - Each edge's two 25G SFP28 legs, ports 29 and 30 on both ToRs.
   - The storage node's leg on `larch-tor-a` port 31.
   - Each ToR's management port and console to its own edge: `larch-tor-a`
     to `larch-edge-a` lan1 and USB, `larch-tor-b` to `larch-edge-b`.
   - Every BMC and power card to the opposite ToR. The render refuses
     anything else, so don't tidy them onto one ToR.
   - Cogent's cross-connect into `larch-tor-a` port 27, if NTT has
     patched it.
9. **Power the dual-PSU gear** straight from NTT's rails, PSU 1 to A and
   PSU 2 to B: the ToRs, then the edges, then the storage node.
10. **The first edge installs itself** once the WAN is lit:
    1. It boots the installer partition primeLine left on it, attests with
       its TPM to `rack-boot.tuist.dev`, and installs.
    2. On its first boot it takes the site's WAN untagged, since the factory
       ToR passes the carrier untagged, and joins the tailnet.
    3. Its rack-edge pod then gives that WAN up and serves the ToRs' DHCP and
       zero-touch provisioning. A ToR that missed provisioning at power-on is
       rebooted over its console.
    4. The ToR's bootstrap puts the WAN on its VLAN, and keepalived holds it
       from there. The edge is offline for those few minutes, and nothing in
       them needs the internet.

    ```
    kubectl $P -n tuist get rlh -l tuist.dev/site=$SITE -w
    kubectl $P -n omada get pods -o wide | grep rack-edge-$SITE
    kubectl $P -n tuist get rackswitch -l tuist.dev/site=$SITE
    ```

    The controller converges `larch-tor-b` first, then `larch-tor-a`.
    `larch-edge-b` and the storage node install next, through the first
    edge.
11. **Power last.** Connect each ATS's two inputs to its pair: chain A's and
    chain B's C19 sockets on different phases on both feeds. Then each PDU to
    its ATS. The cards take an address from the provisioning range and the
    operator adopts them:

    ```
    kubectl $P -n tuist get rackats,rackpdu -l tuist.dev/site=$SITE
    ```

12. **Plug the minis in only now**, once both ToRs report no drift and the
    PDUs are Ready: each mini into its outlet per the schedule. They enrol
    through ADE and the operator bootstraps them:

    ```
    kubectl $P -n tuist get rh,rasm | grep $SITE
    ```

### If Cogent is not live on the day

At Berlin 2 the port took four weeks from LOA to light. Without a WAN, the
first edge cannot reach `rack-boot.tuist.dev` and nothing in step 10
happens. Rack, cable and label everything (steps 7, 8 and 11), power the
dual-PSU gear to check its PSUs and link lights, then switch it off at the
rails or leave it idle. The site picks up at step 10 when the port lights.
No temporary uplink is planned: the edges' install expects the static WAN
that Cogent assigns.

## Before the site takes jobs (remote)

The design's acceptance gate is not automated yet. Every check below passes
before the site's pools are scaled up or any account's jobs route there.

13. **Network.**
    - Every `RackSwitch` of the site is Ready with no drift.
    - Both edges are Ready nodes, and keepalived has exactly one master.
    - `birdc -s /run/bird/bird.ctl show protocols` in the `bgp` container on
      the master shows `upstream4` and `upstream6` Established.
    - Cogent's looking glass shows `95.130.119.0/24` and `95.130.119.32/28`
      behind AS218377.
    - From a mini, `curl -4 https://ifconfig.me` answers with an address in
      95.130.119.32/28, and from a ber1 mini still in 95.130.119.16/28.
14. **Power.**
    - Both RackATS objects see both inputs good and are redundant.
    - Both RackPDU objects are Ready, with outlet readings.
    - `RackSite/larch` shows `status.contractedPowerWatts` 3000.
    - The rack's draw is under it.
15. **Failover, with no jobs running.**
    - Pull feed A, then feed B: no device resets, and each ATS transfers.
    - Reboot `larch-tor-b`: chain A's minis and the WAN stay up.
    - Fail over the edges (stop keepalived on the master): the BGP sessions
      move and egress keeps its address.
16. **Cache and runners.**
    - Production lists `larch-runners` in `TUIST_KURA_AVAILABLE_REGIONS`, and
      the platform chart runs a `kura-larch-runners` ingress controller
      beside `kura-ber1-runners`. Until both are in, the region is inert.
    - The `larch-runners` Kura instance on the storage node is Ready and
      replicating with ber1's.
    - `RackSite/larch`'s `PowerAdmission` condition is True, with readings on
      both chains.
    - The site's minis are Ready nodes in the larch fleet, and its pools
      hold warm runners.
    - The smoke workflow, pointed at the site's dispatch label, passes.
17. **Into service.** Scale the site's pools to their capacity. The server
    routes `runner_site` accounts to the site once its pools are up.
