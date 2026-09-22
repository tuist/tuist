package cachevolumes

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type memoryBackend struct {
	parents                   map[string]string
	attached, sealed, deleted int
	failSeal                  bool
}

func (b *memoryBackend) Attach(slot Slot, path string) error {
	b.attached++
	if slot.ParentID != "" {
		return os.CopyFS(path, os.DirFS(b.parents[slot.ParentID]))
	}
	return nil
}
func (*memoryBackend) Measure(Slot, string) (int64, int64, error) { return 100, 1000, nil }
func (b *memoryBackend) Seal(slot Slot, path string) error {
	if b.failSeal {
		return errors.New("storage unavailable")
	}
	b.sealed++
	b.parents[slot.ID] = path
	return nil
}
func (b *memoryBackend) Delete(_ Slot, _ string) error { b.deleted++; return nil }
func identity(id string) Identity {
	return Identity{ID: id, Account: 1, Scope: strings.Repeat("a", 64), CanPublish: true}
}

const first = "00000000-0000-0000-0000-000000000001"
const second = "00000000-0000-0000-0000-000000000002"
const third = "00000000-0000-0000-0000-000000000003"

func newStore(t *testing.T) (*Store, *memoryBackend) {
	t.Helper()
	b := &memoryBackend{parents: map[string]string{}}
	s, err := Open(t.TempDir(), b)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s, b
}
func TestParallelJobsCloneWarmParentAndCannotMutateEachOther(t *testing.T) {
	s, b := newStore(t)
	if warm, err := s.Acquire(identity(first), "p1", "u1"); err != nil || warm {
		t.Fatal(warm, err)
	}
	slots, _ := s.slots()
	path := s.activePath(slots[0])
	os.WriteFile(filepath.Join(path, "cache"), []byte("trusted"), 0600)
	done := func(string, string) (bool, error) { return true, nil }
	if err := s.Reconcile(done, func(Slot, bool) (string, error) { return "seal", nil }); err != nil {
		t.Fatal(err)
	}
	for i, id := range []string{second, third} {
		x := identity(id)
		x.ParentID = first
		uid := []string{"u2", "u3"}[i]
		if warm, err := s.Acquire(x, "p"+uid, uid); err != nil || !warm {
			t.Fatal(warm, err)
		}
	}
	slots, _ = s.slots()
	paths := map[string]string{}
	for _, slot := range slots {
		paths[slot.ID] = s.activePath(slot)
	}
	os.WriteFile(filepath.Join(paths[second], "cache"), []byte("PR changes"), 0600)
	for _, id := range []string{first, third} {
		data, _ := os.ReadFile(filepath.Join(paths[id], "cache"))
		if string(data) != "trusted" {
			t.Fatal("shared writable cache")
		}
	}
	if b.attached != 3 {
		t.Fatal("missing clone")
	}
}
func TestTeardownFenceOverridesRemoteDeleteAndAPIErrors(t *testing.T) {
	s, b := newStore(t)
	s.Acquire(identity(first), "p", "u")
	if err := s.Reconcile(func(string, string) (bool, error) { return false, nil }, func(Slot, bool) (string, error) { return "delete", nil }); err != nil {
		t.Fatal(err)
	}
	if b.deleted != 0 {
		t.Fatal("deleted live writer")
	}
	if err := s.Reconcile(func(string, string) (bool, error) { return false, errors.New("API down") }, func(Slot, bool) (string, error) { t.Fatal("reported absence"); return "delete", nil }); err == nil {
		t.Fatal("ignored API error")
	}
	if b.deleted != 0 {
		t.Fatal("deleted on API failure")
	}
}
func TestRestartAndRetryPreserveLeaseAndWarmResult(t *testing.T) {
	s, b := newStore(t)
	s.Acquire(identity(first), "p", "u")
	reopened, err := Open(s.path, b)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	if warm, err := reopened.Acquire(identity(first), "p", "u"); err != nil || warm {
		t.Fatal("changed cold result on retry", warm, err)
	}
	if b.attached != 1 {
		t.Fatal("attached twice")
	}
	done := func(string, string) (bool, error) { return true, nil }
	b.failSeal = true
	if err := reopened.Reconcile(done, func(Slot, bool) (string, error) { return "seal", nil }); err == nil {
		t.Fatal("ignored failed snapshot")
	}
	slots, _ := reopened.slots()
	if slots[0].State != "active" {
		t.Fatal("published failed snapshot")
	}
	b.failSeal = false
	if err := reopened.Reconcile(done, func(Slot, bool) (string, error) { return "seal", nil }); err != nil {
		t.Fatal(err)
	}
}
func TestDiscardedPRCannotBeSealedAndDeletionRequiresAcknowledgement(t *testing.T) {
	s, b := newStore(t)
	x := identity(first)
	x.CanPublish = false
	s.Acquire(x, "p", "u")
	done := func(string, string) (bool, error) { return true, nil }
	if err := s.Reconcile(done, func(Slot, bool) (string, error) { return "seal", nil }); err == nil {
		t.Fatal("sealed PR")
	}
	if b.sealed != 0 {
		t.Fatal("published PR")
	}
	s.Reconcile(done, func(Slot, bool) (string, error) { return "delete", nil })
	slots, _ := s.slots()
	if len(slots) != 1 || slots[0].State != "deleted" {
		t.Fatal("forgot before acknowledgement")
	}
	s.Reconcile(done, func(slot Slot, _ bool) (string, error) {
		if slot.State != "deleted" {
			t.Fatal("wrong report")
		}
		return "forget", nil
	})
	slots, _ = s.slots()
	if len(slots) != 0 {
		t.Fatal("did not finish deletion")
	}
}
func TestRejectsTraversalAndCrossPodRetry(t *testing.T) {
	s, _ := newStore(t)
	x := identity(first)
	x.ParentID = "../../escape"
	if _, err := s.Acquire(x, "p", "u"); err == nil {
		t.Fatal("accepted unsafe parent")
	}
	s.Acquire(identity(first), "p", "u")
	if _, err := s.Acquire(identity(first), "other", "other"); err == nil {
		t.Fatal("accepted foreign retry")
	}
}

type blockingBackend struct{ sealing, resume chan struct{} }

func (*blockingBackend) Attach(Slot, string) error                  { return nil }
func (*blockingBackend) Measure(Slot, string) (int64, int64, error) { return 0, 100, nil }
func (b *blockingBackend) Seal(Slot, string) error                  { close(b.sealing); <-b.resume; return nil }
func (*blockingBackend) Delete(Slot, string) error                  { return nil }

func TestSlowSealDoesNotBlockAnotherLease(t *testing.T) {
	b := &blockingBackend{sealing: make(chan struct{}), resume: make(chan struct{})}
	s, err := Open(t.TempDir(), b)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if _, err := s.Acquire(identity(first), "p1", "u1"); err != nil {
		t.Fatal(err)
	}
	complete := make(chan error, 1)
	go func() {
		complete <- s.Reconcile(func(string, string) (bool, error) { return true, nil }, func(Slot, bool) (string, error) { return "seal", nil })
	}()
	<-b.sealing
	attached := make(chan error, 1)
	go func() { _, err := s.Acquire(identity(second), "p2", "u2"); attached <- err }()
	select {
	case err := <-attached:
		if err != nil {
			t.Error(err)
		}
	case <-time.After(2 * time.Second):
		t.Error("flatten blocked unrelated attachment")
	}
	close(b.resume)
	if err := <-complete; err != nil {
		t.Fatal(err)
	}
}
func TestScratchCleanupWaitsForMountsAndNeverFollowsSymlinks(t *testing.T) {
	s, _ := newStore(t)
	if _, err := s.Acquire(identity(first), "p", "u"); err != nil {
		t.Fatal(err)
	}
	outside := t.TempDir()
	os.WriteFile(filepath.Join(outside, "keep"), []byte("safe"), 0600)
	if err := os.Symlink(outside, filepath.Join(s.path, "pods", "orphan")); err != nil {
		t.Fatal(err)
	}
	if err := s.CleanPods(func(string) (bool, error) { return true, nil }); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(s.path, "pods", "u")); err != nil {
		t.Fatal("removed mounted pod", err)
	}
	if _, err := os.Stat(filepath.Join(outside, "keep")); err != nil {
		t.Fatal("followed scratch symlink", err)
	}
	if _, err := os.Lstat(filepath.Join(s.path, "pods", "orphan")); !os.IsNotExist(err) {
		t.Fatal("orphan retained")
	}
}

func TestRejectedAdmissionSurvivesRestartAndReportFailure(t *testing.T) {
	for _, perPod := range []bool{false, true} {
		t.Run(fmt.Sprintf("per-pod-%t", perPod), func(t *testing.T) {
			s, b := newStore(t)
			count := 1
			s.MaxSlots = 1
			if perPod {
				count = 8
				s.MaxSlots = 100
			}
			for i := 1; i <= count; i++ {
				x := identity(fmt.Sprintf("00000000-0000-0000-0000-%012d", i))
				x.Scope = fmt.Sprintf("%064x", i)
				if _, err := s.Acquire(x, "p", "u"); err != nil {
					t.Fatal(err)
				}
			}
			rejected := identity("00000000-0000-0000-0000-000000000099")
			rejected.ParentID = third
			if _, err := s.Acquire(rejected, "p", "u"); err == nil {
				t.Fatal("accepted over capacity")
			}
			reopened, err := Open(s.path, b)
			if err != nil {
				t.Fatal(err)
			}
			defer reopened.Close()
			reopened.MaxSlots = 100
			if _, err := reopened.Acquire(rejected, "p", "u"); err == nil {
				t.Fatal("retry attached a rejected lease")
			}
			seen := false
			report := func(slot Slot, _ bool) (string, error) {
				if slot.ID != rejected.ID {
					return "hold", nil
				}
				seen = true
				if slot.State != "deleted" {
					t.Fatalf("rejected lease state = %s", slot.State)
				}
				return "", errors.New("server unavailable")
			}
			gone := func(string, string) (bool, error) { return true, nil }
			if err := reopened.Reconcile(gone, report); err == nil || !seen {
				t.Fatal("rejected allocation was not durably reported")
			}
			if err := reopened.Reconcile(gone, func(slot Slot, _ bool) (string, error) {
				if slot.ID == rejected.ID {
					return "forget", nil
				}
				return "hold", nil
			}); err != nil {
				t.Fatal(err)
			}
			slots, err := reopened.slots()
			if err != nil || len(slots) != count {
				t.Fatalf("rejected journal retained: %v, %v", slots, err)
			}
			if b.attached != count || b.deleted != 0 {
				t.Fatal("storage created or deleted for rejected allocation")
			}
		})
	}
}
