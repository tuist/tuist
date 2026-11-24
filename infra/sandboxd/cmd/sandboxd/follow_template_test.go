package main

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/fakevm"
	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/network"
	"github.com/tuist/tuist/infra/sandboxd/internal/sandbox"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

func seedTag(t *testing.T, templatesDir, tag string) {
	t.Helper()
	dir := filepath.Join(templatesDir, "default", tag)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{template.KernelFile, template.RootfsFile} {
		if err := os.WriteFile(filepath.Join(dir, f), []byte(tag+" "+f), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func setCurrent(t *testing.T, templatesDir, tag string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(templatesDir, "default", template.CurrentFile), []byte(tag+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestFollowTemplateSwitchesOnceTheNewTagsShapesAreBuilt(t *testing.T) {
	interval, retryAfter := templateFollowInterval, templateRetryAfter
	templateFollowInterval, templateRetryAfter = 20*time.Millisecond, time.Second
	t.Cleanup(func() { templateFollowInterval, templateRetryAfter = interval, retryAfter })

	dataDir := t.TempDir()
	templatesDir := filepath.Join(dataDir, "templates")
	seedTag(t, templatesDir, "t1")
	// The first template build fails, as a broken template would.
	launcher := &fakevm.Launcher{FailLaunch: errors.New("boot failed")}
	net := &fakevm.Network{}
	slots := network.NewSlots(8)
	store := &template.Store{Dir: templatesDir}
	agent := func(path string) vsock.Agent { return vsock.NewUDSClient(path, firecracker.AgentPort) }
	builder := &template.Builder{
		Store: store, Launcher: launcher, Network: net, Slots: slots, Agent: agent, JailBase: filepath.Join(dataDir, "jail"),
		JailerEnabled: true, UIDBase: 10000, DNS: []string{"10.128.0.10"}, FirecrackerVersion: "v1.16.1",
		WorkspaceGB: 10, BootTimeout: 5 * time.Second, CloneFile: fakevm.CopyFile,
	}
	manager := sandbox.New(sandbox.Config{
		JailBase: filepath.Join(dataDir, "jail"), FirecrackerBin: "/fc", JailerBin: "/jailer", JailerEnabled: true, UIDBase: 10000,
		DNS: []string{"10.128.0.10"}, DefaultTemplate: "default", DefaultTemplateTag: "t1", BootTimeout: 5 * time.Second, FirecrackerVersion: "v1.16.1",
	}, sandbox.Deps{
		Store: store, Builder: builder, Launcher: launcher, Network: net, Slots: slots, Agent: agent,
		Metrics: sandbox.NewMetrics(nil), CloneFile: fakevm.CopyFile,
	})
	shape := template.Shape{VCPUs: 2, MemoryMB: 4096}
	var pruned, reports atomic.Int32
	prune := func(current string) {
		if current == "t2" {
			pruned.Add(1)
		}
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go followTemplate(ctx, slog.New(slog.NewTextHandler(io.Discard, nil)), store, builder, manager, "default",
		[]template.Shape{shape}, true, prune, func() { reports.Add(1) })

	// A pointer naming a tag that is not on disk changes nothing.
	setCurrent(t, templatesDir, "t3")
	time.Sleep(100 * time.Millisecond)
	if got := manager.DefaultTemplateTag(); got != "t1" {
		t.Fatalf("switched to a tag that is not installed: %q", got)
	}

	// An installed tag whose shape fails to build is not switched to; creates
	// keep the previous tag until a later attempt builds it.
	seedTag(t, templatesDir, "t2")
	setCurrent(t, templatesDir, "t2")
	time.Sleep(400 * time.Millisecond)
	if got := manager.DefaultTemplateTag(); got != "t1" {
		t.Fatalf("switched to a tag whose shape failed to build: %q", got)
	}
	deadline := time.Now().Add(10 * time.Second)
	for manager.DefaultTemplateTag() != "t2" {
		if time.Now().After(deadline) {
			t.Fatal("the default tag never moved to t2")
		}
		time.Sleep(10 * time.Millisecond)
	}
	t2, err := store.Get("default", "t2")
	if err != nil {
		t.Fatal(err)
	}
	if !t2.ShapeReady(shape) {
		t.Fatal("switched before the new tag's prebuilt shape was ready")
	}
	deadline = time.Now().Add(5 * time.Second)
	for pruned.Load() == 0 || reports.Load() == 0 {
		if time.Now().After(deadline) {
			t.Fatalf("after the switch: pruned %d times, reported %d times", pruned.Load(), reports.Load())
		}
		time.Sleep(10 * time.Millisecond)
	}
}
