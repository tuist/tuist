//go:build !linux && !darwin

package archive

import "os"

func nextData(_ *os.File, off, _ int64) (int64, error) { return off, nil }

func nextHole(_ *os.File, _, size int64) (int64, error) { return size, nil }
