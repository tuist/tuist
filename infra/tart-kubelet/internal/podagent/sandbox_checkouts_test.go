package podagent

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

func sandboxGrant(base int64) protocol.CheckoutGrant {
	grant := protocol.CheckoutGrant{
		ID: checkoutTestUse, Scope: checkoutTestScope, Generation: 1, UID: 502, CloneURL: "https://github.com/org/repo",
		DefaultBranch: "main", Commit: checkoutTestCommit, DefaultBranchJob: true, VolumeKey: strings.Repeat("d", 64),
		Path: "/Users/runner/work/claude-code/org/repo",
	}
	if base > 0 {
		grant.BaseGeneration, grant.ImageDigest, grant.ContentDigest = base, strings.Repeat("b", 40), strings.Repeat("c", 64)
	}
	return grant
}

func sandboxShareDir(t *testing.T, root string) string {
	t.Helper()
	share := filepath.Join(root, sandboxSharesDir, "sbx-1")
	if err := os.MkdirAll(share, 0o777); err != nil {
		t.Fatal(err)
	}
	return share
}

// A sandbox session starts from a clone of the CI master in its VM's share,
// and its export is built from like a default-branch job's.
func TestSandboxSessionSeedsFromTheMasterAndExportsUnderItsUse(t *testing.T) {
	root := t.TempDir()
	checkouts := preparedCheckouts(t, filepath.Join(root, "checkouts"))
	checkouts.Process(context.Background(), exportFrom(t, checkouts, "first", checkoutTestCommit, nil))
	c, _, reports := checkoutAgent(t, root, nil, checkouts)
	share := sandboxShareDir(t, root)

	if !c.SeedSandbox(context.Background(), sandboxGrant(0), share) {
		t.Fatal("a host with the master did not seed the session")
	}
	if image, _ := os.ReadFile(filepath.Join(share, sandboxCheckoutImage)); string(image) != "image" {
		t.Fatal("the share holds no clone of the master")
	}
	if len(*reports) != 1 || (*reports)[0]["state"] != "deleted" || (*reports)[0]["id"] != checkoutTestUse {
		t.Fatalf("the use was not ended: %v", *reports)
	}

	export := filepath.Join(share, cachevolumes.CheckoutExportDir)
	_ = os.MkdirAll(export, 0o755)
	_ = os.WriteFile(filepath.Join(export, "head"), []byte(checkoutTestCommit), 0o644)
	c.CollectSandbox(sandboxGrant(0), share)
	task, _ := checkouts.Pending(checkoutTestScope)
	if task.Export != checkouts.Incoming("sandbox-"+checkoutTestUse) || task.Use != checkoutTestUse || !task.DefaultBranchJob || task.MayStartMaster || task.Commit != checkoutTestCommit {
		t.Fatalf("queued %+v", task)
	}
	if entries, _ := os.ReadDir(share); len(entries) != 0 {
		t.Fatalf("the share keeps %v", entries)
	}
}

func TestSandboxSessionOnAColdHostRestoresTheHead(t *testing.T) {
	root := t.TempDir()
	checkouts := preparedCheckouts(t, filepath.Join(root, "checkouts"))
	c, _, reports := checkoutAgent(t, root, nil, checkouts)
	share := sandboxShareDir(t, root)
	if c.SeedSandbox(context.Background(), sandboxGrant(1), share) {
		t.Fatal("seeded without a master")
	}
	if task, _ := checkouts.Pending(checkoutTestScope); checkouts.Queued() != 1 || task.Export != "" || task.BaseGeneration != 1 {
		t.Fatalf("restore %+v", task)
	}
	if _, err := os.Stat(filepath.Join(share, sandboxCheckoutImage)); !os.IsNotExist(err) {
		t.Fatal("a cold seed left an image")
	}
	if len(*reports) != 1 {
		t.Fatalf("the use was not ended: %v", *reports)
	}
}

// Only a VM's own share under the cache root is used, and only a real export directory.
func TestSandboxCheckoutsRefuseOtherDirectoriesAndLinks(t *testing.T) {
	root := t.TempDir()
	checkouts := preparedCheckouts(t, filepath.Join(root, "checkouts"))
	checkouts.Process(context.Background(), exportFrom(t, checkouts, "first", checkoutTestCommit, nil))
	c := &CustomVolumes{Root: root, Checkouts: checkouts}
	elsewhere := t.TempDir()
	if c.SeedSandbox(context.Background(), sandboxGrant(0), elsewhere) {
		t.Fatal("seeded a directory outside the sandbox shares")
	}
	share := sandboxShareDir(t, root)
	_ = os.Symlink(t.TempDir(), filepath.Join(share, cachevolumes.CheckoutExportDir))
	c.CollectSandbox(sandboxGrant(0), share)
	if checkouts.Queued() != 0 {
		t.Fatal("collected a link out of the share")
	}
	if err := c.RemoveSandboxShare("../checkouts"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "checkouts")); err != nil {
		t.Fatal("removed a directory that is not a share")
	}
}
