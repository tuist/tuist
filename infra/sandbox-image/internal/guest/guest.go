// Package guest is the Linux-specific half of the agent: the clock, hostname,
// resolver, neighbour cache and workspace disk. System implements
// agent.System; on other platforms every operation reports ErrUnsupported so
// the agent still compiles and its handler tests run there.
package guest

import "errors"

const (
	// WorkspaceDevice is the second virtio-blk drive sandboxd attaches; it is
	// left unmounted at the template snapshot and mounted by configure.
	WorkspaceDevice = "/dev/vdb"
	WorkspaceMount  = "/workspace"
	MemoryMount     = "/mnt/memory"
	Interface       = "eth0"
)

var ErrUnsupported = errors.New("only supported on linux")
