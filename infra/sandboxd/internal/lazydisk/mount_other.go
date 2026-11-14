//go:build !linux

package lazydisk

import "errors"

func Supported() bool { return false }

type Mount struct{}

func MountImage(string, *Image, uint32, uint32) (*Mount, error) {
	return nil, errors.ErrUnsupported
}

func (m *Mount) Detach() error { return nil }

func (m *Mount) Done() <-chan struct{} {
	done := make(chan struct{})
	close(done)
	return done
}

func Unmount(string) {}
