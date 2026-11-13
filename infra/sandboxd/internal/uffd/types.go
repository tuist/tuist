// Package uffd serves a restored Firecracker guest's memory through
// userfaultfd, so the VM resumes before its memory image has arrived.
//
// Firecracker, given a Uffd memory backend, maps the guest's memory
// anonymously, registers it with a userfaultfd and hands that descriptor
// with the region layout to the socket Listen opened. From then on every
// first touch of a guest page, by the guest or by KVM on its behalf, stops
// the touching thread until this package installs the page.
//
// Pages are installed a chunk at a time (the Source's unit, 2 MiB for an
// archive): a fault fetches the chunk it falls in ahead of everything else,
// and a background fill fetches the rest in order, so the image is complete
// on the node after a bounded time and no longer depends on the store.
package uffd

import (
	"context"
	"errors"
)

// ErrProcessGone means the process whose memory this served has exited.
var ErrProcessGone = errors.New("the guest's process is gone")

// Region is one guest memory region as Firecracker describes it: Size bytes
// mapped at Base in Firecracker, backed by the image at Offset.
type Region struct {
	Base     uint64 `json:"base_host_virt_addr"`
	Size     uint64 `json:"size"`
	Offset   uint64 `json:"offset"`
	PageSize uint64 `json:"page_size"`
}

// Source is a guest memory image, read a chunk at a time.
type Source interface {
	Size() int64
	ChunkSize() int64
	// Chunk answers chunk i, or nil when it is all zeros. Only the last
	// chunk may be shorter than ChunkSize.
	Chunk(ctx context.Context, i int) ([]byte, error)
}

// Options tunes a Serve.
type Options struct {
	// FaultWorkers fetch the chunks the guest is waiting on; FillWorkers
	// fetch the rest in the background. Zero FillWorkers leaves untouched
	// chunks unfetched.
	FaultWorkers int
	FillWorkers  int
	// OnLoaded runs once every chunk is installed.
	OnLoaded func(Stats)
}

// Stats counts what a Serve installed and why.
type Stats struct {
	Chunks  int   `json:"chunks"`
	Faulted int   `json:"faulted"`
	Filled  int   `json:"filled"`
	Zero    int   `json:"zero"`
	Faults  int64 `json:"faults"`
	// Bytes is the guest memory installed from non-zero chunks.
	Bytes int64 `json:"bytes"`
}
