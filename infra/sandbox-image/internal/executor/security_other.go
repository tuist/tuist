//go:build !linux

package executor

import "fmt"

func prepareExecution() error { return fmt.Errorf("remote execution requires Linux") }
