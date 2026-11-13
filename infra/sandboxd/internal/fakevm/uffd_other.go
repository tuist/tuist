//go:build !linux

package fakevm

import "errors"

func guestMemory(sock string, size int64) ([]byte, func(), error) {
	return nil, nil, errors.New("userfaultfd needs linux")
}
