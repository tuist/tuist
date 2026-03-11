# Evidence: mac host inventory

Source: SSH discovery on `m1@51.159.120.232`

## Identity and OS

```text
HOSTNAME 16356b55-76c6-4b86-b792-02a11f334a5c
USER m1
ID uid=501(m1) gid=20(staff) groups=20(staff),12(everyone),61(localaccounts),79(_appserverusr),80(admin),81(_appserveradm),33(_appstore),98(_lpadmin),100(_lpoperator),204(_developer),250(_analyticsusers),395(com.apple.access_ftp),398(com.apple.access_screensharing),399(com.apple.access_ssh),400(com.apple.access_remote_ae),701(com.apple.sharepoint.group.1)
SUDO no
ProductName: macOS
ProductVersion: 26.0
BuildVersion: 25A354
```

## Hardware

```text
CPU Apple M1
CORES 8
LOGICAL 8
MEM_BYTES 8589934592
```

## Disk

```text
/dev/disk3s1s1   228Gi    11Gi   194Gi
/dev/disk3s5     228Gi    15Gi   194Gi
```

## Xcode and SDKs

```text
XCODE_SELECT /Applications/Xcode.app/Contents/Developer
Xcode 26.0
Build version 17A321
```

```text
.xcode-version in repo: 26.2
```

```text
iOS SDKs: iOS 26.0
iOS Simulator SDKs: Simulator - iOS 26.0
macOS SDKs: macOS 26.0
tvOS SDKs: tvOS 26.0
visionOS SDKs: visionOS 26.0
watchOS SDKs: watchOS 26.0
```

## Simulator state

```text
RUNTIMES
== Runtimes ==

DEVICES
== Devices ==
```

Device types exist, but no runtimes/devices are currently listed by `simctl`.

## Tooling state

```text
NIX missing
DARWIN_REBUILD missing
MISE missing
TUIST missing
```

## Rosetta

```text
package-id: com.apple.pkg.RosettaUpdateAuto
ARCH_X64
x86_64
```

## Naming and VLANs

```text
LOCALHOSTNAME 16356b55-76c6-4b86-b792-02a11f334a5c
HOSTNAME_PREF 16356b55-76c6-4b86-b792-02a11f334a5c
COMPUTERNAME 16356b55-76c6-4b86-b792-02a11f334a5c
```

```text
There are no VLANs currently configured on this system.
```

## Launchd limits

```text
maxfiles    256            unlimited
maxproc     1333           2000
```

## Interpretation

- This is a clean-ish host, not yet prepared for Tuist workflows.
- It is missing the entire Nix bootstrap path.
- It does not yet match the repo's Xcode assumption.
- It does not yet have the Private Network VLAN required to reach the cache privately.
