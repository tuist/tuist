package podagent

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
)

const drainTestUID = "b1abef64-43be-40c8-b78d-49d18c261fed"

func TestDrainSurvivesReconcileRestartAndRequiresMatchingAcknowledgement(t *testing.T) {
	dir := t.TempDir()
	for i := 0; i < 2; i++ {
		waiting, err := requestGuestDrain(dir, drainTestUID)
		if err != nil || !waiting {
			t.Fatalf("pending drain: %v %v", waiting, err)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "drain-complete"), []byte("another-pod\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if waiting, err := requestGuestDrain(dir, drainTestUID); err != nil || !waiting {
		t.Fatalf("stale acknowledgement: %v %v", waiting, err)
	}
	if err := os.WriteFile(filepath.Join(dir, "drain-complete"), []byte(drainTestUID+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if waiting, err := requestGuestDrain(dir, drainTestUID); err != nil || waiting {
		t.Fatalf("completed drain: %v %v", waiting, err)
	}
}

func TestDrainRejectsSymlinksAndFIFOs(t *testing.T) {
	for _, name := range []string{"drain-request", "drain-complete"} {
		for _, kind := range []string{"symlink", "fifo"} {
			t.Run(name+"/"+kind, func(t *testing.T) {
				dir := t.TempDir()
				outside := filepath.Join(t.TempDir(), "outside")
				want := drainTestUID + "\n"
				if err := os.WriteFile(outside, []byte(want), 0600); err != nil {
					t.Fatal(err)
				}
				path := filepath.Join(dir, name)
				var err error
				if kind == "symlink" {
					err = os.Symlink(outside, path)
				} else {
					err = syscall.Mkfifo(path, 0600)
				}
				if err != nil {
					t.Fatal(err)
				}
				waiting, _ := requestGuestDrain(dir, drainTestUID)
				if !waiting {
					t.Fatal("unsafe guest file accepted as acknowledgement")
				}
				data, err := os.ReadFile(outside)
				if err != nil || string(data) != want {
					t.Fatal("modified a path outside the VM share")
				}
			})
		}
	}
}
