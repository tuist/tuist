package sandbox

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
)

func TestDiskSnapshotLifecycle(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	if err := os.MkdirAll(h.m.cfg.SnapshotDir, 0o700); err != nil {
		t.Fatal(err)
	}
	h.create(t, "source", 10)
	sourceRoot := vm.RootDir(h.jailBase, "source")
	if err := os.WriteFile(filepath.Join(sourceRoot, "workspace.ext4"), []byte("prepared workspace"), 0o644); err != nil {
		t.Fatal(err)
	}

	res, err := h.m.PauseWith(ctx, protocol.PauseArgs{SandboxID: "source", SyncDisks: true})
	if err != nil || !res.DisksSynced {
		t.Fatalf("synced pause %+v %v", res, err)
	}
	var synced bool
	for _, exec := range h.launcher.Instances()[1].Agent.RequestsOf("exec") {
		if cmd, _ := exec["cmd"].([]any); len(cmd) == 1 && cmd[0] == "/bin/sync" {
			synced = true
		}
	}
	if !synced {
		t.Fatal("a synced pause must run sync in the guest")
	}
	if meta, _ := LoadMetadata(sourceRoot); !meta.DisksSynced {
		t.Fatalf("metadata must record the synced disks: %+v", meta)
	}

	if _, err := h.m.SaveDisks(ctx, protocol.SaveDisksArgs{SandboxID: "source", SnapshotID: "snap1"}); err != nil {
		t.Fatalf("save disks: %v", err)
	}
	dir := filepath.Join(h.m.cfg.SnapshotDir, "snap1")
	for _, name := range []string{"vmlinux", "rootfs.ext4", "workspace.ext4", diskSnapshotFile} {
		if !vm.Exists(filepath.Join(dir, name)) {
			t.Fatalf("disk snapshot is missing %s", name)
		}
	}
	listed := h.m.DiskSnapshots()
	if len(listed) != 1 || listed[0].ID != "snap1" || listed[0].Template != "default" || listed[0].TemplateTag != "t1" || listed[0].WorkspaceGB != 10 {
		t.Fatalf("disk snapshots %+v", listed)
	}

	launches := len(h.launcher.Instances())
	if _, err := h.m.Create(ctx, protocol.CreateArgs{SandboxID: "clone", Template: "default", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 10, FromDiskSnapshot: "snap1"}); err != nil {
		t.Fatalf("create from disk snapshot: %v", err)
	}
	cloneRoot := vm.RootDir(h.jailBase, "clone")
	if data, _ := os.ReadFile(filepath.Join(cloneRoot, "workspace.ext4")); string(data) != "prepared workspace" {
		t.Fatalf("the clone must get the snapshot's workspace, got %q", data)
	}
	if vm.Exists(filepath.Join(cloneRoot, "mem")) {
		t.Fatal("a clone has no memory image until its first pause")
	}
	if len(h.launcher.Instances()) != launches+1 {
		t.Fatal("a create from a disk snapshot must not build the template shape")
	}
	booted := h.launcher.Last()
	var loaded, started bool
	for _, call := range booted.Calls() {
		switch call.Path {
		case "/snapshot/load":
			loaded = true
		case "/actions":
			started = true
		}
	}
	if loaded || !started {
		t.Fatalf("a clone must cold boot (loaded=%v started=%v)", loaded, started)
	}
	if configures := booted.Agent.RequestsOf("configure"); len(configures) != 1 || configures[0]["format_workspace"] != nil {
		t.Fatalf("a clone must keep its workspace: %v", configures)
	}
	meta, _ := LoadMetadata(cloneRoot)
	if meta.State != protocol.StateRunning || meta.Tag != "t1" || meta.DisksSynced {
		t.Fatalf("clone metadata %+v", meta)
	}
	if _, err := h.m.Pause(ctx, "clone"); err != nil {
		t.Fatalf("pause clone: %v", err)
	}
	if _, err := h.m.Resume(ctx, "clone"); err != nil {
		t.Fatalf("resume clone: %v", err)
	}

	if _, err := h.m.Resume(ctx, "source"); err != nil {
		t.Fatalf("resume source: %v", err)
	}
	if meta, _ := LoadMetadata(sourceRoot); meta.DisksSynced {
		t.Fatal("a resume must clear the synced flag")
	}
	if _, err := h.m.Pause(ctx, "source"); err != nil {
		t.Fatal(err)
	}
	if _, err := h.m.SaveDisks(ctx, protocol.SaveDisksArgs{SandboxID: "source", SnapshotID: "snap2"}); !errors.Is(err, ErrDisksNotSynced) {
		t.Fatalf("saving unsynced disks must fail, got %v", err)
	}

	if _, err := h.m.Create(ctx, protocol.CreateArgs{SandboxID: "wrongsize", Template: "default", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 20, FromDiskSnapshot: "snap1"}); !errors.Is(err, ErrDiskSnapshotMismatch) {
		t.Fatalf("a workspace size mismatch must fail, got %v", err)
	}
	if vm.Exists(vm.JailDir(h.jailBase, "wrongsize")) {
		t.Fatal("a failed clone must remove its jail")
	}
	if _, err := h.m.Create(ctx, protocol.CreateArgs{SandboxID: "missing", Template: "default", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 10, FromDiskSnapshot: "nosuch"}); !errors.Is(err, ErrDiskSnapshotNotFound) {
		t.Fatalf("a missing snapshot must fail, got %v", err)
	}

	if err := h.m.DeleteDisks(ctx, "snap1"); err != nil {
		t.Fatal(err)
	}
	if err := h.m.DeleteDisks(ctx, "snap1"); err != nil {
		t.Fatalf("deleting an absent snapshot must succeed, got %v", err)
	}
	if len(h.m.DiskSnapshots()) != 0 {
		t.Fatal("deleted snapshot still listed")
	}
	if data, _ := os.ReadFile(filepath.Join(cloneRoot, "workspace.ext4")); string(data) != "prepared workspace" {
		t.Fatal("deleting a snapshot must not touch its clones")
	}
}

func TestRecoverRemovesPartialDiskSnapshots(t *testing.T) {
	h := newHarness(t)
	partial := filepath.Join(h.m.cfg.SnapshotDir, diskSnapshotTmpPrefix+"snap1")
	if err := os.MkdirAll(partial, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := h.m.Recover(context.Background()); err != nil {
		t.Fatal(err)
	}
	if vm.Exists(partial) {
		t.Fatal("recover must remove a partial disk snapshot")
	}
}

func TestCacheImageDrive(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	if err := os.MkdirAll(h.m.cfg.SnapshotDir, 0o700); err != nil {
		t.Fatal(err)
	}
	h.create(t, "source", 10)
	if err := os.WriteFile(filepath.Join(vm.RootDir(h.jailBase, "source"), "workspace.ext4"), []byte("workspace"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := h.m.PauseWith(ctx, protocol.PauseArgs{SandboxID: "source", SyncDisks: true}); err != nil {
		t.Fatal(err)
	}
	if _, err := h.m.SaveDisks(ctx, protocol.SaveDisksArgs{SandboxID: "source", SnapshotID: "snap1"}); err != nil {
		t.Fatal(err)
	}
	clone := protocol.CreateArgs{SandboxID: "cached", Template: "default", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 10, FromDiskSnapshot: "snap1", CacheImage: "go-cache"}
	if _, err := h.m.Create(ctx, clone); !errors.Is(err, ErrCacheImage) {
		t.Fatalf("a daemon without a cache image directory must refuse, got %v", err)
	}

	h.m.cfg.CacheImageDir = filepath.Join(h.dataDir, "cache-images")
	if err := os.MkdirAll(h.m.cfg.CacheImageDir, 0o700); err != nil {
		t.Fatal(err)
	}
	master := filepath.Join(h.m.cfg.CacheImageDir, "go-cache")
	if err := os.WriteFile(master, []byte("warm cache"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(master, filepath.Join(h.m.cfg.CacheImageDir, "linked")); err != nil {
		t.Fatal(err)
	}
	fromTemplate := protocol.CreateArgs{SandboxID: "warm", Template: "default", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 10, CacheImage: "go-cache"}
	if _, err := h.m.Create(ctx, fromTemplate); !errors.Is(err, ErrCacheImage) {
		t.Fatalf("a memory-snapshot create cannot gain a drive, got %v", err)
	}
	linked := clone
	linked.SandboxID, linked.CacheImage = "linked", "linked"
	if _, err := h.m.Create(ctx, linked); !errors.Is(err, ErrCacheImage) {
		t.Fatalf("a symlinked cache image must be refused, got %v", err)
	}

	if _, err := h.m.Create(ctx, clone); err != nil {
		t.Fatalf("create with a cache drive: %v", err)
	}
	attached := filepath.Join(vm.RootDir(h.jailBase, "cached"), "cache.ext4")
	if err := os.WriteFile(attached, []byte("guest writes"), 0o644); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(master); string(data) != "warm cache" {
		t.Fatalf("guest writes must not reach the master, got %q", data)
	}
	var drive bool
	for _, call := range h.launcher.Last().Calls() {
		if call.Path == "/drives/cache" {
			drive = true
		}
	}
	if !drive {
		t.Fatal("the cold boot must attach the cache drive")
	}
	if err := h.m.Delete(ctx, "cached"); err != nil {
		t.Fatal(err)
	}
	if vm.Exists(attached) {
		t.Fatal("deleting the sandbox must discard its cache clone")
	}
}
