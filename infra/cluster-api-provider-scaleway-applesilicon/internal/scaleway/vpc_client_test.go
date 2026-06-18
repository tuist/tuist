package scaleway

import (
	"context"
	"errors"
	"testing"

	vpc "github.com/scaleway/scaleway-sdk-go/api/vpc/v2"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

type fakeVPC struct {
	list        *vpc.ListPrivateNetworksResponse
	listErr     error
	created     *vpc.PrivateNetwork
	listCalls   int
	createCalls int
	lastCreate  *vpc.CreatePrivateNetworkRequest
}

func (f *fakeVPC) ListPrivateNetworks(_ *vpc.ListPrivateNetworksRequest, _ ...scw.RequestOption) (*vpc.ListPrivateNetworksResponse, error) {
	f.listCalls++
	if f.listErr != nil {
		return nil, f.listErr
	}
	return f.list, nil
}

func (f *fakeVPC) CreatePrivateNetwork(req *vpc.CreatePrivateNetworkRequest, _ ...scw.RequestOption) (*vpc.PrivateNetwork, error) {
	f.createCalls++
	f.lastCreate = req
	return f.created, nil
}

func newVPC(f *fakeVPC) *VPCClient {
	return &VPCClient{VPC: f, ProjectID: "proj", cache: map[string]string{}}
}

func TestEnsurePN_FindsExisting(t *testing.T) {
	f := &fakeVPC{list: &vpc.ListPrivateNetworksResponse{PrivateNetworks: []*vpc.PrivateNetwork{{ID: "pn-1", Name: "kura-runner-cache"}}}}
	id, err := newVPC(f).EnsurePrivateNetworkByName(context.Background(), "fr-par", "kura-runner-cache", "172.16.0.0/22")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if id != "pn-1" {
		t.Fatalf("got %q, want pn-1", id)
	}
	if f.createCalls != 0 {
		t.Fatalf("should not create when found, got %d", f.createCalls)
	}
}

func TestEnsurePN_CreatesWhenMissing(t *testing.T) {
	f := &fakeVPC{
		list:    &vpc.ListPrivateNetworksResponse{},
		created: &vpc.PrivateNetwork{ID: "pn-new", Name: "kura-runner-cache"},
	}
	id, err := newVPC(f).EnsurePrivateNetworkByName(context.Background(), "fr-par", "kura-runner-cache", "172.16.0.0/22")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if id != "pn-new" {
		t.Fatalf("got %q, want pn-new", id)
	}
	if f.createCalls != 1 || f.lastCreate.Name != "kura-runner-cache" || f.lastCreate.ProjectID != "proj" {
		t.Fatalf("bad create: calls=%d req=%+v", f.createCalls, f.lastCreate)
	}
	if len(f.lastCreate.Subnets) != 1 || f.lastCreate.Subnets[0].String() != "172.16.0.0/22" {
		t.Fatalf("bad subnet: %+v", f.lastCreate.Subnets)
	}
}

func TestEnsurePN_ExactMatchOnly(t *testing.T) {
	// List returns only a substring match — must not count, must create.
	f := &fakeVPC{
		list:    &vpc.ListPrivateNetworksResponse{PrivateNetworks: []*vpc.PrivateNetwork{{ID: "pn-old", Name: "kura-runner-cache-old"}}},
		created: &vpc.PrivateNetwork{ID: "pn-new", Name: "kura-runner-cache"},
	}
	id, err := newVPC(f).EnsurePrivateNetworkByName(context.Background(), "fr-par", "kura-runner-cache", "172.16.0.0/22")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if id != "pn-new" {
		t.Fatalf("substring match should not count; got %q", id)
	}
}

func TestEnsurePN_AmbiguousErrors(t *testing.T) {
	f := &fakeVPC{list: &vpc.ListPrivateNetworksResponse{PrivateNetworks: []*vpc.PrivateNetwork{
		{ID: "pn-1", Name: "kura-runner-cache"}, {ID: "pn-2", Name: "kura-runner-cache"},
	}}}
	if _, err := newVPC(f).EnsurePrivateNetworkByName(context.Background(), "fr-par", "kura-runner-cache", "172.16.0.0/22"); err == nil {
		t.Fatal("expected ambiguous error")
	}
}

func TestEnsurePN_Caches(t *testing.T) {
	f := &fakeVPC{list: &vpc.ListPrivateNetworksResponse{PrivateNetworks: []*vpc.PrivateNetwork{{ID: "pn-1", Name: "kura-runner-cache"}}}}
	c := newVPC(f)
	for i := 0; i < 3; i++ {
		if _, err := c.EnsurePrivateNetworkByName(context.Background(), "fr-par", "kura-runner-cache", "172.16.0.0/22"); err != nil {
			t.Fatalf("call %d: %v", i, err)
		}
	}
	if f.listCalls != 1 {
		t.Fatalf("want 1 list (cached after), got %d", f.listCalls)
	}
}

func TestEnsurePN_ListErrorPropagates(t *testing.T) {
	f := &fakeVPC{listErr: errors.New("boom")}
	if _, err := newVPC(f).EnsurePrivateNetworkByName(context.Background(), "fr-par", "kura-runner-cache", "172.16.0.0/22"); err == nil {
		t.Fatal("expected list error to propagate")
	}
}

func TestRegionFromZone(t *testing.T) {
	if got := RegionFromZone("fr-par-1"); got != "fr-par" {
		t.Fatalf("got %q", got)
	}
	if got := RegionFromZone("nl-ams-2"); got != "nl-ams" {
		t.Fatalf("got %q", got)
	}
}
