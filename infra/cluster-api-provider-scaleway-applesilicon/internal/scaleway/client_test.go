package scaleway

import (
	"context"
	"errors"
	"strings"
	"testing"

	applesilicon "github.com/scaleway/scaleway-sdk-go/api/applesilicon/v1alpha1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

func TestPasswordFromVncURL(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want string
	}{
		{
			name: "empty input returns empty",
			raw:  "",
			want: "",
		},
		{
			name: "well-formed vnc URL with alphanumeric password",
			raw:  "vnc://m1:69ovyKUj4nLD@62.210.194.41:59010",
			want: "69ovyKUj4nLD",
		},
		{
			name: "password with percent-encoded special characters is decoded",
			raw:  "vnc://m1:p%40ss%3Aword@host:1234",
			want: "p@ss:word",
		},
		{
			name: "no userinfo returns empty",
			raw:  "vnc://host:1234",
			want: "",
		},
		{
			name: "user only, no password returns empty",
			raw:  "vnc://m1@host:1234",
			want: "",
		},
		{
			name: "malformed URL returns empty",
			raw:  "not a url",
			want: "",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := passwordFromVncURL(tc.raw)
			if got != tc.want {
				t.Fatalf("passwordFromVncURL(%q) = %q, want %q", tc.raw, got, tc.want)
			}
		})
	}
}

func TestScalewayServerToServer_FallsBackToVncURLWhenSudoPasswordEmpty(t *testing.T) {
	// Adopted servers come back from list/GET with an empty
	// SudoPassword; the controller needs a real password to stage
	// kcpassword. The vnc_url embeds the same OS-default credentials
	// and is the only surface that survives past CreateServer.
	in := &applesilicon.Server{
		ID:           "server-id",
		Status:       applesilicon.ServerStatusReady,
		SudoPassword: "",
		SSHUsername:  "m1",
		VncURL:       "vnc://m1:secretpwd@host:59010",
	}
	out := scalewayServerToServer(in)
	if out.SudoPassword != "secretpwd" {
		t.Fatalf("expected password to fall back to vnc_url value 'secretpwd', got %q", out.SudoPassword)
	}
}

func TestScalewayServerToServer_PrefersAPISudoPasswordWhenSet(t *testing.T) {
	// CreateServer responses populate SudoPassword directly. The vnc
	// fallback must not override that — if the API gave us a value,
	// it's the authoritative one.
	in := &applesilicon.Server{
		ID:           "server-id",
		Status:       applesilicon.ServerStatusReady,
		SudoPassword: "fromCreate",
		SSHUsername:  "m1",
		VncURL:       "vnc://m1:fromVNC@host:59010",
	}
	out := scalewayServerToServer(in)
	if out.SudoPassword != "fromCreate" {
		t.Fatalf("expected primary SudoPassword to win, got %q", out.SudoPassword)
	}
}

func TestScalewayServerToServer_LeavesPasswordEmptyWhenBothSourcesEmpty(t *testing.T) {
	in := &applesilicon.Server{
		ID:           "server-id",
		Status:       applesilicon.ServerStatusReady,
		SudoPassword: "",
		SSHUsername:  "m1",
		VncURL:       "",
	}
	out := scalewayServerToServer(in)
	if out.SudoPassword != "" {
		t.Fatalf("expected empty SudoPassword when both sources are empty, got %q", out.SudoPassword)
	}
}

// --- two-phase adoption tests ---------------------------------------------
//
// The two-phase claim in AdoptByPrefix is what keeps two concurrent
// reconciles from both walking away with the same ServerID. Test it
// against a fake Scaleway API that models the rename-store semantics
// the production code relies on. The fake is intentionally minimal:
// just enough surface to drive the candidate scan + the rename
// sequence, plus a hook to inject a concurrent rename between phase
// 1's UpdateServer and phase 1's verify GET.

// fakeAppleSiliconAPI is a small in-memory simulator. Servers are
// pointers — UpdateServer mutates them in place so subsequent GETs
// reflect the rename, matching Scaleway's own read-after-write
// semantics. Only the methods AdoptByPrefix touches are implemented;
// the rest return a sentinel error so test failures are obvious if
// a test triggers an unexpected call path.
type fakeAppleSiliconAPI struct {
	servers []*applesilicon.Server

	// beforeGet fires immediately before each GetServer responds.
	// Tests use it to mutate server state (typically: a second
	// rename) to simulate a concurrent reconcile having raced us
	// between phase 1's UpdateServer and phase 1's verify GET.
	beforeGet func(serverID string)

	// updateErrors maps `<update-call-index> -> error`. The first
	// UpdateServer call is index 1. Lets a test force a phase-2
	// failure without affecting phase 1.
	updateErrors map[int]error
	updateCalls  int
}

func (f *fakeAppleSiliconAPI) ListServers(req *applesilicon.ListServersRequest, _ ...scw.RequestOption) (*applesilicon.ListServersResponse, error) {
	// Return everything in one page. AdoptByPrefix paginates by
	// `len(resp.Servers) < pageSize` to stop, so a single full slice
	// causes the loop to exit after one pass.
	return &applesilicon.ListServersResponse{
		Servers:    f.servers,
		TotalCount: uint32(len(f.servers)),
	}, nil
}

func (f *fakeAppleSiliconAPI) GetServer(req *applesilicon.GetServerRequest, _ ...scw.RequestOption) (*applesilicon.Server, error) {
	if f.beforeGet != nil {
		f.beforeGet(req.ServerID)
	}
	for _, s := range f.servers {
		if s.ID == req.ServerID {
			return s, nil
		}
	}
	return nil, errors.New("not found")
}

func (f *fakeAppleSiliconAPI) UpdateServer(req *applesilicon.UpdateServerRequest, _ ...scw.RequestOption) (*applesilicon.Server, error) {
	f.updateCalls++
	if err, ok := f.updateErrors[f.updateCalls]; ok {
		return nil, err
	}
	for _, s := range f.servers {
		if s.ID == req.ServerID {
			if req.Name != nil {
				s.Name = *req.Name
			}
			return s, nil
		}
	}
	return nil, errors.New("not found")
}

func (f *fakeAppleSiliconAPI) CreateServer(*applesilicon.CreateServerRequest, ...scw.RequestOption) (*applesilicon.Server, error) {
	return nil, errors.New("CreateServer not implemented in fake")
}

func (f *fakeAppleSiliconAPI) DeleteServer(*applesilicon.DeleteServerRequest, ...scw.RequestOption) error {
	return errors.New("DeleteServer not implemented in fake")
}

func (f *fakeAppleSiliconAPI) WaitForServer(*applesilicon.WaitForServerRequest, ...scw.RequestOption) (*applesilicon.Server, error) {
	return nil, errors.New("WaitForServer not implemented in fake")
}

func (f *fakeAppleSiliconAPI) ListOS(*applesilicon.ListOSRequest, ...scw.RequestOption) (*applesilicon.ListOSResponse, error) {
	return nil, errors.New("ListOS not implemented in fake")
}

// readyServer builds a server in the state AdoptByPrefix is willing
// to consider — Delivered + Ready, plus the type/os filters the
// callers pass.
func readyServer(id, name string) *applesilicon.Server {
	return &applesilicon.Server{
		ID:        id,
		Name:      name,
		Status:    applesilicon.ServerStatusReady,
		Delivered: true,
		Type:      "M2-L",
		Os:        &applesilicon.OS{Name: "macos-tahoe-26.0"},
	}
}

func newTestClient(api *fakeAppleSiliconAPI) *Client {
	return &Client{API: api}
}

func TestAdoptByPrefix_HappyPath(t *testing.T) {
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-pool-001"),
		},
	}
	c := newTestClient(api)

	srv, err := c.AdoptByPrefix(context.Background(),
		"tuist-tuist-runners-fleet-abc", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err != nil {
		t.Fatalf("AdoptByPrefix returned error: %v", err)
	}
	if srv == nil || srv.ID != "srv-1" {
		t.Fatalf("expected srv-1 returned, got %+v", srv)
	}
	if got := api.servers[0].Name; got != "tuist-tuist-runners-fleet-abc" {
		t.Fatalf("expected server renamed to final claimName, got %q", got)
	}
	// Phase 1 UpdateServer + Phase 2 UpdateServer = 2 total.
	if api.updateCalls != 2 {
		t.Fatalf("expected 2 UpdateServer calls (phase 1 + phase 2), got %d", api.updateCalls)
	}
}

func TestAdoptByPrefix_IdempotentRediscovery(t *testing.T) {
	// Server already carries the final claimName from a prior
	// reconcile whose status patch was lost. Adoption must return it
	// immediately without going through the two-phase dance again
	// (which would rename to a fresh pending marker and burn API
	// calls on an already-claimed host).
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-tuist-runners-fleet-abc"),
		},
	}
	c := newTestClient(api)

	srv, err := c.AdoptByPrefix(context.Background(),
		"tuist-tuist-runners-fleet-abc", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err != nil {
		t.Fatalf("expected idempotent rediscovery, got error: %v", err)
	}
	if srv.ID != "srv-1" {
		t.Fatalf("expected srv-1, got %+v", srv)
	}
	if api.updateCalls != 0 {
		t.Fatalf("expected zero UpdateServer calls on rediscovery, got %d", api.updateCalls)
	}
}

func TestAdoptByPrefix_RaceLost_SkipsCandidate(t *testing.T) {
	// Two pool hosts. A concurrent reconcile overwrites our phase-1
	// pending marker on srv-1 between our UpdateServer and our GET.
	// AdoptByPrefix should detect the race (verify.Name != ours) and
	// move on to srv-2, where there's no contention.
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-pool-001"),
			readyServer("srv-2", "tuist-pool-002"),
		},
	}
	// Only mutate the FIRST GetServer (the verify on srv-1).
	var getCalls int
	api.beforeGet = func(id string) {
		getCalls++
		if getCalls == 1 && id == "srv-1" {
			// Simulate a concurrent reconcile that claimed srv-1
			// after our phase 1 UpdateServer landed — they overwrote
			// our pending marker with their own.
			api.servers[0].Name = claimPendingPrefix + "competitor"
		}
	}
	c := newTestClient(api)

	srv, err := c.AdoptByPrefix(context.Background(),
		"tuist-tuist-runners-fleet-mine", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err != nil {
		t.Fatalf("AdoptByPrefix returned error: %v", err)
	}
	if srv.ID != "srv-2" {
		t.Fatalf("expected adoption to skip srv-1 and pick srv-2, got %q", srv.ID)
	}
	// srv-1's name is whatever the competitor wrote; we must not have
	// promoted it to our claimName.
	if api.servers[0].Name == "tuist-tuist-runners-fleet-mine" {
		t.Fatalf("phase 2 must not promote srv-1 when phase 1 verify failed")
	}
	if api.servers[1].Name != "tuist-tuist-runners-fleet-mine" {
		t.Fatalf("expected srv-2 to be renamed to our claimName, got %q", api.servers[1].Name)
	}
}

func TestAdoptByPrefix_OrphanReAdopted(t *testing.T) {
	// A previous reconcile crashed between phase 1 and phase 2 —
	// srv-1 sits outside any pool prefix, named only by a stale
	// claim-pending marker. The next reconcile must treat that marker
	// as an eligible candidate and re-adopt cleanly.
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", claimPendingPrefix+"crashed-uuid"),
		},
	}
	c := newTestClient(api)

	srv, err := c.AdoptByPrefix(context.Background(),
		"tuist-tuist-runners-fleet-recovered", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err != nil {
		t.Fatalf("orphan re-adoption returned error: %v", err)
	}
	if srv.ID != "srv-1" {
		t.Fatalf("expected srv-1 re-adopted, got %+v", srv)
	}
	if api.servers[0].Name != "tuist-tuist-runners-fleet-recovered" {
		t.Fatalf("expected orphan renamed to our claimName, got %q", api.servers[0].Name)
	}
}

func TestAdoptByPrefix_NoEligibleHosts(t *testing.T) {
	cases := []struct {
		name string
		srv  *applesilicon.Server
	}{
		{
			name: "wrong prefix",
			srv: &applesilicon.Server{
				ID: "srv-1", Name: "unrelated-host",
				Status: applesilicon.ServerStatusReady, Delivered: true,
				Type: "M2-L", Os: &applesilicon.OS{Name: "macos-tahoe-26.0"},
			},
		},
		{
			name: "not delivered",
			srv: &applesilicon.Server{
				ID: "srv-1", Name: "tuist-pool-001",
				Status: applesilicon.ServerStatusReady, Delivered: false,
				Type: "M2-L", Os: &applesilicon.OS{Name: "macos-tahoe-26.0"},
			},
		},
		{
			name: "not ready",
			srv: &applesilicon.Server{
				ID: "srv-1", Name: "tuist-pool-001",
				Status: applesilicon.ServerStatusStarting, Delivered: true,
				Type: "M2-L", Os: &applesilicon.OS{Name: "macos-tahoe-26.0"},
			},
		},
		{
			name: "wrong type",
			srv: &applesilicon.Server{
				ID: "srv-1", Name: "tuist-pool-001",
				Status: applesilicon.ServerStatusReady, Delivered: true,
				Type: "M1-M", Os: &applesilicon.OS{Name: "macos-tahoe-26.0"},
			},
		},
		{
			name: "wrong os",
			srv: &applesilicon.Server{
				ID: "srv-1", Name: "tuist-pool-001",
				Status: applesilicon.ServerStatusReady, Delivered: true,
				Type: "M2-L", Os: &applesilicon.OS{Name: "macos-sonoma-14"},
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			api := &fakeAppleSiliconAPI{servers: []*applesilicon.Server{tc.srv}}
			c := newTestClient(api)
			_, err := c.AdoptByPrefix(context.Background(),
				"tuist-tuist-runners-fleet-x", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
			if !errors.Is(err, ErrNoAvailableHost) {
				t.Fatalf("expected ErrNoAvailableHost, got %v", err)
			}
			if api.updateCalls != 0 {
				t.Fatalf("expected no UpdateServer calls on ineligible candidate, got %d", api.updateCalls)
			}
		})
	}
}

func TestAdoptByPrefix_Phase2FailureSurfacesError(t *testing.T) {
	// Phase 1 succeeds (the candidate is renamed to our pending
	// marker), then phase 2 fails. The function must propagate the
	// error so the caller requeues; the server is left in the
	// claim-pending state so the next reconcile re-adopts it via the
	// orphan path covered above.
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-pool-001"),
		},
		updateErrors: map[int]error{
			// 1 = phase-1 UpdateServer (succeeds)
			// 2 = phase-2 UpdateServer (fail this one)
			2: errors.New("scaleway transient error"),
		},
	}
	c := newTestClient(api)

	_, err := c.AdoptByPrefix(context.Background(),
		"tuist-tuist-runners-fleet-x", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err == nil {
		t.Fatalf("expected phase-2 error to be surfaced, got nil")
	}
	if !strings.Contains(err.Error(), "promote claim") {
		t.Fatalf("expected error to mention claim promotion, got %v", err)
	}
	// Server should be stuck at the pending marker, NOT at the final
	// claimName. The next reconcile will see it as an orphan and
	// re-adopt.
	if !strings.HasPrefix(api.servers[0].Name, claimPendingPrefix) {
		t.Fatalf("expected server to be left in claim-pending state after phase-2 failure, got name=%q",
			api.servers[0].Name)
	}
}

func TestAdoptByPrefix_RequiresPoolPrefix(t *testing.T) {
	api := &fakeAppleSiliconAPI{}
	c := newTestClient(api)
	_, err := c.AdoptByPrefix(context.Background(),
		"tuist-tuist-runners-fleet-x", "fr-par-1", "M2-L", "macos-tahoe-26.0", "")
	if err == nil {
		t.Fatalf("expected error when poolPrefix is empty")
	}
	if !strings.Contains(err.Error(), "poolPrefix") {
		t.Fatalf("expected error to mention poolPrefix, got %v", err)
	}
}
