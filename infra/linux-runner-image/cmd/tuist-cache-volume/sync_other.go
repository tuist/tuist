//go:build !darwin

package main

import "os"

func fullSync(f *os.File) error { return f.Sync() }
