//go:build !linux

package main

import "errors"

func bindDirectory(socket, source, target string) error {
	return errors.New("cache volume bind mounts require Linux")
}
func serveMounts(socket, root string) error {
	return errors.New("cache volume bind mounts require Linux")
}
func mountWorker() error { return errors.New("cache volume bind mounts require Linux") }
