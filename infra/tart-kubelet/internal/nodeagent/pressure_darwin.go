package nodeagent

import (
	"context"
	"fmt"

	"golang.org/x/sys/unix"
)

func HostMemoryPressure(ctx context.Context) (bool, string, error) {
	if err := ctx.Err(); err != nil {
		return false, "", err
	}
	// XNU exports dispatch pressure flags: NORMAL=1, WARN=2, CRITICAL=4.
	// See bsd/kern/kern_memorystatus_notify.c in apple-oss-distributions/xnu.
	level, err := unix.SysctlUint32("kern.memorystatus_vm_pressure_level")
	if err != nil {
		return false, "", fmt.Errorf("read memory pressure: %w", err)
	}
	return memoryPressure(level)
}

func HostPIDPressure(ctx context.Context) (bool, string, error) {
	if err := ctx.Err(); err != nil {
		return false, "", err
	}
	limit, err := unix.SysctlUint32("kern.maxproc")
	if err != nil {
		return false, "", fmt.Errorf("read process limit: %w", err)
	}
	processes, err := unix.SysctlKinfoProcSlice("kern.proc.all")
	if err != nil {
		return false, "", fmt.Errorf("read process count: %w", err)
	}
	return pidPressure(uint64(len(processes)), uint64(limit))
}
