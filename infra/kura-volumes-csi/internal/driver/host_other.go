//go:build !linux

package driver

import "errors"

var errUnsupportedOS = errors.New("kura-volumes-csi only runs on Linux")

type OSHost struct{}

func (OSHost) FSStats(string) (FSStats, error) { return FSStats{}, errUnsupportedOS }

func (OSHost) DeviceNumber(string) (string, error) { return "", errUnsupportedOS }
