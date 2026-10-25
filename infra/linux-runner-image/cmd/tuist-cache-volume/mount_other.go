//go:build !linux

package main

import "errors"

func bindDirectory(socket, source, target string) error {
	return errors.New("cache volume bind mounts require Linux")
}
func serveMounts(socket, root string, docker func(dockerMessage) error) error {
	return errors.New("cache volume bind mounts require Linux")
}
func sendDocker(socket string, message dockerMessage) error {
	return errors.New("the Docker cache requires Linux")
}
func runDind(args []string) error { return errors.New("the Docker cache requires Linux") }
func mountWorker(bool) error      { return errors.New("cache volume bind mounts require Linux") }
func bindCheckout(socket, source, workspace, target string) error {
	return errors.New("cached checkouts require Linux")
}
