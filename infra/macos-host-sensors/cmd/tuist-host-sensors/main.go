// Command tuist-host-sensors samples a Mac's hardware sensors once and writes
// them for node_exporter's textfile collector: temperatures, fan speeds,
// system power and thermal pressure. launchd runs it on an interval, so a
// crash costs one sample rather than a daemon.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tuist/tuist/infra/macos-host-sensors/internal/sensors"
)

func main() {
	out := flag.String("out", "/var/lib/tuist-host-sensors/host_sensors.prom", "File node_exporter's textfile collector reads")
	flag.Parse()

	readings, errs := sensors.Read()
	for _, err := range errs {
		fmt.Fprintln(os.Stderr, err)
	}
	if err := write(*out, sensors.Format(readings)); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// write replaces path in one rename, so the collector never reads a file
// half written.
func write(path, content string) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".host_sensors-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString(content); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}
