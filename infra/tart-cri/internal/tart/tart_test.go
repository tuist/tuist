package tart

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestPull(t *testing.T) {
	var seen []string
	r := &Runtime{
		Binary: "tart",
		Exec: func(_ context.Context, _ string, args ...string) ([]byte, error) {
			seen = args
			return nil, nil
		},
	}
	if err := r.Pull(context.Background(), "ghcr.io/x/y:1"); err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(seen, " "); got != "pull ghcr.io/x/y:1" {
		t.Fatalf("got args %q", got)
	}
}

func TestSetParameters_NoOpsWhenAllZero(t *testing.T) {
	r := &Runtime{
		Binary: "tart",
		Exec: func(_ context.Context, _ string, _ ...string) ([]byte, error) {
			t.Fatalf("Exec should not be called when all params are zero")
			return nil, nil
		},
	}
	if err := r.SetParameters(context.Background(), "vm", 0, 0); err != nil {
		t.Fatal(err)
	}
}

func TestGet_ParsesJSON(t *testing.T) {
	r := &Runtime{
		Binary: "tart",
		Exec: func(_ context.Context, _ string, args ...string) ([]byte, error) {
			if args[0] != "get" || args[1] != "vm-x" {
				return nil, errors.New("unexpected")
			}
			return []byte(`{"Source":"ghcr.io/x:1","State":"running","CPU":4,"Memory":8192}`), nil
		},
	}
	vm, err := r.Get(context.Background(), "vm-x")
	if err != nil {
		t.Fatal(err)
	}
	if vm.State != "running" || vm.CPU != 4 {
		t.Fatalf("got %+v", vm)
	}
}

func TestList_ParsesArray(t *testing.T) {
	r := &Runtime{
		Binary: "tart",
		Exec: func(_ context.Context, _ string, _ ...string) ([]byte, error) {
			return []byte(`[{"Source":"a","State":"running"},{"Source":"b","State":"stopped"}]`), nil
		},
	}
	vms, err := r.List(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(vms) != 2 || vms[0].State != "running" || vms[1].State != "stopped" {
		t.Fatalf("got %+v", vms)
	}
}
