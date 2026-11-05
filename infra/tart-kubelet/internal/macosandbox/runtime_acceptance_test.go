package macosandbox

import (
	"context"
	"encoding/base64"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// Run only on a dedicated/reserved test Mac. This test deliberately does not
// acquire or evict fleet capacity itself. The hostname acknowledgement prevents
// accidentally starting a real VM during ordinary laptop or CI unit tests.
func TestAppleRuntimeAcceptance(t *testing.T) {
	hostname, _ := os.Hostname()
	if os.Getenv("TUIST_MACOS_E2E_RESERVED_HOST") != hostname || hostname == "" {
		t.Skip("requires an explicitly reserved Mac")
	}
	image := os.Getenv("TUIST_MACOS_E2E_IMAGE")
	root := os.Getenv("TUIST_MACOS_E2E_ROOT")
	if image == "" || !filepath.IsAbs(root) {
		t.Fatal("set a versioned sandbox-capable image and absolute isolated root")
	}
	if err := validateConfig(Config{URL: "https://test.invalid", Template: "macos", Image: image}); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(root, 0700); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()
	binary, err := BuildRuntime(ctx, filepath.Join(root, "runtime"))
	if err != nil {
		t.Fatal(err)
	}
	tools, err := installTools(filepath.Join(root, "tools"))
	if err != nil {
		t.Fatal(err)
	}
	directory, err := os.MkdirTemp(root, "acceptance-")
	if err != nil {
		t.Fatal(err)
	}
	c := &tart.Client{Binary: binary, HomeDir: filepath.Join(directory, "tart"), LogDir: filepath.Join(directory, "logs"), UserDataDir: filepath.Join(directory, "env"), EnsureGUISession: tart.EnsureRealGUISession, ExtraEnv: []string{"TART_NO_AUTO_PRUNE=1"}}
	if err = os.MkdirAll(c.HomeDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err = c.Pull(ctx, image); err != nil {
		t.Fatal(err)
	}
	m, _, capacity, args := harness(t)
	m.Root = filepath.Join(directory, "records")
	m.RuntimePath = binary
	m.ToolsPath = tools
	m.TemplateTag = image
	m.Runtime = &TartRuntime{Client: c, Image: image, Template: "macos", Tools: tools}
	if err = m.Load(ctx); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cleanup, done := context.WithTimeout(context.Background(), 2*time.Minute)
		defer done()
		if err := m.Delete(cleanup, args.SandboxID); err != nil {
			t.Errorf("cleanup: %v; retained %s", err, directory)
		} else {
			_ = os.RemoveAll(directory)
		}
	})
	if err = m.Create(ctx, args); err != nil {
		t.Fatal(err)
	}
	exec := func(command string) string {
		t.Helper()
		var output strings.Builder
		result, err := m.Exec(ctx, protocol.ExecArgs{SandboxID: args.SandboxID, Cmd: []string{"/bin/sh", "-c", command}, Cwd: "/Users/runner/work", TimeoutMs: 60000}, func(stream protocol.Stream) {
			if stream.Stream == "stdout" {
				data, _ := base64.StdEncoding.DecodeString(stream.DataB64)
				output.Write(data)
			}
		})
		if err != nil || result.ExitCode != 0 {
			t.Fatalf("guest exec: %v exit=%d", err, result.ExitCode)
		}
		return output.String()
	}
	// The nonce exists only in a detached process's heap. A disk-only cold boot
	// cannot satisfy the proof, even if every workspace file survived.
	exec(`node -e 'require("child_process").spawn(process.execPath,["-e","("+function(){const value=require("crypto").randomBytes(32).toString("hex");require("http").createServer((q,r)=>r.end(value)).listen(18765,"127.0.0.1")}.toString()+")()"],{detached:true,stdio:"ignore"}).unref()'; for i in 1 2 3 4 5; do curl -fsS http://127.0.0.1:18765 && exit 0; sleep 1; done; exit 1`)
	proof := exec("curl -fsS http://127.0.0.1:18765")
	if len(proof) != 64 {
		t.Fatal("invalid memory proof")
	}
	for i := 0; i < 3; i++ {
		if err = m.Pause(ctx, args.SandboxID); err != nil {
			t.Fatal(err)
		}
		started := time.Now()
		if err = m.Resume(ctx, args.SandboxID); err != nil {
			t.Fatal(err)
		}
		if exec("curl -fsS http://127.0.0.1:18765") != proof {
			t.Fatal("resident memory lost")
		}
		t.Logf("resident resume through first command: %s", time.Since(started))
	}
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: m.Runtime, Capacity: capacity}
	if err = recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	m = recovered
	capacity.allow = false
	if err = m.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if m.Snapshot()[0].Resident || capacity.held[args.SandboxID] {
		t.Fatal("eviction did not fence and release")
	}
	capacity.allow = true
	started := time.Now()
	if err = m.Resume(ctx, args.SandboxID); err != nil {
		t.Fatal(err)
	}
	if exec("curl -fsS http://127.0.0.1:18765") != proof {
		t.Fatal("restored memory lost")
	}
	t.Logf("evicted restore through first command: %s", time.Since(started))
}
