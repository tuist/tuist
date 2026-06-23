package ovh

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/ovh/go-ovh/ovh"
)

// fakeAPI routes GetWithContext by URL against a canned response map (values
// are JSON round-tripped into the caller's resType, mirroring the real client)
// and records POSTs. Unmapped GETs return a 404 so not-found paths are testable.
type fakeAPI struct {
	get   map[string]any
	posts []postCall
}

type postCall struct {
	url  string
	body any
}

func (f *fakeAPI) GetWithContext(_ context.Context, url string, res any) error {
	v, ok := f.get[url]
	if !ok {
		return &ovh.APIError{Code: 404, Message: "not found: " + url}
	}
	return remarshal(res, v)
}

func (f *fakeAPI) PostWithContext(_ context.Context, url string, body, _ any) error {
	f.posts = append(f.posts, postCall{url: url, body: body})
	return nil
}

func (f *fakeAPI) PutWithContext(_ context.Context, _ string, _, _ any) error { return nil }
func (f *fakeAPI) DeleteWithContext(_ context.Context, _ string, _ any) error { return nil }

func remarshal(dst, src any) error {
	b, err := json.Marshal(src)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, dst)
}

func TestProviderID(t *testing.T) {
	got := ProviderID("vin", "ns123.ip-1-2-3.eu")
	want := "ovh://vin/ns123.ip-1-2-3.eu"
	if got != want {
		t.Fatalf("ProviderID = %q, want %q", got, want)
	}
}

func TestFindAdoptableServer(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server":                []string{"claimed.eu", "wrong-dc.eu", "wrong-offer.eu", "wrong-name.eu", "free.eu"},
		"/dedicated/server/claimed.eu":     Server{Name: "claimed.eu", Datacenter: "vin", CommercialRange: "Advance-3-2024"},
		"/dedicated/server/wrong-dc.eu":    Server{Name: "wrong-dc.eu", Datacenter: "hil", CommercialRange: "Advance-3-2024"},
		"/dedicated/server/wrong-offer.eu": Server{Name: "wrong-offer.eu", Datacenter: "vin", CommercialRange: "Rise-1-2024"},
		"/dedicated/server/wrong-name.eu":  Server{Name: "wrong-name.eu", Datacenter: "vin", CommercialRange: "Advance-3-2024"},
		"/dedicated/server/free.eu":        Server{Name: "free.eu", Datacenter: "vin", CommercialRange: "Advance-3-2024"},
		// Display name lives on the service layer (serviceInfos -> services).
		// wrong-name passes datacenter + offer but belongs to another fleet
		// (different display-name prefix), so the marker keeps it off this fleet.
		"/dedicated/server/wrong-name.eu/serviceInfos": serviceInfos{ServiceID: 7},
		"/services/7":                            service{Resource: serviceResource{DisplayName: "kura-us-west-1"}},
		"/dedicated/server/free.eu/serviceInfos": serviceInfos{ServiceID: 4},
		"/services/4":                            service{Resource: serviceResource{DisplayName: "kura-us-east-4"}},
	}}
	c := &Client{API: api}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{
		Datacenter:        "vin",
		Offer:             "advance-3",
		DisplayNamePrefix: "kura-us-east",
	}, map[string]bool{"claimed.eu": true})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got == nil || got.Name != "free.eu" {
		t.Fatalf("FindAdoptableServer = %+v, want free.eu (claimed/datacenter/offer/display-name filtered)", got)
	}
}

func TestFindAdoptableServerExhausted(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server":         []string{"only.eu"},
		"/dedicated/server/only.eu": Server{Name: "only.eu", Datacenter: "vin", CommercialRange: "Advance-3"},
	}}
	c := &Client{API: api}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{Datacenter: "vin"}, map[string]bool{"only.eu": true})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got != nil {
		t.Fatalf("FindAdoptableServer = %+v, want nil (pool exhausted)", got)
	}
}

func TestResolveTemplate(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server/srv/install/compatibleTemplates": map[string][]string{
			"ovh":      {"debian12_64", "ubuntu2404-server_64"},
			"personal": {},
		},
	}}
	c := &Client{API: api}

	got, err := c.ResolveTemplate(context.Background(), "srv", "ubuntu_24.04")
	if err != nil {
		t.Fatalf("ResolveTemplate: %v", err)
	}
	if got != "ubuntu2404-server_64" {
		t.Fatalf("ResolveTemplate = %q, want ubuntu2404-server_64", got)
	}

	if _, err := c.ResolveTemplate(context.Background(), "srv", "windows_2022"); err == nil {
		t.Fatal("ResolveTemplate: expected error for unmatched label")
	}
}

func TestInstallStatePicksLatestInstallTask(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server/srv/task":    []int64{10, 42, 7},
		"/dedicated/server/srv/task/10": installTask{Function: "hardReboot", Status: "done"},
		"/dedicated/server/srv/task/42": installTask{Function: "reinstallServer", Status: "doing"},
		"/dedicated/server/srv/task/7":  installTask{Function: "reinstallServer", Status: "done"},
	}}
	c := &Client{API: api}

	got, err := c.InstallState(context.Background(), "srv")
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallRunning {
		t.Fatalf("InstallState = %v, want InstallRunning (latest install task id 42 is doing; reboot task ignored)", got)
	}
}

func TestInstallStateNoTasksIsPending(t *testing.T) {
	api := &fakeAPI{get: map[string]any{"/dedicated/server/srv/task": []int64{}}}
	c := &Client{API: api}

	got, err := c.InstallState(context.Background(), "srv")
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallPending {
		t.Fatalf("InstallState = %v, want InstallPending", got)
	}
}

func TestEnsureSSHKeyIdempotent(t *testing.T) {
	api := &fakeAPI{get: map[string]any{"/me/sshKey": []string{"kura-fleet"}}}
	c := &Client{API: api}

	if err := c.EnsureSSHKey(context.Background(), "kura-fleet", "ssh-ed25519 AAAA..."); err != nil {
		t.Fatalf("EnsureSSHKey (present): %v", err)
	}
	if len(api.posts) != 0 {
		t.Fatalf("EnsureSSHKey posted %d keys, want 0 (already present)", len(api.posts))
	}

	if err := c.EnsureSSHKey(context.Background(), "new-key", "ssh-ed25519 BBBB..."); err != nil {
		t.Fatalf("EnsureSSHKey (absent): %v", err)
	}
	if len(api.posts) != 1 || api.posts[0].url != "/me/sshKey" {
		t.Fatalf("EnsureSSHKey: expected one POST to /me/sshKey, got %+v", api.posts)
	}
}

func TestIsNotFound(t *testing.T) {
	if !IsNotFound(&ovh.APIError{Code: 404}) {
		t.Fatal("IsNotFound(404) = false, want true")
	}
	if IsNotFound(&ovh.APIError{Code: 500}) {
		t.Fatal("IsNotFound(500) = true, want false")
	}
}
