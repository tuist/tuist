# macos-host-sensors

`tuist-host-sensors` samples a Mac's hardware once and writes the readings for
node_exporter's textfile collector: temperatures, fan speeds, system power and
thermal pressure. The CAPI provider's bootstrap installs it on every Mac mini
as a launchd job that runs every 30 seconds
([`macos-host-bootstrap/host_sensors.go`](../macos-host-bootstrap/host_sensors.go)),
and node_exporter reads `/var/lib/tuist-host-sensors`, so the readings ride the
existing `tuist-macos-node-exporter` scrape. No port, egress Service or tailnet
grant of its own.

## Why it exists

node_exporter cannot report temperatures on a healthy Apple silicon host. Its
darwin thermal collector asks macOS for the CPU power status first and returns
before reading any sensor when none is recorded, which is the normal state of a
machine that has never throttled (`pmset -g therm` says "No CPU power status
has been recorded"). Measured on 1.8.2, the fleet's version, and 1.12.1, the
latest: zero thermal series. The fix upstream is
[prometheus/node_exporter#3767](https://github.com/prometheus/node_exporter/pull/3767),
unmerged. The throttle ratios that collector also reports never exist on Apple
silicon at all.

node_exporter also has no fan or power reading on macOS, which is what the rack
needs most: a dead fan is the failure that turns into a fleet event in a flush
stack.

## How

The sensors are macOS frameworks called through
[purego](https://github.com/ebitengine/purego), not cgo, so the binary
cross-builds from Linux with `CGO_ENABLED=0` in the operator image like every
other host binary. That is the whole reason this is not a patched node_exporter:
node_exporter's Apple silicon collector needs cgo and the Apple SDK.

- **Temperatures**: IOKit's HID event system, the services under usage page
  `0xff00`, usage 5. The same calls node_exporter's collector makes.
- **Fans and power**: the AppleSMC user client (`FNum`, `F<n>Ac`, `F<n>Tg`,
  `F<n>Mx`, `PSTR`). Apple silicon reports these as little-endian floats.
- **Thermal pressure**: the `com.apple.system.thermalpressurelevel`
  notification state, Apple's own summary of whether the machine is being held
  back.

None of it needs root. It samples once and exits, so a crash costs one sample
and never leaves a wedged daemon; the file is replaced in one rename, so
node_exporter never reads it half written.

## Metrics

| Metric | Labels | Meaning |
| --- | --- | --- |
| `macos_sensor_temperature_celsius` | `sensor` | a HID sensor, hottest reading among the services that share its name |
| `macos_fan_speed_rpm` | `fan` | measured speed |
| `macos_fan_target_rpm` | `fan` | speed the SMC is asking for |
| `macos_fan_max_rpm` | `fan` | rated maximum |
| `macos_system_power_watts` | | total system power |
| `macos_thermal_pressure_level` | | 0 nominal, 1 moderate, 2 heavy, 3 trapping, 4 sleeping |

node_exporter adds `node_textfile_mtime_seconds`, which is how old the sample
is. Alert on its age rather than on missing series.

Things to know before querying them:

- **Sensor names differ by chip.** Apple silicon lists each die sensor three
  times (`PMU tdie1` and so on), a few tenths of a degree apart, and the hottest
  is kept so a name is one stable series across reboots. The set of names varies
  between chip generations, so alert on `max by (instance)` over
  `sensor=~"PMU tdie.*"` rather than on one name.
- **A fan well below its target is failing**; a target above zero with the
  speed at zero is a dead fan. Minis have one fan.
- **A key the model does not have is simply absent.** A fanless Mac reports no
  fans, and a key the SMC does not know is skipped.

Verified 2026-09-23 on an M3 Pro: 21 sensor names from 46 services, two fans,
power and thermal pressure, served through node_exporter 1.8.2's textfile
collector with no scrape error.

## Development

```
go test ./...                                   # portable: decoding and formatting
GOOS=darwin GOARCH=arm64 go vet ./...           # the darwin reader
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build ./cmd/tuist-host-sensors
./tuist-host-sensors --out /tmp/host_sensors.prom   # on a Mac
```

The CI job in `.github/workflows/capi-provider-scaleway-applesilicon-image.yml`
runs the same, because a Linux test pass never compiles the darwin files.
