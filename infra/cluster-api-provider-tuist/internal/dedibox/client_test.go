package dedibox

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

// fakeTransport routes get by path against a canned response map (JSON
// round-tripped into the caller's out, mirroring the real transport) and
// records posts. Unmapped gets return a 404 so not-found paths are testable.
type fakeTransport struct {
	gets  map[string]any
	posts []postCall
}

type postCall struct {
	path string
	body any
}

func (f *fakeTransport) get(_ context.Context, path string, out any) error {
	v, ok := f.gets[path]
	if !ok {
		return &apiError{status: http.StatusNotFound, body: "not found: " + path}
	}
	return remarshal(out, v)
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
	if got, want := ProviderID("dc3", 12345), "dedibox://dc3/12345"; got != want {
		t.Fatalf("ProviderID = %q, want %q", got, want)
	}
}

func TestFindAdoptableServer(t *testing.T) {
	tr := &fakeTransport{gets: map[string]any{
		"/server":   []string{"/api/v1/server/1", "/api/v1/server/2", "/api/v1/server/3"},
		"/server/1": Server{ID: 1, Hostname: "tuist-kura-dedibox-1", Datacenter: "dc3"},
		"/server/2": Server{ID: 2, Hostname: "other-fleet-2", Datacenter: "dc3"},
		"/server/3": Server{ID: 3, Hostname: "tuist-kura-dedibox-3", Datacenter: "dc3"},
	}}
	c := &Client{t: tr}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{
		Datacenter:     "dc3",
		HostnamePrefix: "tuist-kura-dedibox-",
	}, map[int]bool{1: true})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got == nil || got.ID != 3 {
		t.Fatalf("FindAdoptableServer = %+v, want server 3 (1 claimed, 2 wrong prefix)", got)
	}
}

func TestFindAdoptableServerExhausted(t *testing.T) {
	tr := &fakeTransport{gets: map[string]any{
		"/server":   []string{"/api/v1/server/1"},
		"/server/1": Server{ID: 1, Hostname: "tuist-kura-dedibox-1", Datacenter: "dc3"},
	}}
	c := &Client{t: tr}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{HostnamePrefix: "tuist-kura-dedibox-"}, map[int]bool{1: true})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got != nil {
		t.Fatalf("FindAdoptableServer = %+v, want nil (pool exhausted)", got)
	}
}

func TestInstallStateNoInstallResourceMeansDone(t *testing.T) {
	// No /server/install/{id} (404) + an OS-bearing server in normal boot = Done.
	tr := &fakeTransport{gets: map[string]any{
		"/server/7": Server{ID: 7, BootMode: "normal", OS: &ServerOS{Name: "Ubuntu", Version: "24.04"}},
	}}
	c := &Client{t: tr}

	got, err := c.InstallState(context.Background(), 7)
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallDone {
		t.Fatalf("InstallState = %v, want InstallDone (installed + normal boot, no active install)", got)
	}
}

func TestInstallStateBareServerIsPending(t *testing.T) {
	tr := &fakeTransport{gets: map[string]any{
		"/server/7": Server{ID: 7, BootMode: "rescue"},
	}}
	c := &Client{t: tr}

	got, err := c.InstallState(context.Background(), 7)
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallPending {
		t.Fatalf("InstallState = %v, want InstallPending (bare server, no OS)", got)
	}
}

func TestEnsureSSHKeyIdempotent(t *testing.T) {
	tr := &fakeTransport{gets: map[string]any{
		"/user/key/ssh": []map[string]string{{"description": "kura-fleet", "key": "ssh-ed25519 AAAA"}},
	}}
	c := &Client{t: tr}

	if err := c.EnsureSSHKey(context.Background(), "kura-fleet", "ssh-ed25519 AAAA"); err != nil {
		t.Fatalf("EnsureSSHKey (present): %v", err)
	}
	if len(tr.posts) != 0 {
		t.Fatalf("EnsureSSHKey posted %d keys, want 0 (already present)", len(tr.posts))
	}

	if err := c.EnsureSSHKey(context.Background(), "new-key", "ssh-ed25519 BBBB"); err != nil {
		t.Fatalf("EnsureSSHKey (absent): %v", err)
	}
	if len(tr.posts) != 1 || tr.posts[0].path != "/user/key/ssh" {
		t.Fatalf("EnsureSSHKey: expected one POST to /user/key/ssh, got %+v", tr.posts)
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
