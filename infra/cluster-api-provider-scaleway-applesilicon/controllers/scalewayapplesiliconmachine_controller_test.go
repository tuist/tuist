package controllers

import (
	"errors"
	"testing"

	"github.com/go-logr/logr"
	"k8s.io/client-go/tools/record"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
)

// recordUpdateFailure is the safety primitive that bounds the
// drift-loop's retry behaviour. Tests document the contract:
// counter increments per call; only crosses into the terminal
// FailureReason state once the cap is reached; cap=0 disables
// terminal transition entirely (escape hatch documented on the
// flag).

// fakeRecorder is the FakeRecorder from client-go but its full
// import path is a mouthful and tests don't read the events back —
// just need a recorder that doesn't panic on Eventf.
func fakeRecorder() record.EventRecorder {
	return record.NewFakeRecorder(32)
}

func TestRecordUpdateFailure_IncrementsAttempts(t *testing.T) {
	machine := &infrav1.ScalewayAppleSiliconMachine{}
	recordUpdateFailure(machine, errors.New("boom"), 5, logr.Discard(), fakeRecorder())
	if machine.Status.TartKubeletUpdateAttempts != 1 {
		t.Fatalf("attempts: got %d, want 1", machine.Status.TartKubeletUpdateAttempts)
	}
	if machine.Status.FailureReason != nil {
		t.Fatalf("did not expect terminal failure on attempt 1; got %q", *machine.Status.FailureReason)
	}
}

func TestRecordUpdateFailure_TransitionsToFailedAtCap(t *testing.T) {
	machine := &infrav1.ScalewayAppleSiliconMachine{}
	for i := 0; i < 5; i++ {
		recordUpdateFailure(machine, errors.New("boom"), 5, logr.Discard(), fakeRecorder())
	}
	if machine.Status.TartKubeletUpdateAttempts != 5 {
		t.Fatalf("attempts: got %d, want 5", machine.Status.TartKubeletUpdateAttempts)
	}
	if machine.Status.FailureReason == nil {
		t.Fatal("expected FailureReason to be set after 5 attempts")
	}
	if got, want := *machine.Status.FailureReason, "TartKubeletUpdateExceededRetries"; got != want {
		t.Fatalf("FailureReason: got %q, want %q", got, want)
	}
	if machine.Status.Phase != "Failed" {
		t.Fatalf("Phase: got %q, want Failed", machine.Status.Phase)
	}
	if machine.Status.FailureMessage == nil {
		t.Fatal("expected FailureMessage to be set")
	}
}

func TestRecordUpdateFailure_DoesNotTransitionBeforeCap(t *testing.T) {
	machine := &infrav1.ScalewayAppleSiliconMachine{}
	for i := 0; i < 4; i++ {
		recordUpdateFailure(machine, errors.New("boom"), 5, logr.Discard(), fakeRecorder())
	}
	if machine.Status.FailureReason != nil {
		t.Fatalf("did not expect terminal failure on attempt 4; got %q", *machine.Status.FailureReason)
	}
}

func TestRecordUpdateFailure_DisabledCap(t *testing.T) {
	machine := &infrav1.ScalewayAppleSiliconMachine{}
	for i := 0; i < 100; i++ {
		recordUpdateFailure(machine, errors.New("boom"), 0, logr.Discard(), fakeRecorder())
	}
	if machine.Status.TartKubeletUpdateAttempts != 100 {
		t.Fatalf("attempts: got %d, want 100", machine.Status.TartKubeletUpdateAttempts)
	}
	if machine.Status.FailureReason != nil {
		t.Fatalf("cap=0 must never trigger terminal failure; got %q", *machine.Status.FailureReason)
	}
}
