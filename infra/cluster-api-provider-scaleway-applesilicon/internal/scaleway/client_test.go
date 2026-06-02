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
	// and is the surface AdoptFromPool reads them from.
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
	// If Scaleway surfaces a non-empty SudoPassword on the response,
	// it's authoritative and the vnc fallback must not override it.
	in := &applesilicon.Server{
		ID:           "server-id",
		Status:       applesilicon.ServerStatusReady,
		SudoPassword: "fromAPI",
		SSHUsername:  "m1",
		VncURL:       "vnc://m1:fromVNC@host:59010",
	}
	out := scalewayServerToServer(in)
	if out.SudoPassword != "fromAPI" {
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

func TestScalewayServerToServer_FallsBackToVncURLWhenSudoPasswordIsSealed(t *testing.T) {
	// macOS Tahoe seals the OS-managed auto-login credential after
	// adopt; Scaleway returns the literal "<sealed>" marker on
	// `sudo_password` but vnc_url can still carry the real value
	// (observed empirically during a fresh adopt: top-level field
	// sealed, vnc_url returned the plaintext password).
	in := &applesilicon.Server{
		ID:           "server-id",
		Status:       applesilicon.ServerStatusReady,
		SudoPassword: SealedSecretMarker,
		SSHUsername:  "m1",
		VncURL:       "vnc://m1:realpwd@host:59010",
	}
	out := scalewayServerToServer(in)
	if out.SudoPassword != "realpwd" {
		t.Fatalf("expected vnc_url password to override <sealed>, got %q", out.SudoPassword)
	}
}

func TestScalewayServerToServer_RejectsSealedMarkerFromVncURL(t *testing.T) {
	// When the sealed window is in effect across both surfaces (post-
	// reboot, mid-reinstall), `vnc_url` either equals the marker
	// outright (URL parsing returns empty) or embeds it as the
	// password component (URL parsing surfaces it verbatim). Both
	// must resolve to empty so the controller's MissingSudoPassword
	// gate fires honestly rather than handing "<sealed>" to sudo.
	cases := []struct {
		name   string
		vncURL string
	}{
		{name: "vnc_url is the marker itself", vncURL: SealedSecretMarker},
		{name: "vnc_url embeds the marker as password", vncURL: "vnc://m1:%3Csealed%3E@host:59010"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			in := &applesilicon.Server{
				ID:           "server-id",
				Status:       applesilicon.ServerStatusReady,
				SudoPassword: SealedSecretMarker,
				SSHUsername:  "m1",
				VncURL:       tc.vncURL,
			}
			out := scalewayServerToServer(in)
			if out.SudoPassword != "" {
				t.Fatalf("expected SudoPassword to be empty when both sources carry the sealed marker, got %q", out.SudoPassword)
			}
		})
	}
}

func TestClientRebootServer_SwallowsNotFound(t *testing.T) {
	// Deletion races: the operator just removed the host via
	// ReleaseToPool's reinstall path, and a concurrent recovery
	// reboot fires against the gone serverID. NotFound should be
	// success — the host the caller wanted rebooted no longer
	// exists for them to act on.
	api := &fakeAppleSiliconAPI{
		rebootErrors: map[int]error{1: &scw.ResourceNotFoundError{Resource: "server", ResourceID: "srv-gone"}},
	}
	c := &Client{API: api}
	if err := c.RebootServer(context.Background(), "srv-gone", "fr-par-1"); err != nil {
		t.Fatalf("expected NotFound to be swallowed, got %v", err)
	}
}

func TestClientRebootServer_SwallowsTransientState(t *testing.T) {
	// Rebooting a server that's already mid-reboot/install is a
	// no-op from the caller's perspective; the typed transient-state
	// error shouldn't trigger downstream recovery.
	api := &fakeAppleSiliconAPI{
		rebootErrors: map[int]error{1: &scw.TransientStateError{Resource: "server", ResourceID: "srv-1", CurrentState: "rebooting"}},
	}
	c := &Client{API: api}
	if err := c.RebootServer(context.Background(), "srv-1", "fr-par-1"); err != nil {
		t.Fatalf("expected transient-state error to be swallowed, got %v", err)
	}
}

func TestClientRebootServer_HappyPathRecordsCall(t *testing.T) {
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{{ID: "srv-1", Status: applesilicon.ServerStatusReady}},
	}
	c := &Client{API: api}
	if err := c.RebootServer(context.Background(), "srv-1", "fr-par-1"); err != nil {
		t.Fatalf("RebootServer: %v", err)
	}
	if len(api.rebootedIDs) != 1 || api.rebootedIDs[0] != "srv-1" {
		t.Fatalf("expected one reboot of srv-1, got %v", api.rebootedIDs)
	}
}

// --- two-phase adoption tests ---------------------------------------------
//
// The two-phase claim in AdoptFromPool is what keeps two concurrent
// reconciles from both walking away with the same ServerID. Test it
// against a fake Scaleway API that models the rename-store semantics
// the production code relies on. The fake is intentionally minimal:
// just enough surface to drive the candidate scan + the rename
// sequence, plus a hook to inject a concurrent rename between phase
// 1's UpdateServer and phase 1's verify GET.

// fakeAppleSiliconAPI is a small in-memory simulator. Servers are
// pointers — UpdateServer mutates them in place so subsequent GETs
// reflect the rename, matching Scaleway's own read-after-write
// semantics. Only the methods AdoptFromPool touches are implemented;
// the rest return a sentinel error so test failures are obvious if
// a test triggers an unexpected call path.
type fakeAppleSiliconAPI struct {
	servers []*applesilicon.Server

	// beforeGet fires immediately before each GetServer responds.
	// Tests use it to mutate server state (typically: a second
	// rename) to simulate a concurrent reconcile having raced us
	// between phase 1's UpdateServer and phase 1's verify GET.
	beforeGet func(serverID string)

	// updateErrors / getErrors map `<call-index> -> error`. Call
	// indices are 1-based per method (the first UpdateServer call is
	// 1, regardless of how many GetServer calls precede it). Lets a
	// test force a specific phase or step to fail — including with a
	// scw.ResourceNotFoundError, to exercise the IsNotFound branch
	// where the caller treats the candidate as race-lost rather than
	// propagating the error.
	updateErrors map[int]error
	updateCalls  int
	getErrors    map[int]error
	getCalls     int

	// reinstallErrors maps `<call-index> -> error` for ReinstallServer;
	// an absent / nil entry returns success and appends to
	// reinstalledIDs. ReleaseToPool tests use this to force the
	// crash-recovery shape where a previous reinstall is still in
	// flight (TransientStateError) and confirm the second attempt
	// degrades gracefully.
	reinstallErrors map[int]error
	reinstallCalls  int
	reinstalledIDs  []string

	// rebootErrors / rebootedIDs mirror the reinstall shape for
	// RebootServer. Tests exercising the BootstrapFailed reboot tier
	// assert on rebootedIDs and use rebootErrors to force NotFound /
	// TransientState shapes.
	rebootErrors map[int]error
	rebootCalls  int
	rebootedIDs  []string
}

func (f *fakeAppleSiliconAPI) ListServers(req *applesilicon.ListServersRequest, _ ...scw.RequestOption) (*applesilicon.ListServersResponse, error) {
	// Return everything in one page. AdoptFromPool paginates by
	// `len(resp.Servers) < pageSize` to stop, so a single full slice
	// causes the loop to exit after one pass.
	return &applesilicon.ListServersResponse{
		Servers:    f.servers,
		TotalCount: uint32(len(f.servers)),
	}, nil
}

func (f *fakeAppleSiliconAPI) GetServer(req *applesilicon.GetServerRequest, _ ...scw.RequestOption) (*applesilicon.Server, error) {
	f.getCalls++
	if err, ok := f.getErrors[f.getCalls]; ok {
		return nil, err
	}
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

func (f *fakeAppleSiliconAPI) ReinstallServer(req *applesilicon.ReinstallServerRequest, _ ...scw.RequestOption) (*applesilicon.Server, error) {
	f.reinstallCalls++
	if err, ok := f.reinstallErrors[f.reinstallCalls]; ok {
		return nil, err
	}
	for _, s := range f.servers {
		if s.ID == req.ServerID {
			f.reinstalledIDs = append(f.reinstalledIDs, s.ID)
			s.Status = applesilicon.ServerStatusReinstalling
			return s, nil
		}
	}
	return nil, errors.New("not found")
}

func (f *fakeAppleSiliconAPI) RebootServer(req *applesilicon.RebootServerRequest, _ ...scw.RequestOption) (*applesilicon.Server, error) {
	f.rebootCalls++
	if err, ok := f.rebootErrors[f.rebootCalls]; ok {
		return nil, err
	}
	for _, s := range f.servers {
		if s.ID == req.ServerID {
			f.rebootedIDs = append(f.rebootedIDs, s.ID)
			s.Status = applesilicon.ServerStatusRebooting
			return s, nil
		}
	}
	return nil, errors.New("not found")
}

// readyServer builds a server in the state AdoptFromPool is willing
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

func TestAdoptFromPool_HappyPath(t *testing.T) {
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-pool-001"),
		},
	}
	c := newTestClient(api)

	srv, err := c.AdoptFromPool(context.Background(),
		"tuist-tuist-runners-fleet-abc", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err != nil {
		t.Fatalf("AdoptFromPool returned error: %v", err)
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

func TestAdoptFromPool_IdempotentRediscovery(t *testing.T) {
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

	srv, err := c.AdoptFromPool(context.Background(),
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

func TestAdoptFromPool_RaceLost_SkipsCandidate(t *testing.T) {
	// Two pool hosts. A concurrent reconcile overwrites our phase-1
	// pending marker on srv-1 between our UpdateServer and our GET.
	// AdoptFromPool should detect the race (verify.Name != ours) and
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

	srv, err := c.AdoptFromPool(context.Background(),
		"tuist-tuist-runners-fleet-mine", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err != nil {
		t.Fatalf("AdoptFromPool returned error: %v", err)
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

func TestAdoptFromPool_OrphanReAdopted(t *testing.T) {
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

	srv, err := c.AdoptFromPool(context.Background(),
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

func TestAdoptFromPool_NoEligibleHosts(t *testing.T) {
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
			_, err := c.AdoptFromPool(context.Background(),
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

func TestAdoptFromPool_Phase2FailureSurfacesError(t *testing.T) {
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

	_, err := c.AdoptFromPool(context.Background(),
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

func TestAdoptFromPool_RequiresPoolPrefix(t *testing.T) {
	api := &fakeAppleSiliconAPI{}
	c := newTestClient(api)
	_, err := c.AdoptFromPool(context.Background(),
		"tuist-tuist-runners-fleet-x", "fr-par-1", "M2-L", "macos-tahoe-26.0", "")
	if err == nil {
		t.Fatalf("expected error when poolPrefix is empty")
	}
	if !strings.Contains(err.Error(), "poolPrefix") {
		t.Fatalf("expected error to mention poolPrefix, got %v", err)
	}
}

func TestAdoptFromPool_Phase1Update404SkipsCandidate(t *testing.T) {
	// A 404 on phase 1 UpdateServer means the candidate was deleted
	// out from under us between list and UpdateServer (concurrent
	// operator action). The function should treat that as a per-
	// candidate race-lost and let the outer loop move on to the
	// next eligible host, NOT propagate as a real error.
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-pool-001"),
			readyServer("srv-2", "tuist-pool-002"),
		},
		// First UpdateServer call (phase 1 against srv-1) returns
		// the Scaleway-typed NotFound error; the remaining calls
		// (phase 1 + phase 2 against srv-2) succeed.
		updateErrors: map[int]error{
			1: &scw.ResourceNotFoundError{Resource: "server", ResourceID: "srv-1"},
		},
	}
	c := newTestClient(api)

	srv, err := c.AdoptFromPool(context.Background(),
		"tuist-tuist-runners-fleet-x", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err != nil {
		t.Fatalf("phase 1 404 should be race-lost, not error; got %v", err)
	}
	if srv.ID != "srv-2" {
		t.Fatalf("expected fallthrough to srv-2, got %q", srv.ID)
	}
}

func TestAdoptFromPool_Phase1UpdateNon404SurfacesError(t *testing.T) {
	// Any non-NotFound Scaleway error (403 auth, 5xx outage,
	// validation error) is operational and must propagate as a real
	// failure. The pre-fix behavior swallowed every UpdateServer
	// error as "race lost" and let the outer loop downgrade it to
	// ErrNoAvailableHost — telling operators to pre-order capacity
	// they already have.
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-pool-001"),
		},
		updateErrors: map[int]error{
			1: errors.New("scaleway: 403 forbidden"),
		},
	}
	c := newTestClient(api)

	_, err := c.AdoptFromPool(context.Background(),
		"tuist-tuist-runners-fleet-x", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err == nil {
		t.Fatalf("expected non-404 phase 1 error to be surfaced")
	}
	if errors.Is(err, ErrNoAvailableHost) {
		t.Fatalf("non-404 phase 1 error must not be downgraded to ErrNoAvailableHost, got %v", err)
	}
	if !strings.Contains(err.Error(), "phase 1 rename") {
		t.Fatalf("expected error to identify phase 1 rename, got %v", err)
	}
}

func TestAdoptFromPool_Phase1Verify404SkipsCandidate(t *testing.T) {
	// 404 on the verify GET (server deleted between phase 1 and
	// verify) is recoverable per-candidate, same handling as a phase
	// 1 update 404.
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-pool-001"),
			readyServer("srv-2", "tuist-pool-002"),
		},
		getErrors: map[int]error{
			1: &scw.ResourceNotFoundError{Resource: "server", ResourceID: "srv-1"},
		},
	}
	c := newTestClient(api)

	srv, err := c.AdoptFromPool(context.Background(),
		"tuist-tuist-runners-fleet-x", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err != nil {
		t.Fatalf("verify 404 should be race-lost, not error; got %v", err)
	}
	if srv.ID != "srv-2" {
		t.Fatalf("expected fallthrough to srv-2, got %q", srv.ID)
	}
}

func TestAdoptFromPool_Phase1VerifyNon404SurfacesError(t *testing.T) {
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-pool-001"),
		},
		getErrors: map[int]error{
			1: errors.New("scaleway: 502 bad gateway"),
		},
	}
	c := newTestClient(api)

	_, err := c.AdoptFromPool(context.Background(),
		"tuist-tuist-runners-fleet-x", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err == nil {
		t.Fatalf("expected non-404 verify error to be surfaced")
	}
	if errors.Is(err, ErrNoAvailableHost) {
		t.Fatalf("non-404 verify error must not be downgraded to ErrNoAvailableHost, got %v", err)
	}
	if !strings.Contains(err.Error(), "phase 1 verify") {
		t.Fatalf("expected error to identify phase 1 verify, got %v", err)
	}
}

// --- ReleaseToPool ---------------------------------------------------------
//
// ReleaseToPool is the cluster-driven exit for a Mac mini: rename
// back into the pool namespace and trigger an OS reinstall, leaving
// physical destruction as an out-of-band operator action. These
// tests pin the rename target shape, the reinstall side-effect, the
// crash-recovery shape (TransientStateError from a second reinstall
// while the first is still in flight), and the 404-as-success paths
// that let an operator-deleted host clean up its Machine cleanly.

func TestReleaseToPool_HappyPathRenamesAndReinstalls(t *testing.T) {
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-tuist-macos-fleet-0"),
		},
	}
	c := newTestClient(api)

	if err := c.ReleaseToPool(context.Background(), "srv-1", "fr-par-1", "tuist-pool-"); err != nil {
		t.Fatalf("ReleaseToPool: %v", err)
	}
	if got := api.servers[0].Name; !strings.HasPrefix(got, "tuist-pool-") {
		t.Fatalf("server should be renamed back into the pool namespace, got %q", got)
	}
	if got := api.reinstalledIDs; len(got) != 1 || got[0] != "srv-1" {
		t.Fatalf("expected ReinstallServer call for srv-1, got %v", got)
	}
}

func TestReleaseToPool_RejectsEmptyPoolPrefix(t *testing.T) {
	// An empty poolPrefix would rename the server to a bare UUID
	// outside the pool namespace, where AdoptFromPool would never
	// find it again — effectively orphaning the host. Refuse loudly
	// so callers fix their call site.
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{readyServer("srv-1", "tuist-tuist-macos-fleet-0")},
	}
	c := newTestClient(api)

	if err := c.ReleaseToPool(context.Background(), "srv-1", "fr-par-1", ""); err == nil {
		t.Fatal("expected ReleaseToPool to refuse empty poolPrefix")
	}
	if api.updateCalls != 0 || api.reinstallCalls != 0 {
		t.Fatalf("no Scaleway calls should fire when validation rejects the input; updates=%d reinstalls=%d",
			api.updateCalls, api.reinstallCalls)
	}
}

func TestReleaseToPool_SwallowsTransientStateOnReinstall(t *testing.T) {
	// Crash-recovery: a prior reconcile already triggered a reinstall;
	// the controller restarted, sees ServerID still set, and retries.
	// Rename succeeds (different UUID — pool happy with either name),
	// reinstall fails with TransientStateError because the server is
	// still `reinstalling`. Treat as success so the Machine finalizes
	// and the host eventually becomes ready under its pool name.
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{readyServer("srv-1", "tuist-tuist-macos-fleet-0")},
		reinstallErrors: map[int]error{
			1: &scw.TransientStateError{Resource: "server", ResourceID: "srv-1", CurrentState: "reinstalling"},
		},
	}
	c := newTestClient(api)

	if err := c.ReleaseToPool(context.Background(), "srv-1", "fr-par-1", "tuist-pool-"); err != nil {
		t.Fatalf("ReleaseToPool: expected nil on TransientStateError, got %v", err)
	}
}

func TestReleaseToPool_TreatsRename404AsAlreadyGone(t *testing.T) {
	// Operator force-deleted the host out-of-band between reconciles.
	// The rename comes back 404; nothing left to release, so return
	// success and let the controller finalize the Machine cleanly.
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{readyServer("srv-2", "tuist-tuist-macos-fleet-1")},
		updateErrors: map[int]error{
			1: &scw.ResourceNotFoundError{Resource: "server", ResourceID: "srv-2"},
		},
	}
	c := newTestClient(api)

	if err := c.ReleaseToPool(context.Background(), "srv-2", "fr-par-1", "tuist-pool-"); err != nil {
		t.Fatalf("ReleaseToPool: expected nil when rename sees 404, got %v", err)
	}
	if api.reinstallCalls != 0 {
		t.Fatalf("rename 404 means host is gone; reinstall must be skipped, got %d calls", api.reinstallCalls)
	}
}

func TestReleaseToPool_TreatsReinstall404AsAlreadyGone(t *testing.T) {
	// Race: rename lands, then operator deletes the host before
	// reinstall fires. Reinstall 404 is also "already gone".
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{readyServer("srv-3", "tuist-tuist-macos-fleet-2")},
		reinstallErrors: map[int]error{
			1: &scw.ResourceNotFoundError{Resource: "server", ResourceID: "srv-3"},
		},
	}
	c := newTestClient(api)

	if err := c.ReleaseToPool(context.Background(), "srv-3", "fr-par-1", "tuist-pool-"); err != nil {
		t.Fatalf("ReleaseToPool: expected nil when reinstall sees 404, got %v", err)
	}
}

func TestReleaseToPool_PropagatesNonRecoverableReinstallError(t *testing.T) {
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{readyServer("srv-4", "tuist-tuist-macos-fleet-3")},
		reinstallErrors: map[int]error{
			1: errors.New("scaleway: 502 bad gateway"),
		},
	}
	c := newTestClient(api)

	err := c.ReleaseToPool(context.Background(), "srv-4", "fr-par-1", "tuist-pool-")
	if err == nil {
		t.Fatal("expected non-recoverable reinstall error to surface")
	}
	if !strings.Contains(err.Error(), "reinstall server") {
		t.Fatalf("expected error to identify reinstall step, got %v", err)
	}
}
