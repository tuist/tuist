package dedibox

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"net/url"
	"strings"
	"testing"

	scwdedibox "github.com/scaleway/scaleway-sdk-go/api/dedibox/v1"
)

// fakeTransport routes get by path (ignoring query) against a canned response
// map, JSON round-tripped into the caller's out. Unmapped `/servers` list paths
// return an empty list so zone iteration completes; other unmapped paths 404.
type fakeTransport struct {
	gets  map[string]any
	posts []postCall
}

type postCall struct {
	path string
	body any
}

func (f *fakeTransport) get(_ context.Context, path string, _ url.Values, out any) error {
	if v, ok := f.gets[path]; ok {
		return remarshal(out, v)
	}
	if strings.HasSuffix(path, "/servers") {
		return nil
	}
	return &apiError{status: http.StatusNotFound, body: "not found: " + path}
}

func (f *fakeTransport) post(_ context.Context, path string, body, _ any) error {
	f.posts = append(f.posts, postCall{path: path, body: body})
	return nil
}

func remarshal(dst, src any) error {
	b, err := json.Marshal(src)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, dst)
}

func TestProviderID(t *testing.T) {
	if got, want := ProviderID("fr-par-1", 75839), "dedibox://fr-par-1/75839"; got != want {
		t.Fatalf("ProviderID = %q, want %q", got, want)
	}
}

// TestFindAdoptableServerByTag is the environment-boundary guarantee: every
// Dedibox shares the default project, so the per-fleet tag is the only thing
// scoping the pool. A box tagged for another fleet is never adopted.
func TestFindAdoptableServerByTag(t *testing.T) {
	f := &fakeTransport{gets: map[string]any{
		"/dedibox/v1/zones/fr-par-1/servers": scwdedibox.ListServersResponse{
			TotalCount: 2,
			Servers: []*scwdedibox.ServerSummary{
				{ID: 1, OfferName: "Start-1-M-SSD", DatacenterName: "DC2", Zone: "fr-par-1"},
				{ID: 2, OfferName: "Start-1-M-SSD", DatacenterName: "DC2", Zone: "fr-par-1"},
			},
		},
		"/dedibox/v1/zones/fr-par-1/servers/1": scwdedibox.Server{Zone: "fr-par-1", ID: 1, Tags: []string{"tuist-kura-prod"}},
		"/dedibox/v1/zones/fr-par-1/servers/2": scwdedibox.Server{Zone: "fr-par-1", ID: 2, Tags: []string{"tuist-kura-staging"}},
	}}
	c := &Client{t: f, ProjectID: "proj"}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{
		Tag:        "tuist-kura-staging",
		Offer:      "Start-1-M-SSD",
		Datacenter: "DC2",
	}, map[uint64]bool{})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got == nil || got.ID != 2 {
		t.Fatalf("FindAdoptableServer = %+v, want server 2 (only one tagged staging)", got)
	}
}

func TestFindAdoptableServerExhausted(t *testing.T) {
	f := &fakeTransport{gets: map[string]any{
		"/dedibox/v1/zones/fr-par-1/servers": scwdedibox.ListServersResponse{
			Servers: []*scwdedibox.ServerSummary{{ID: 1, OfferName: "Start-1-M-SSD", DatacenterName: "DC2", Zone: "fr-par-1"}},
		},
		"/dedibox/v1/zones/fr-par-1/servers/1": scwdedibox.Server{Zone: "fr-par-1", ID: 1, Tags: []string{"tuist-kura-prod"}},
	}}
	c := &Client{t: f, ProjectID: "proj"}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{Tag: "tuist-kura-staging"}, map[uint64]bool{})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got != nil {
		t.Fatalf("FindAdoptableServer = %+v, want nil (no staging-tagged box)", got)
	}
}

func TestFindAdoptableServerClaimedSkipped(t *testing.T) {
	f := &fakeTransport{gets: map[string]any{
		"/dedibox/v1/zones/fr-par-1/servers": scwdedibox.ListServersResponse{
			Servers: []*scwdedibox.ServerSummary{
				{ID: 5, OfferName: "Start-1-M-SSD", DatacenterName: "DC2", Zone: "fr-par-1"},
				{ID: 6, OfferName: "Start-1-M-SSD", DatacenterName: "DC2", Zone: "fr-par-1"},
			},
		},
		"/dedibox/v1/zones/fr-par-1/servers/6": scwdedibox.Server{Zone: "fr-par-1", ID: 6, Tags: []string{"tuist-kura-staging"}},
	}}
	c := &Client{t: f, ProjectID: "proj"}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{Tag: "tuist-kura-staging"}, map[uint64]bool{5: true})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got == nil || got.ID != 6 {
		t.Fatalf("FindAdoptableServer = %+v, want server 6 (5 already claimed)", got)
	}
}

func TestResolveOS(t *testing.T) {
	f := &fakeTransport{gets: map[string]any{
		"/dedibox/v1/zones/fr-par-1/os": scwdedibox.ListOSResponse{
			Os: []*scwdedibox.OS{
				{ID: 1, Name: "Debian", Version: "12"},
				{ID: 2, Name: "Ubuntu", Version: "24.04", RequiresUser: true},
			},
		},
	}}
	c := &Client{t: f, ProjectID: "proj"}

	got, err := c.ResolveOS(context.Background(), "fr-par-1", 7, "ubuntu_24.04")
	if err != nil {
		t.Fatalf("ResolveOS: %v", err)
	}
	if got.ID != 2 || !got.RequiresUser {
		t.Fatalf("ResolveOS = %+v, want Ubuntu 24.04 (id 2, RequiresUser)", got)
	}
}

func TestStartInstall(t *testing.T) {
	f := &fakeTransport{gets: map[string]any{
		"/dedibox/v1/zones/fr-par-1/servers/7/partitioning/2": scwdedibox.ServerDefaultPartitioning{
			Partitions: []*scwdedibox.Partition{{FileSystem: "ext4"}},
		},
	}}
	c := &Client{t: f, ProjectID: "proj"}

	if err := c.StartInstall(context.Background(), InstallParams{
		Zone:      "fr-par-1",
		ServerID:  7,
		OS:        OSChoice{ID: 2, RequiresUser: true, AllowSSHKeys: true, AllowCustomPartitioning: true},
		Hostname:  "node-0",
		UserLogin: "tuist",
		SSHKeyIDs: []string{"key-abc"},
	}); err != nil {
		t.Fatalf("StartInstall: %v", err)
	}
	if len(f.posts) != 1 || f.posts[0].path != "/dedibox/v1/zones/fr-par-1/servers/7/install" {
		t.Fatalf("expected one POST to the install path, got %+v", f.posts)
	}
	body, ok := f.posts[0].body.(installBody)
	if !ok {
		t.Fatalf("post body is not an installBody: %T", f.posts[0].body)
	}
	if len(body.SSHKeyIDs) != 1 || body.SSHKeyIDs[0] != "key-abc" {
		t.Fatalf("install did not authorize the fleet key: %+v", body.SSHKeyIDs)
	}
	if body.UserLogin != "tuist" {
		t.Fatalf("install did not set the user login")
	}
	if body.UserPassword == "" {
		t.Fatalf("install must set a user password when the OS RequiresUser")
	}
	if body.RootPassword != "" {
		t.Fatalf("install must leave root_password blank for a user-login OS (the API rejects it): %q", body.RootPassword)
	}
	if len(body.Partitions) != 1 {
		t.Fatalf("install did not carry the default partitioning: %+v", body.Partitions)
	}
}

func TestInstallStateInstalledIsDone(t *testing.T) {
	f := &fakeTransport{gets: map[string]any{
		"/dedibox/v1/zones/fr-par-1/servers/7/install": scwdedibox.ServerInstall{Status: scwdedibox.ServerInstallStatusInstalled},
	}}
	c := &Client{t: f, ProjectID: "proj"}

	got, err := c.InstallState(context.Background(), "fr-par-1", 7)
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallDone {
		t.Fatalf("InstallState = %v, want InstallDone", got)
	}
}

func TestInstallStateInstallingIsRunning(t *testing.T) {
	f := &fakeTransport{gets: map[string]any{
		"/dedibox/v1/zones/fr-par-1/servers/7/install": scwdedibox.ServerInstall{Status: scwdedibox.ServerInstallStatusInstalling},
	}}
	c := &Client{t: f, ProjectID: "proj"}

	got, err := c.InstallState(context.Background(), "fr-par-1", 7)
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallRunning {
		t.Fatalf("InstallState = %v, want InstallRunning", got)
	}
}

func TestInstallStateNoInstallResourceBareIsPending(t *testing.T) {
	// install path 404s; the server carries no OS = never installed.
	f := &fakeTransport{gets: map[string]any{
		"/dedibox/v1/zones/fr-par-1/servers/7": scwdedibox.Server{Zone: "fr-par-1", ID: 7},
	}}
	c := &Client{t: f, ProjectID: "proj"}

	got, err := c.InstallState(context.Background(), "fr-par-1", 7)
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallPending {
		t.Fatalf("InstallState = %v, want InstallPending (bare server)", got)
	}
}

func TestInstallStateNoInstallResourceInstalledIsDone(t *testing.T) {
	// install path 404s; the server carries an OS = installed-and-booted.
	f := &fakeTransport{gets: map[string]any{
		"/dedibox/v1/zones/fr-par-1/servers/7": scwdedibox.Server{Zone: "fr-par-1", ID: 7, Os: &scwdedibox.OS{Name: "Ubuntu"}},
	}}
	c := &Client{t: f, ProjectID: "proj"}

	got, err := c.InstallState(context.Background(), "fr-par-1", 7)
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallDone {
		t.Fatalf("InstallState = %v, want InstallDone (server carries an OS)", got)
	}
}

func TestPublicIPv4(t *testing.T) {
	ifaces := []*scwdedibox.NetworkInterface{{IPs: []*scwdedibox.IP{
		{Version: scwdedibox.IPVersionIPv6, Address: net.ParseIP("2001:db8::1")},
		{Version: scwdedibox.IPVersionIPv4, Semantic: scwdedibox.IPSemanticPublic, Address: net.ParseIP("195.154.165.232")},
	}}}
	if got := publicIPv4(ifaces); got != "195.154.165.232" {
		t.Fatalf("publicIPv4 = %q, want 195.154.165.232", got)
	}
}

func TestIsNotFound(t *testing.T) {
	if !IsNotFound(&apiError{status: 404}) {
		t.Fatal("IsNotFound(404) = false, want true")
	}
	if IsNotFound(&apiError{status: 500}) {
		t.Fatal("IsNotFound(500) = true, want false")
	}
}

func TestFailoverIPByAddress(t *testing.T) {
	f := &fakeTransport{gets: map[string]any{
		"/dedibox/v1/zones/fr-par-1/failover-ips": map[string]any{
			"failover_ips": []any{
				map[string]any{"id": 42, "address": "203.0.113.10", "server_id": 100, "server_zone": "fr-par-1"},
			},
		},
	}}
	c := &Client{t: f, ProjectID: "proj"}
	fip, zone, err := c.FailoverIPByAddress(context.Background(), []string{"fr-par-2", "fr-par-1"}, "203.0.113.10")
	if err != nil {
		t.Fatal(err)
	}
	if zone != "fr-par-1" || fip.ID != 42 || fip.Address.String() != "203.0.113.10" {
		t.Fatalf("got zone=%q id=%d addr=%s", zone, fip.ID, fip.Address)
	}
	if fip.ServerID == nil || *fip.ServerID != 100 {
		t.Fatalf("server id = %v", fip.ServerID)
	}
}

func TestAttachFailoverIP(t *testing.T) {
	f := &fakeTransport{}
	c := &Client{t: f, ProjectID: "proj"}
	if err := c.AttachFailoverIP(context.Background(), "fr-par-1", 200, 42); err != nil {
		t.Fatal(err)
	}
	if len(f.posts) != 1 || f.posts[0].path != "/dedibox/v1/zones/fr-par-1/failover-ips/attach" {
		t.Fatalf("attach posts = %+v", f.posts)
	}
	b, _ := json.Marshal(f.posts[0].body)
	if string(b) != `{"server_id":200,"fips_ids":[42]}` {
		t.Fatalf("attach body = %s", b)
	}
}
