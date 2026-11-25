package main

import (
	"encoding/json"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"
)

const ownContainer = "d95139643cb05c11631d887aafb9c05b8ff1e8615aacf2e39fb6c4708a37b0e8"

func TestContainerID(t *testing.T) {
	for _, cgroup := range []string{
		"0::/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-podac18b44e_59d3_4757_8239_bafea77f9a76.slice/cri-containerd-" + ownContainer + ".scope\n",
		"0::/kubepods/burstable/podac18b44e-59d3-4757-8239-bafea77f9a76/" + ownContainer + "\n",
	} {
		if got := containerID(cgroup); got != ownContainer {
			t.Fatalf("containerID(%q) = %q", cgroup, got)
		}
	}
	if got := containerID("0::/user.slice\n"); got != "" {
		t.Fatalf("a cgroup without a container id gave %q", got)
	}
}

// Only an unexpired marker naming this very container arms a handover: a
// stale one, or one the updater wrote for the previous container, must not
// keep a deleted Pod's VMs from pausing.
func TestHandoverArmed(t *testing.T) {
	now := time.Date(2026, 11, 24, 12, 0, 0, 0, time.UTC)
	dir := t.TempDir()
	file := filepath.Join(dir, "annotations")
	arm := &handoverArm{file: file, container: ownContainer, log: slog.New(slog.NewTextHandler(io.Discard, nil)), now: func() time.Time { return now }}
	write := func(marker handoverMarker) {
		value, _ := json.Marshal(marker)
		// The downward API's format: one key="quoted value" line each.
		data := "prometheus.io/port=\"9470\"\n" + handoverAnnotation + "=" + strconv.Quote(string(value)) + "\n"
		if err := os.WriteFile(file, []byte(data), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if _, ok := arm.armed(); ok {
		t.Fatal("armed without a file")
	}
	write(handoverMarker{Container: "containerd://" + ownContainer, Until: now.Add(time.Minute), Nonce: "n1"})
	if marker, ok := arm.armed(); !ok || marker.Nonce != "n1" {
		t.Fatalf("armed = %+v, %v for this container's marker", marker, ok)
	}
	write(handoverMarker{Container: "containerd://" + ownContainer, Until: now, Nonce: "n2"})
	if _, ok := arm.armed(); ok {
		t.Fatal("an expired marker armed")
	}
	write(handoverMarker{Container: "containerd://0000000000000000000000000000000000000000000000000000000000000000", Until: now.Add(time.Minute), Nonce: "n3"})
	if _, ok := arm.armed(); ok {
		t.Fatal("another container's marker armed")
	}
}
