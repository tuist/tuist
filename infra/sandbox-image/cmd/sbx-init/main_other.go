//go:build !linux

package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "sbx-init is the Linux guest's PID 1 and only runs there")
	os.Exit(1)
}
