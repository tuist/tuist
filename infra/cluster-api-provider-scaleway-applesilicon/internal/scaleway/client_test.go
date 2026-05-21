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

	// deleteErrors maps `<call-index> -> error` for DeleteServer; an
	// absent / nil entry returns success (Scaleway accepts the
	// immediate delete). Lets the precondition-fallback tests force
	// the typed scw.PreconditionFailedError that the SDK returns for
	// a server still inside its 24h Apple-licensing floor, then
	// observe the schedule-deletion UpdateServer call that should
	// follow.
	deleteErrors  map[int]error
	deleteCalls   int
	deletedIDs    []string
	scheduledIDs  []string

	// reinstallErrors maps `<call-index> -> error` for ReinstallServer;
	// an absent / nil entry returns success and appends to
	// reinstalledIDs. ReleaseToPool tests use this to force the
	// crash-recovery shape where a previous reinstall is still in
	// flight (TransientStateError) and confirm the second attempt
	// degrades gracefully.
	reinstallErrors map[int]error
	reinstallCalls  int
	reinstalledIDs  []string
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
			if req.ScheduleDeletion != nil && *req.ScheduleDeletion {
				f.scheduledIDs = append(f.scheduledIDs, s.ID)
			}
			return s, nil
		}
	}
	return nil, errors.New("not found")
}

func (f *fakeAppleSiliconAPI) CreateServer(*applesilicon.CreateServerRequest, ...scw.RequestOption) (*applesilicon.Server, error) {
	return nil, errors.New("CreateServer not implemented in fake")
}

func (f *fakeAppleSiliconAPI) DeleteServer(req *applesilicon.DeleteServerRequest, _ ...scw.RequestOption) error {
	f.deleteCalls++
	if err, ok := f.deleteErrors[f.deleteCalls]; ok {
		return err
	}
	f.deletedIDs = append(f.deletedIDs, req.ServerID)
	return nil
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

func TestAdoptByPrefix_Phase1Update404SkipsCandidate(t *testing.T) {
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

	srv, err := c.AdoptByPrefix(context.Background(),
		"tuist-tuist-runners-fleet-x", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err != nil {
		t.Fatalf("phase 1 404 should be race-lost, not error; got %v", err)
	}
	if srv.ID != "srv-2" {
		t.Fatalf("expected fallthrough to srv-2, got %q", srv.ID)
	}
}

func TestAdoptByPrefix_Phase1UpdateNon404SurfacesError(t *testing.T) {
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

	_, err := c.AdoptByPrefix(context.Background(),
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

func TestAdoptByPrefix_Phase1Verify404SkipsCandidate(t *testing.T) {
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

	srv, err := c.AdoptByPrefix(context.Background(),
		"tuist-tuist-runners-fleet-x", "fr-par-1", "M2-L", "macos-tahoe-26.0", "tuist-pool-")
	if err != nil {
		t.Fatalf("verify 404 should be race-lost, not error; got %v", err)
	}
	if srv.ID != "srv-2" {
		t.Fatalf("expected fallthrough to srv-2, got %q", srv.ID)
	}
}

func TestAdoptByPrefix_Phase1VerifyNon404SurfacesError(t *testing.T) {
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-pool-001"),
		},
		getErrors: map[int]error{
			1: errors.New("scaleway: 502 bad gateway"),
		},
	}
	c := newTestClient(api)

	_, err := c.AdoptByPrefix(context.Background(),
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

// --- DeleteServer fallback for the 24h billing floor ----------------------
//
// The SDK parses standard error types into their own concrete types
// inside hasResponseError — a 412 with `"type": "precondition_failed"`
// comes back as *scw.PreconditionFailedError, not as the generic
// *scw.ResponseError. An earlier version of isPreconditionFailed only
// checked the generic shape and so missed every real 412 the SDK
// returned, leaving DeleteServer to loop on the Apple 24h floor while
// the MachineDeployment sat at 0 available and gated every helm
// upgrade behind it. These tests pin the wiring so the schedule-
// deletion fallback actually fires.

func TestDeleteServer_PreconditionFailedTriggersScheduleDeletion(t *testing.T) {
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-1", "tuist-tuist-macos-fleet-0"),
		},
		deleteErrors: map[int]error{
			1: &scw.PreconditionFailedError{Precondition: "unknown_precondition", HelpMessage: "this server cannot be deleted before 2026-06-12 07:06:59"},
		},
	}
	c := newTestClient(api)

	if err := c.DeleteServer(context.Background(), "srv-1", "fr-par-1"); err != nil {
		t.Fatalf("DeleteServer: expected nil after schedule-deletion fallback, got %v", err)
	}
	if got := api.scheduledIDs; len(got) != 1 || got[0] != "srv-1" {
		t.Fatalf("expected schedule-deletion UpdateServer call for srv-1, got %v", got)
	}
}

func TestDeleteServer_ResponseError412AlsoTriggersScheduleDeletion(t *testing.T) {
	// Unparsed 412 responses (non-JSON body or unknown error type) come
	// back as the generic *scw.ResponseError. The wiring should still
	// catch this path so the fallback isn't tied to one error shape.
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-2", "tuist-tuist-macos-fleet-1"),
		},
		deleteErrors: map[int]error{
			1: &scw.ResponseError{StatusCode: 412, Status: "412 Precondition Failed"},
		},
	}
	c := newTestClient(api)

	if err := c.DeleteServer(context.Background(), "srv-2", "fr-par-1"); err != nil {
		t.Fatalf("DeleteServer: expected nil after schedule-deletion fallback, got %v", err)
	}
	if got := api.scheduledIDs; len(got) != 1 || got[0] != "srv-2" {
		t.Fatalf("expected schedule-deletion UpdateServer call for srv-2, got %v", got)
	}
}

func TestDeleteServer_PreconditionFallbackPropagatesNon404UpdateError(t *testing.T) {
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-3", "tuist-tuist-macos-fleet-2"),
		},
		deleteErrors: map[int]error{
			1: &scw.PreconditionFailedError{Precondition: "unknown_precondition"},
		},
		updateErrors: map[int]error{
			1: errors.New("scaleway: 502 bad gateway"),
		},
	}
	c := newTestClient(api)

	err := c.DeleteServer(context.Background(), "srv-3", "fr-par-1")
	if err == nil {
		t.Fatalf("expected schedule-deletion failure to be surfaced")
	}
	if !strings.Contains(err.Error(), "schedule deletion") {
		t.Fatalf("expected error to identify the schedule-deletion fallback, got %v", err)
	}
}

func TestDeleteServer_PreconditionFallbackTreats404AsAlreadyGone(t *testing.T) {
	// Race window: a previous reconcile already scheduled the
	// deletion, the billing floor expired between reconciles, and
	// Scaleway has since removed the server. The fallback's
	// UpdateServer comes back 404 — that's a clean "already gone"
	// and should not propagate as a reconcile failure.
	api := &fakeAppleSiliconAPI{
		servers: []*applesilicon.Server{
			readyServer("srv-4", "tuist-tuist-macos-fleet-3"),
		},
		deleteErrors: map[int]error{
			1: &scw.PreconditionFailedError{Precondition: "unknown_precondition"},
		},
		updateErrors: map[int]error{
			1: &scw.ResourceNotFoundError{Resource: "server", ResourceID: "srv-4"},
		},
	}
	c := newTestClient(api)

	if err := c.DeleteServer(context.Background(), "srv-4", "fr-par-1"); err != nil {
		t.Fatalf("DeleteServer: expected nil when schedule-deletion sees 404, got %v", err)
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
	// outside the pool namespace, where AdoptByPrefix would never
	// find it again — effectively orphaning the host. Refuse loudly
	// so the caller fixes the call site (auto-order mode should call
	// DeleteServer directly, not ReleaseToPool with "").
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
