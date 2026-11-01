//go:build linux

package driver

import (
	"net"
	"os"
	"path/filepath"
	"testing"
)

func TestAllocatorChecksKernelPeer(t *testing.T) {
	path := filepath.Join(t.TempDir(), "peer.sock")
	listener, err := net.Listen("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	client, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	peer, err := listener.Accept()
	if err != nil {
		t.Fatal(err)
	}
	defer peer.Close()
	if allocatorRootPeer(peer) != (os.Geteuid() == 0) {
		t.Fatal("allocator authorization differs from kernel UID")
	}
	a, b := net.Pipe()
	defer a.Close()
	defer b.Close()
	if allocatorRootPeer(a) {
		t.Fatal("accepted a connection without Unix credentials")
	}
}
