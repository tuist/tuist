//go:build e2e

package dedibox

import (
	"context"
	"os"
	"testing"
)

// TestDediboxProbe is a read-only smoke test against the live Scaleway Dedibox
// API, gated behind the `e2e` build tag so it never runs in CI. It validates the
// raw-HTTP client end to end without writing anything: that the project's
// pre-ordered box is visible (and what zone/datacenter/offer the API reports),
// and that the install OS resolves. Run with the default-project IAM creds:
//
//	GOTOOLCHAIN=go1.26.4 \
//	DEDIBOX_SCW_SECRET_KEY=... DEDIBOX_SCW_PROJECT_ID=f84f3b7f-... \
//	go test -tags=e2e -run TestDediboxProbe ./internal/dedibox/ -v
//
// Optional overrides: DEDIBOX_PROBE_DATACENTER (default DC2),
// DEDIBOX_PROBE_OFFER (default Start-1-M-SSD), DEDIBOX_PROBE_OS (ubuntu_24.04),
// DEDIBOX_PROBE_TAG (when set, also asserts the box carries that fleet tag).
func TestDediboxProbe(t *testing.T) {
	if os.Getenv("DEDIBOX_SCW_SECRET_KEY") == "" {
		t.Skip("set DEDIBOX_SCW_SECRET_KEY / DEDIBOX_SCW_PROJECT_ID to run the live probe")
	}
	c, err := NewClientFromEnv()
	if err != nil {
		t.Fatalf("client: %v", err)
	}
	t.Logf("project: %s", c.ProjectID)
	ctx := context.Background()

	dc := envOr("DEDIBOX_PROBE_DATACENTER", "DC2")
	offer := envOr("DEDIBOX_PROBE_OFFER", "Start-1-M-SSD")

	// 1) Find the box by offer + datacenter (no tag), revealing the live field
	//    values the client keys on.
	srv, err := c.FindAdoptableServer(ctx, AdoptParams{Datacenter: dc, Offer: offer}, map[uint64]bool{})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if srv == nil {
		t.Fatalf("no Dedibox %q server in %s visible to this project/key", offer, dc)
	}
	t.Logf("found server id=%d zone=%s datacenter=%q offer=%q hostname=%q installed=%v publicIP=%s",
		srv.ID, srv.Zone, srv.Datacenter, srv.Offer, srv.Hostname, srv.Installed, srv.PublicIP)

	// 2) Optional: assert the fleet tag is present (the env boundary marker).
	if tag := os.Getenv("DEDIBOX_PROBE_TAG"); tag != "" {
		tagged, terr := c.FindAdoptableServer(ctx, AdoptParams{Tag: tag, Datacenter: dc, Offer: offer}, map[uint64]bool{})
		if terr != nil {
			t.Fatalf("tag adopt: %v", terr)
		}
		if tagged == nil {
			t.Fatalf("no server carrying tag %q — has the box been tagged?", tag)
		}
		t.Logf("tag %q matched server %d", tag, tagged.ID)
	}

	// 3) The install OS resolves on the box (meaningful while it is still bare).
	osLabel := envOr("DEDIBOX_PROBE_OS", "ubuntu_24.04")
	osChoice, err := c.ResolveOS(ctx, srv.Zone, srv.ID, osLabel)
	if err != nil {
		t.Fatalf("resolve OS %q: %v", osLabel, err)
	}
	t.Logf("resolved OS %q -> id=%d requiresUser=%v requiresAdminPassword=%v",
		osLabel, osChoice.ID, osChoice.RequiresUser, osChoice.RequiresAdminPassword)
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
