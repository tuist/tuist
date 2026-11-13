package macosandbox

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

type fakeCheckouts struct {
	seeded, collected []string
}

func (f *fakeCheckouts) SandboxShare(vm string) (string, error) { return "/cache/" + vm, nil }
func (f *fakeCheckouts) RemoveSandboxShare(string) error        { return nil }
func (f *fakeCheckouts) SeedSandbox(_ context.Context, g protocol.CheckoutGrant, share string) bool {
	f.seeded = append(f.seeded, g.ID+"@"+share)
	return true
}
func (f *fakeCheckouts) CollectSandbox(g protocol.CheckoutGrant, share string) {
	f.collected = append(f.collected, g.ID+"@"+share)
}

func testGrant() *protocol.CheckoutGrant {
	return &protocol.CheckoutGrant{ID: "11111111-1111-4111-8111-111111111111", Scope: strings.Repeat("a", 64), VolumeKey: strings.Repeat("d", 64),
		Commit: strings.Repeat("0", 40), Generation: 1, Path: "/Users/runner/work/claude-code/org/repo", DefaultBranchJob: true}
}

// A session's worker starts from the master in its VM's share, and the host
// takes its export only once an eviction has fenced the VM.
func TestCheckoutSeedsAtWorkerStartAndCollectsAfterTheFence(t *testing.T) {
	m, r, c, a := harness(t)
	checkouts := &fakeCheckouts{}
	m.Checkouts = checkouts
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	m.records[a.SandboxID].CheckoutShare = "/cache/" + a.SandboxID
	if _, err := m.StartWorker(ctx, a.SandboxID, map[string]string{"ANTHROPIC_WORK_ID": "work-1"}, testGrant()); err != nil {
		t.Fatal(err)
	}
	share := testGrant().ID + "@/cache/" + a.SandboxID
	if len(checkouts.seeded) != 1 || checkouts.seeded[0] != share {
		t.Fatalf("seeded %v", checkouts.seeded)
	}
	if r.workerEnv[protocol.CheckoutPathEnv] != testGrant().Path || r.workerEnv[protocol.CheckoutCommitEnv] != testGrant().Commit ||
		r.workerEnv[protocol.CheckoutShareEnv] != guestCheckoutShare || r.workerEnv["ANTHROPIC_WORK_ID"] != "work-1" {
		t.Fatalf("worker env %v", r.workerEnv)
	}
	// The grant survives a host restart until its export is taken.
	var journal Record
	data, _ := os.ReadFile(filepath.Join(m.Root, a.SandboxID+".json"))
	if err := json.Unmarshal(data, &journal); err != nil || journal.Checkout == nil || journal.Checkout.ID != testGrant().ID {
		t.Fatalf("journal %s", data)
	}

	// The worker exits; the running VM could still write the share.
	r.worker.Running = false
	if err := m.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if len(checkouts.collected) != 0 {
		t.Fatal("collected from a running VM")
	}
	c.allow = false // CI needs the room: the idle sandbox is saved.
	if err := m.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if len(checkouts.collected) != 1 || checkouts.collected[0] != share || m.records[a.SandboxID].Checkout != nil {
		t.Fatalf("collected %v, grant %+v", checkouts.collected, m.records[a.SandboxID].Checkout)
	}
}

func TestCheckoutGrantIsIgnoredWithoutAShareOrWhenInvalid(t *testing.T) {
	m, r, _, a := harness(t)
	checkouts := &fakeCheckouts{}
	m.Checkouts = checkouts
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	// A VM that booted before the host had shares.
	if _, err := m.StartWorker(ctx, a.SandboxID, map[string]string{"ANTHROPIC_WORK_ID": "work-1"}, testGrant()); err != nil {
		t.Fatal(err)
	}
	if _, ok := r.workerEnv[protocol.CheckoutPathEnv]; ok || len(checkouts.seeded) != 0 {
		t.Fatalf("a VM without a share got a checkout: %v", r.workerEnv)
	}
	m.records[a.SandboxID].CheckoutShare = "/cache/" + a.SandboxID
	grant := testGrant()
	grant.Path = "/Users/runner/.ssh"
	if _, err := m.StartWorker(ctx, a.SandboxID, map[string]string{"ANTHROPIC_WORK_ID": "work-1"}, grant); err != nil {
		t.Fatal(err)
	}
	if _, ok := r.workerEnv[protocol.CheckoutPathEnv]; ok || len(checkouts.seeded) != 0 {
		t.Fatalf("an invalid grant was used: %v", r.workerEnv)
	}
}

func TestCheckoutShareIsBoundAtBootAndKeptForRestores(t *testing.T) {
	runtime := &TartRuntime{Client: &tart.Client{HomeDir: "/home"}}
	r := &Record{CreateArgs: protocol.CreateArgs{SandboxID: "s1"}, ToolsPath: "/tools", CheckoutShare: "/cache/s1"}
	shares := runtime.options(r).SharedDirs
	if shares[len(shares)-1] != checkoutShareName+":/cache/s1" {
		t.Fatalf("shares %v", shares)
	}
	r.CheckoutShare = ""
	if shares := runtime.options(r).SharedDirs; len(shares) != 2 {
		t.Fatalf("a VM without a share got %v", shares)
	}
}
