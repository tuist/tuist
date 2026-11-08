package macosandbox

import (
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
	"testing"
)

func TestDiskAdmissionIncludesEvictedDisksAndCheckpointReplacement(t *testing.T) {
	const gib = uint64(1024 * 1024 * 1024)
	vms := []tart.VM{{Name: "sbx-a", Disk: 100, Memory: 24576}, {Name: "sbx-b", Disk: 100, Memory: 24576}}
	if err := diskRoom(vms, 1024*gib, 100*gib, 24576); err != nil {
		t.Fatal(err)
	}
	if diskRoom(vms, 512*gib, 100*gib, 24576) == nil {
		t.Fatal("writable roots exceeded half-disk ceiling")
	}
	if diskRoom(vms, 1024*gib, 67*gib, 24576) == nil {
		t.Fatal("checkpoint replacement spent CI disk reserve")
	}
	vms[0].Disk = 0
	if diskRoom(vms, 1024*gib, 100*gib, 24576) == nil {
		t.Fatal("unknown logical disk admitted")
	}
}
