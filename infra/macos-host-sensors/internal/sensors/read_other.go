//go:build !darwin

package sensors

import "errors"

// Read reports that there is nothing to read: the sensors are macOS
// frameworks. It exists so the package builds and tests on Linux CI.
func Read() (Readings, []error) {
	return Readings{}, []error{errors.New("hardware sensors are only read on macOS")}
}

func readProcessIO() ([]ProcessIO, error) {
	return nil, errors.New("process disk I/O is only read on macOS")
}
