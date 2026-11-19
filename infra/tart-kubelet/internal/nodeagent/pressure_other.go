//go:build !darwin

package nodeagent

import (
	"context"
	"errors"
)

func HostMemoryPressure(context.Context) (bool, string, error) {
	return false, "", errors.New("macOS memory pressure is unavailable on this platform")
}

func HostPIDPressure(context.Context) (bool, string, error) {
	return false, "", errors.New("macOS process pressure is unavailable on this platform")
}
