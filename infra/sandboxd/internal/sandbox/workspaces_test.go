package sandbox

import (
	"archive/tar"
	"bufio"
	"bytes"
	"context"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/checkout"
	"github.com/tuist/tuist/infra/sandboxd/internal/fakevm"
	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

const preparedImage = "prepared workspace image"

var workspaceGrant = &protocol.CheckoutGrant{
	ID: "11111111-1111-4111-8111-111111111111", Scope: strings.Repeat("ab", 32), Generation: 3,
	Commit: "0123456789abcdef0123456789abcdef01234567", Path: "/workspace/claude-code/acme/app",
}

type treeAgent struct{ tree []byte }

func (a treeAgent) Seed(context.Context, protocol.CheckoutGrant) (io.ReadCloser, error) {
	return io.NopCloser(bytes.NewReader(a.tree)), nil
}

func (treeAgent) Export(context.Context, protocol.CheckoutGrant, io.Reader) error { return nil }

func masterTree(t *testing.T) []byte {
	t.Helper()
	var buffer bytes.Buffer
	archive := tar.NewWriter(&buffer)
	for _, file := range [][2]string{{".git/HEAD", "0123456789abcdef0123456789abcdef01234567\n"}, {"main.swift", "print(1)\n"}} {
		archive.WriteHeader(&tar.Header{Name: file[0], Mode: 0o644, Typeflag: tar.TypeReg, Size: int64(len(file[1]))})
		archive.Write([]byte(file[1]))
	}
	archive.Close()
	return buffer.Bytes()
}

// withWorkspaces gives the harness prepared workspaces whose images hold
// preparedImage, and a template that records its runner user.
func withWorkspaces(t *testing.T, h *harness) *checkout.Workspaces {
	t.Helper()
	tmpl, err := h.m.store.Get("default", "t1")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpl.Dir, template.MetadataFile), []byte(`{"name":"default","runner_uid":1001,"runner_gid":1001}`), 0o644); err != nil {
		t.Fatal(err)
	}
	w := &checkout.Workspaces{
		Dir: t.TempDir(), MaxBytes: 1 << 30, TTL: time.Hour,
		FreeBytes: func(string) (int64, error) { return 1 << 50, nil },
		Mkfs: func(_ context.Context, image, _ string) error {
			return os.WriteFile(image, []byte(preparedImage), 0o600)
		},
	}
	h.m.checkouts = treeAgent{tree: masterTree(t)}
	h.m.workspaces = w
	return w
}

func prepare(t *testing.T, h *harness, w *checkout.Workspaces) {
	t.Helper()
	sb, err := h.m.get(testID)
	if err != nil {
		t.Fatal(err)
	}
	key, ok := h.m.workspaceKey(sb.meta, workspaceGrant)
	if !ok {
		t.Fatal("no workspace key")
	}
	recording := w.Recorder(key)
	recording.Write(masterTree(t))
	recording.Finish(true)
	awaitPrepared(t, w, key)
}

func awaitPrepared(t *testing.T, w *checkout.Workspaces, key checkout.WorkspaceKey) {
	t.Helper()
	for deadline := time.Now().Add(10 * time.Second); time.Now().Before(deadline); time.Sleep(10 * time.Millisecond) {
		if _, ok := w.Lookup(key); ok {
			return
		}
	}
	t.Fatal("no prepared workspace")
}

func workspaceFile(t *testing.T, h *harness) string {
	t.Helper()
	// An empty workspace is a sparse 10 GiB file: compare its first bytes.
	file, err := os.Open(filepath.Join(vm.RootDir(h.m.cfg.JailBase, testID), firecracker.WorkspacePath))
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	data := make([]byte, len(preparedImage))
	n, _ := io.ReadFull(file, data)
	return string(data[:n])
}

func execCommands(inst *fakevm.Instance) []string {
	var cmds []string
	for _, request := range inst.Agent.RequestsOf("exec") {
		raw, _ := request["cmd"].([]any)
		var cmd []string
		for _, part := range raw {
			cmd = append(cmd, part.(string))
		}
		cmds = append(cmds, strings.Join(cmd, " "))
	}
	return cmds
}

func TestAFreshSandboxsFirstWorkerStartsFromThePreparedWorkspace(t *testing.T) {
	h := newHarness(t)
	w := withWorkspaces(t, h)
	h.create(t, testID, 10)
	prepare(t, h, w)
	inst := h.launcher.Instances()[1]
	configures := len(inst.Agent.RequestsOf("configure"))

	if _, err := h.m.StartWorker(context.Background(), protocol.StartWorkerArgs{SandboxID: testID, Checkout: workspaceGrant}); err != nil {
		t.Fatal(err)
	}
	defer h.m.StopWorker(context.Background(), testID)

	if got := workspaceFile(t, h); got != preparedImage {
		t.Fatalf("workspace disk holds %q, not the prepared image", got)
	}
	if cmds := execCommands(inst); len(cmds) != 2 || cmds[0] != "/bin/umount /workspace" || cmds[1] != DefaultWorkerPath {
		t.Fatalf("guest execs %v: the empty workspace must be unmounted before the worker starts", cmds)
	}
	remount := inst.Agent.RequestsOf("configure")[configures:]
	if len(remount) != 1 || remount[0]["format_workspace"] == true {
		t.Fatalf("the guest must mount the prepared disk without formatting it: %v", remount)
	}
	var patched bool
	for _, call := range inst.Calls() {
		patched = patched || (call.Method == "PATCH" && call.Path == "/drives/"+firecracker.WorkspaceDriveID)
	}
	if !patched {
		t.Fatal("Firecracker was not told to reopen the workspace drive")
	}
	for _, leftover := range []string{".prepared", ".empty"} {
		if vm.Exists(filepath.Join(vm.RootDir(h.m.cfg.JailBase, testID), firecracker.WorkspacePath+leftover)) {
			t.Errorf("left %s behind", leftover)
		}
	}
	// The worker still gets the grant, for its export.
	workerEnv, _ := inst.Agent.RequestsOf("exec")[1]["env"].(map[string]any)
	if workerEnv[protocol.CheckoutPathEnv] != workspaceGrant.Path {
		t.Fatalf("worker env %v", workerEnv)
	}
}

func TestThePreparedWorkspaceReplacesOnlyAnUntouchedEmptyWorkspace(t *testing.T) {
	for name, tc := range map[string]struct {
		before func(t *testing.T, h *harness)
		umount int
	}{
		"after an exec": {before: func(t *testing.T, h *harness) {
			if _, err := h.m.Exec(context.Background(), protocol.ExecArgs{SandboxID: testID, Cmd: []string{"true"}}, nil); err != nil {
				t.Fatal(err)
			}
		}},
		"after a worker": {before: func(t *testing.T, h *harness) {
			if _, err := h.m.StartWorker(context.Background(), protocol.StartWorkerArgs{SandboxID: testID}); err != nil {
				t.Fatal(err)
			}
			if err := h.m.StopWorker(context.Background(), testID); err != nil {
				t.Fatal(err)
			}
		}},
		"guest cannot unmount": {before: func(*testing.T, *harness) {}, umount: 32},
	} {
		t.Run(name, func(t *testing.T) {
			h := newHarness(t)
			w := withWorkspaces(t, h)
			h.create(t, testID, 10)
			prepare(t, h, w)
			inst := h.launcher.Instances()[1]
			inst.Agent.ExecHook = func(req map[string]any, _ func(string, []byte)) (int, bool) {
				cmd, _ := req["cmd"].([]any)
				return tc.umount, len(cmd) > 0 && cmd[0] == "/bin/umount"
			}
			tc.before(t, h)
			before := workspaceFile(t, h)

			if _, err := h.m.StartWorker(context.Background(), protocol.StartWorkerArgs{SandboxID: testID, Checkout: workspaceGrant}); err != nil {
				t.Fatalf("the worker did not start: %v", err)
			}
			defer h.m.StopWorker(context.Background(), testID)
			if got := workspaceFile(t, h); got != before {
				t.Fatalf("the workspace changed to %q", got)
			}
		})
	}
}

func TestAFirstSeedOnTheNodePreparesTheWorkspaceForTheNextSandbox(t *testing.T) {
	h := newHarness(t)
	w := withWorkspaces(t, h)
	h.create(t, testID, 10)
	inst := h.launcher.Instances()[1]
	if _, err := h.m.StartWorker(context.Background(), protocol.StartWorkerArgs{SandboxID: testID, Checkout: workspaceGrant}); err != nil {
		t.Fatal(err)
	}
	defer h.m.StopWorker(context.Background(), testID)
	if cmds := execCommands(inst); len(cmds) != 1 {
		t.Fatalf("the guest was asked to swap without a prepared workspace: %v", cmds)
	}

	conn, err := net.Dial("unix", inst.VsockPath()+"_"+strconv.Itoa(protocol.CheckoutVsockPort))
	if err != nil {
		t.Fatal(err)
	}
	conn.SetDeadline(time.Now().Add(5 * time.Second))
	conn.Write([]byte(`{"op":"seed"}` + "\n"))
	answer, _ := io.ReadAll(bufio.NewReader(conn))
	conn.Close()
	if !bytes.HasSuffix(answer, masterTree(t)) {
		t.Fatalf("seed answered %d bytes, not the agent's tree", len(answer))
	}
	sb, _ := h.m.get(testID)
	key, _ := h.m.workspaceKey(sb.meta, workspaceGrant)
	awaitPrepared(t, w, key)
}
