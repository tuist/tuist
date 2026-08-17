package hostwork

import (
	"context"
	"errors"
	"testing"
)

type vmStub struct {
	running bool
	err     error
}

func (s *vmStub) AnyRunning(_ context.Context) (bool, error) { return s.running, s.err }

func TestProbe_RunningVMIsBusy(t *testing.T) {
	busy, detail, err := Probe(context.Background(), &vmStub{running: true})
	if err != nil {
		t.Fatalf("probe: %v", err)
	}
	if !busy {
		t.Fatal("a running Tart VM must read as busy")
	}
	if detail == "" {
		t.Fatal("expected a detail for the Node condition message")
	}
}

func TestProbe_VMErrorIsNotIdle(t *testing.T) {
	// The caller leaves the previous verdict standing on an error. A
	// swallowed error here would publish "idle" off a probe that never
	// ran, which is what authorises a reboot.
	if _, _, err := Probe(context.Background(), &vmStub{err: errors.New("tart daemon down")}); err == nil {
		t.Fatal("expected the VM probe error to surface, not be folded into a not-busy verdict")
	}
}

func TestProbe_NoVMFallsThroughToTheActionsJobCheck(t *testing.T) {
	// The window this covers: during `tart push` the bake's VM has
	// already been stopped, so a VM-only probe reports idle while the
	// job is still running. No Runner.Worker exists in this test
	// process, so the expected answer is a clean not-busy — the point
	// is that the second signal is consulted at all.
	busy, detail, err := Probe(context.Background(), &vmStub{running: false})
	if err != nil {
		t.Fatalf("probe: %v", err)
	}
	if busy {
		t.Fatal("no VM and no Actions worker must read as idle")
	}
	if detail == "" {
		t.Fatal("expected a detail even for the idle verdict")
	}
}

func TestProcessMatches_NoMatchIsAnAnswerNotAnError(t *testing.T) {
	matched, err := processMatches(context.Background(), `tuist-hostwork-no-such-process-xyzzy`)
	if err != nil {
		t.Fatalf("pgrep exit 1 means no match, not failure: %v", err)
	}
	if matched {
		t.Fatal("did not expect a match for a nonsense pattern")
	}
}
