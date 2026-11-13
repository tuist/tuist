package podagent

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"regexp"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// macOS sandboxes (internal/macosandbox) use the same checkout masters as CI
// VMs. Each sandbox VM boots with its own share under sandboxSharesDir, on the
// cache volume so a master clones into it. Before a session's worker starts,
// the host puts a clone of the master there (sandboxCheckoutImage), which the
// guest copies into place and removes. After the session, the guest leaves its
// export there in the CI format (cachevolumes.CheckoutExportDir), and the host
// takes it once the VM no longer runs, as it takes a CI job's after the Pod is
// gone. The server's grant (protocol.CheckoutGrant) stands in for the CI job's
// allocation; the guest only ever supplies the export, which the build verifies.
const (
	sandboxSharesDir     = "sandbox-checkouts"
	sandboxCheckoutImage = "checkout.sparseimage"
)

var sandboxShareName = regexp.MustCompile(`^[a-zA-Z0-9-]{1,128}$`)

// SandboxShare creates the empty checkout share of a VM about to boot.
func (c *CustomVolumes) SandboxShare(vm string) (string, error) {
	if c == nil || c.Checkouts == nil || !sandboxShareName.MatchString(vm) {
		return "", errors.New("sandbox checkouts unavailable")
	}
	if mounted, err := c.Space.backend.isMounted(c.Space.Root); err != nil || !mounted {
		return "", errors.New("cache filesystem unavailable")
	}
	parent := filepath.Join(c.Root, sandboxSharesDir)
	if err := os.MkdirAll(parent, 0o755); err != nil {
		return "", err
	}
	dir := filepath.Join(parent, vm)
	if err := os.RemoveAll(dir); err != nil {
		return "", err
	}
	if err := os.Mkdir(dir, 0o777); err != nil {
		return "", err
	}
	// The guest's user writes its export here, as with a CI VM's share.
	return dir, os.Chmod(dir, 0o777)
}

// RemoveSandboxShare drops a deleted VM's share and anything left in it.
func (c *CustomVolumes) RemoveSandboxShare(vm string) error {
	if c == nil || !sandboxShareName.MatchString(vm) {
		return nil
	}
	return os.RemoveAll(filepath.Join(c.Root, sandboxSharesDir, vm))
}

func (c *CustomVolumes) sandboxShare(share string) bool {
	return c != nil && sandboxShareName.MatchString(filepath.Base(share)) &&
		share == filepath.Join(c.Root, sandboxSharesDir, filepath.Base(share))
}

// SeedSandbox puts a clone of the grant's master in the VM's share and reports
// whether it did. Without a master here it queues a restore of the volume's
// HEAD, as a CI job does, so the repository's next session on this host is
// warm. The use ends either way: the clone is the guest's to copy, never a
// branch the host tracks, and the export is published under the use later.
func (c *CustomVolumes) SeedSandbox(ctx context.Context, grant protocol.CheckoutGrant, share string) bool {
	if !c.sandboxShare(share) || c.Checkouts == nil || !c.Checkouts.Ready() {
		return false
	}
	task := sandboxCheckoutTask(grant)
	c.Checkouts.Track(task)
	defer c.endUse(ctx, grant.ID)
	image := filepath.Join(share, sandboxCheckoutImage)
	_ = os.Remove(image)
	if c.Checkouts.Master(task.Scope, task.Generation) == "" {
		if task.BaseGeneration > 0 {
			c.Checkouts.Enqueue(task)
		}
		return false
	}
	slot := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: grant.ID, Scope: grant.Scope, Generation: grant.Generation, UID: grant.UID, Kind: cachevolumes.KindCheckout}}
	if err := c.Checkouts.Seed(ctx, slot, image); err != nil {
		_ = os.Remove(image)
		customCacheLog().Warn("sandbox checkout seed failed", "scope", grant.Scope, "error", err)
		return false
	}
	return true
}

// CollectSandbox takes the export a session left in its VM's share and queues
// a build from it. Call it only once the VM is stopped or saved, so the guest
// can no longer write what the host reads.
func (c *CustomVolumes) CollectSandbox(grant protocol.CheckoutGrant, share string) {
	if !c.sandboxShare(share) {
		return
	}
	_ = os.Remove(filepath.Join(share, sandboxCheckoutImage))
	src := filepath.Join(share, cachevolumes.CheckoutExportDir)
	if c.Checkouts == nil || !c.Checkouts.Ready() {
		_ = os.RemoveAll(src)
		return
	}
	c.queueExport(sandboxCheckoutTask(grant), src, "sandbox-"+grant.ID)
}

func sandboxCheckoutTask(grant protocol.CheckoutGrant) cachevolumes.CheckoutTask {
	return cachevolumes.CheckoutTask{
		Scope: grant.Scope, Generation: grant.Generation, CloneURL: grant.CloneURL, DefaultBranch: grant.DefaultBranch,
		Commit: grant.Commit, DefaultBranchJob: grant.DefaultBranchJob, MayStartMaster: grant.MayStartMaster, Use: grant.ID,
		VolumeKey: grant.VolumeKey, UID: grant.UID, BaseGeneration: grant.BaseGeneration, ImageDigest: grant.ImageDigest,
		ContentDigest: grant.ContentDigest,
	}
}
