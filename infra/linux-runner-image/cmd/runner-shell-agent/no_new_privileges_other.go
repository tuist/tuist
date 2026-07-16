//go:build !linux

package main

func enableNoNewPrivileges() error {
	return nil
}
