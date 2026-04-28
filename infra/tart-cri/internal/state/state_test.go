package state

import (
	"path/filepath"
	"testing"

	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"
)

func TestPersistAcrossRestart(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "state.json")

	s, err := New(path)
	if err != nil {
		t.Fatal(err)
	}

	if err := s.PutSandbox(&Sandbox{
		ID:    "sandbox-1",
		State: runtimeapi.PodSandboxState_SANDBOX_READY,
	}); err != nil {
		t.Fatal(err)
	}
	if err := s.PutContainer(&Container{
		ID:        "container-1",
		SandboxID: "sandbox-1",
		Image:     "ghcr.io/x:1",
		State:     runtimeapi.ContainerState_CONTAINER_RUNNING,
	}); err != nil {
		t.Fatal(err)
	}

	// Reopen.
	s2, err := New(path)
	if err != nil {
		t.Fatal(err)
	}
	if sb := s2.GetSandbox("sandbox-1"); sb == nil || sb.State != runtimeapi.PodSandboxState_SANDBOX_READY {
		t.Fatalf("sandbox not persisted: %+v", sb)
	}
	if c := s2.GetContainer("container-1"); c == nil || c.Image != "ghcr.io/x:1" {
		t.Fatalf("container not persisted: %+v", c)
	}
}

func TestDeleteSandboxRemovesContainers(t *testing.T) {
	s, _ := New(filepath.Join(t.TempDir(), "state.json"))
	_ = s.PutSandbox(&Sandbox{ID: "sb"})
	_ = s.PutContainer(&Container{ID: "c1", SandboxID: "sb"})
	_ = s.PutContainer(&Container{ID: "c2", SandboxID: "other"})

	if err := s.DeleteSandbox("sb"); err != nil {
		t.Fatal(err)
	}
	if c := s.GetContainer("c1"); c != nil {
		t.Fatalf("container c1 should have been removed with its sandbox")
	}
	if c := s.GetContainer("c2"); c == nil {
		t.Fatalf("container c2 (different sandbox) should remain")
	}
}

func TestListContainers_FiltersBySandbox(t *testing.T) {
	s, _ := New(filepath.Join(t.TempDir(), "state.json"))
	_ = s.PutContainer(&Container{ID: "c1", SandboxID: "a"})
	_ = s.PutContainer(&Container{ID: "c2", SandboxID: "a"})
	_ = s.PutContainer(&Container{ID: "c3", SandboxID: "b"})

	if got := len(s.ListContainers("")); got != 3 {
		t.Fatalf("ListContainers(\"\") returned %d, want 3", got)
	}
	if got := len(s.ListContainers("a")); got != 2 {
		t.Fatalf("ListContainers(\"a\") returned %d, want 2", got)
	}
}
