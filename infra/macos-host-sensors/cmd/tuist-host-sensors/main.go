// Command tuist-host-sensors samples a Mac's hardware sensors once and writes
// them for node_exporter's textfile collector: temperatures, fan speeds,
// system power, thermal pressure and disk I/O by process group. launchd runs
// it on an interval, so a crash costs one sample rather than a daemon.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/tuist/tuist/infra/macos-host-sensors/internal/sensors"
)

func main() {
	out := flag.String("out", "/var/lib/tuist-host-sensors/host_sensors.prom", "File node_exporter's textfile collector reads")
	// The textfile collector reads only *.prom, so the state can sit beside
	// the readings.
	diskIOState := flag.String("disk-io-state", "/var/lib/tuist-host-sensors/disk_io_state.json", "File that carries the process disk I/O totals from one run to the next")
	flag.Parse()

	readings, errs := sensors.Read()
	for _, err := range errs {
		fmt.Fprintln(os.Stderr, err)
	}
	diskIO, err := sensors.AccountDiskIO(*diskIOState)
	if err != nil {
		fmt.Fprintln(os.Stderr, "process disk I/O:", err)
	}
	readings.DiskIO = diskIO
	if err := sensors.WriteFile(*out, []byte(sensors.Format(readings)), 0o644); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
