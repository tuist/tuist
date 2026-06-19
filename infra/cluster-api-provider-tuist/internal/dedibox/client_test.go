package dedibox

import (
	"context"
	"net"
	"testing"

	scwdedibox "github.com/scaleway/scaleway-sdk-go/api/dedibox/v1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

// fakeAPI is an in-memory stand-in for the Scaleway Dedibox SDK API. ListServers
// honours the ProjectID filter so the project (environment) boundary is
// exercised; GetServer / GetServerInstall 404 on unknown IDs.
type fakeAPI struct {
	servers      map[scw.Zone][]*scwdedibox.ServerSummary
	serverDetail map[uint64]*scwdedibox.Server
	osList       []*scwdedibox.OS
	install      map[uint64]*scwdedibox.ServerInstall
	installCalls []*scwdedibox.InstallServerRequest
}

func (f *fakeAPI) ListServers(req *scwdedibox.ListServersRequest, _ ...scw.RequestOption) (*scwdedibox.ListServersResponse, error) {
	var out []*scwdedibox.ServerSummary
	for _, s := range f.servers[req.Zone] {
		if req.ProjectID != nil && s.ProjectID != *req.ProjectID {
			continue
		}
		out = append(out, s)
	}
	return &scwdedibox.ListServersResponse{Servers: out, TotalCount: uint32(len(out))}, nil
}

func (f *fakeAPI) GetServer(req *scwdedibox.GetServerRequest, _ ...scw.RequestOption) (*scwdedibox.Server, error) {
	if s, ok := f.serverDetail[req.ServerID]; ok {
		return s, nil
	}
	return nil, &scw.ResourceNotFoundError{Resource: "server"}
}

func (f *fakeAPI) ListOS(_ *scwdedibox.ListOSRequest, _ ...scw.RequestOption) (*scwdedibox.ListOSResponse, error) {
	return &scwdedibox.ListOSResponse{Os: f.osList, TotalCount: uint32(len(f.osList))}, nil
}

func (f *fakeAPI) GetServerDefaultPartitioning(_ *scwdedibox.GetServerDefaultPartitioningRequest, _ ...scw.RequestOption) (*scwdedibox.ServerDefaultPartitioning, error) {
	return &scwdedibox.ServerDefaultPartitioning{}, nil
}

func (f *fakeAPI) InstallServer(req *scwdedibox.InstallServerRequest, _ ...scw.RequestOption) (*scwdedibox.ServerInstall, error) {
	f.installCalls = append(f.installCalls, req)
	return &scwdedibox.ServerInstall{}, nil
}

func (f *fakeAPI) GetServerInstall(req *scwdedibox.GetServerInstallRequest, _ ...scw.RequestOption) (*scwdedibox.ServerInstall, error) {
	if inst, ok := f.install[req.ServerID]; ok {
		return inst, nil
	}
	return nil, &scw.ResourceNotFoundError{Resource: "install"}
}

func TestProviderID(t *testing.T) {
	if got, want := ProviderID("fr-par-1", 75839), "dedibox://fr-par-1/75839"; got != want {
		t.Fatalf("ProviderID = %q, want %q", got, want)
	}
}

func TestFindAdoptableServer(t *testing.T) {
	f := &fakeAPI{servers: map[scw.Zone][]*scwdedibox.ServerSummary{
		scw.ZoneFrPar1: {
			{ID: 1, OfferName: "Start-1-M-SSD", DatacenterName: "DC2", ProjectID: "proj", Hostname: "tuist-kura-dedibox-1"},
			{ID: 2, OfferName: "Other-Offer", DatacenterName: "DC2", ProjectID: "proj"},
			{ID: 3, OfferName: "Start-1-M-SSD", DatacenterName: "DC2", ProjectID: "proj"},
		},
	}}
	c := &Client{API: f, ProjectID: "proj"}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{
		Datacenter: "DC2",
		Offer:      "Start-1-M-SSD",
	}, map[uint64]bool{1: true})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got == nil || got.ID != 3 {
		t.Fatalf("FindAdoptableServer = %+v, want server 3 (1 claimed, 2 wrong offer)", got)
	}
}

// TestFindAdoptableServerProjectScoped is the environment-boundary guarantee: a
// server belonging to a different project is never returned, even when it
// matches offer + datacenter, so a staging manager can't claim a prod box.
func TestFindAdoptableServerProjectScoped(t *testing.T) {
	f := &fakeAPI{servers: map[scw.Zone][]*scwdedibox.ServerSummary{
		scw.ZoneFrPar1: {
			{ID: 9, OfferName: "Start-1-M-SSD", DatacenterName: "DC2", ProjectID: "production"},
		},
	}}
	c := &Client{API: f, ProjectID: "staging"}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{Offer: "Start-1-M-SSD"}, map[uint64]bool{})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got != nil {
		t.Fatalf("FindAdoptableServer = %+v, want nil (server is in a different project)", got)
	}
}

// TestFindAdoptableServerBareBoxAdoptedDespitePrefix confirms a bare box (no
// hostname yet) is claimable even when HostnamePrefix is set, since the hostname
// filter only constrains already-installed boxes.
func TestFindAdoptableServerBareBoxAdoptedDespitePrefix(t *testing.T) {
	f := &fakeAPI{servers: map[scw.Zone][]*scwdedibox.ServerSummary{
		scw.ZoneFrPar2: {
			{ID: 11, OfferName: "Start-1-M-SSD", DatacenterName: "DC2", ProjectID: "p"},
		},
	}}
	c := &Client{API: f, ProjectID: "p"}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{
		Offer:          "Start-1-M-SSD",
		HostnamePrefix: "tuist-kura-",
	}, map[uint64]bool{})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got == nil || got.ID != 11 {
		t.Fatalf("FindAdoptableServer = %+v, want bare server 11 (not excluded by prefix)", got)
	}
}

func TestResolveOS(t *testing.T) {
	f := &fakeAPI{osList: []*scwdedibox.OS{
		{ID: 1, Name: "Debian", Version: "12"},
		{ID: 2, Name: "Ubuntu", Version: "24.04", RequiresUser: true},
	}}
	c := &Client{API: f}

	got, err := c.ResolveOS(context.Background(), "fr-par-1", 7, "ubuntu_24.04")
	if err != nil {
		t.Fatalf("ResolveOS: %v", err)
	}
	if got.ID != 2 || !got.RequiresUser {
		t.Fatalf("ResolveOS = %+v, want Ubuntu 24.04 (id 2, RequiresUser)", got)
	}
}

func TestStartInstallAuthorizesKeyAndUser(t *testing.T) {
	f := &fakeAPI{}
	c := &Client{API: f}

	if err := c.StartInstall(context.Background(), InstallParams{
		Zone:      "fr-par-1",
		ServerID:  7,
		OS:        OSChoice{ID: 2, RequiresUser: true},
		Hostname:  "node-0",
		UserLogin: "tuist",
		SSHKeyIDs: []string{"key-abc"},
	}); err != nil {
		t.Fatalf("StartInstall: %v", err)
	}
	if len(f.installCalls) != 1 {
		t.Fatalf("want 1 install call, got %d", len(f.installCalls))
	}
	req := f.installCalls[0]
	if len(req.SSHKeyIDs) != 1 || req.SSHKeyIDs[0] != "key-abc" {
		t.Fatalf("install did not authorize the fleet key: %+v", req.SSHKeyIDs)
	}
	if req.UserLogin == nil || *req.UserLogin != "tuist" {
		t.Fatalf("install did not set the user login")
	}
	if req.UserPassword == nil {
		t.Fatalf("install must set a user password when the OS RequiresUser")
	}
}

func TestInstallStateInstalledIsDone(t *testing.T) {
	f := &fakeAPI{install: map[uint64]*scwdedibox.ServerInstall{7: {Status: scwdedibox.ServerInstallStatusInstalled}}}
	c := &Client{API: f}

	got, err := c.InstallState(context.Background(), "fr-par-1", 7)
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallDone {
		t.Fatalf("InstallState = %v, want InstallDone", got)
	}
}

func TestInstallStateInstallingIsRunning(t *testing.T) {
	f := &fakeAPI{install: map[uint64]*scwdedibox.ServerInstall{7: {Status: scwdedibox.ServerInstallStatusInstalling}}}
	c := &Client{API: f}

	got, err := c.InstallState(context.Background(), "fr-par-1", 7)
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallRunning {
		t.Fatalf("InstallState = %v, want InstallRunning", got)
	}
}

func TestInstallStateNoInstallResourceBareIsPending(t *testing.T) {
	// No install resource (404) + a server with no OS = never installed.
	f := &fakeAPI{serverDetail: map[uint64]*scwdedibox.Server{7: {ID: 7}}}
	c := &Client{API: f}

	got, err := c.InstallState(context.Background(), "fr-par-1", 7)
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallPending {
		t.Fatalf("InstallState = %v, want InstallPending (bare server)", got)
	}
}

func TestInstallStateNoInstallResourceInstalledIsDone(t *testing.T) {
	// No install resource (404) + a server carrying an OS = installed-and-booted.
	f := &fakeAPI{serverDetail: map[uint64]*scwdedibox.Server{7: {ID: 7, Os: &scwdedibox.OS{Name: "Ubuntu"}}}}
	c := &Client{API: f}

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
	if !IsNotFound(&scw.ResourceNotFoundError{}) {
		t.Fatal("IsNotFound(ResourceNotFoundError) = false, want true")
	}
	if !IsNotFound(&scw.ResponseError{StatusCode: 404}) {
		t.Fatal("IsNotFound(404) = false, want true")
	}
	if IsNotFound(&scw.ResponseError{StatusCode: 500}) {
		t.Fatal("IsNotFound(500) = true, want false")
	}
}
