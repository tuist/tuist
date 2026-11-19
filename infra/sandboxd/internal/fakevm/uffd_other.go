//go:build !linux

package fakevm

import "errors"

// UserfaultfdSupported is false outside Linux.
func UserfaultfdSupported() bool { return false }

func guestMemory(sock string, size int64) ([]byte, func(), error) {
	return nil, nil, errors.New("userfaultfd needs linux")
}
