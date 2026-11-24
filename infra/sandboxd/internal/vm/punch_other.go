//go:build !linux

package vm

// PunchZeros is a no-op off Linux, where memory images are never written.
func PunchZeros(string) (int64, error) { return 0, nil }
