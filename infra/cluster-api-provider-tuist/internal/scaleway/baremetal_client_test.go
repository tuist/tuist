package scaleway

import (
	"context"
	"errors"
	"testing"

	baremetal "github.com/scaleway/scaleway-sdk-go/api/baremetal/v1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

// fakeBaremetalAPI implements BaremetalAPI; only the methods FindAdoptableServer
// and ReinstallServer touch return canned data, the rest are stubs.
type fakeBaremetalAPI struct {
	servers    []*baremetal.Server
	getServer  *baremetal.Server
	osList     []*baremetal.OS
	installReq *baremetal.InstallServerRequest
	// defaultSchema is what the offer reports as its own layout. Nil serves the
	// mirrored two-NVMe shape the cache fleet runs.
	defaultSchema *baremetal.Schema
	// validated records the schema the client asked the API to check, and
	// validateErr makes that check fail, which is how a box gets protected from
	// an install that would wipe it onto an unusable layout.
	validated   *baremetal.Schema
	validateErr error
}

func (f *fakeBaremetalAPI) GetDefaultPartitioningSchema(*baremetal.GetDefaultPartitioningSchemaRequest, ...scw.RequestOption) (*baremetal.Schema, error) {
	if f.defaultSchema != nil {
		return f.defaultSchema, nil
	}
	return mirroredDefaultSchema(), nil
}

func (f *fakeBaremetalAPI) ValidatePartitioningSchema(req *baremetal.ValidatePartitioningSchemaRequest, _ ...scw.RequestOption) error {
	f.validated = req.PartitioningSchema
	return f.validateErr
}

func (f *fakeBaremetalAPI) ListServers(*baremetal.ListServersRequest, ...scw.RequestOption) (*baremetal.ListServersResponse, error) {
	return &baremetal.ListServersResponse{Servers: f.servers, TotalCount: uint32(len(f.servers))}, nil
}

func (f *fakeBaremetalAPI) GetServer(*baremetal.GetServerRequest, ...scw.RequestOption) (*baremetal.Server, error) {
	return f.getServer, nil
}

func (f *fakeBaremetalAPI) InstallServer(req *baremetal.InstallServerRequest, _ ...scw.RequestOption) (*baremetal.Server, error) {
	f.installReq = req
	return &baremetal.Server{ID: req.ServerID}, nil
}

func (f *fakeBaremetalAPI) ListOS(*baremetal.ListOSRequest, ...scw.RequestOption) (*baremetal.ListOSResponse, error) {
	return &baremetal.ListOSResponse{Os: f.osList}, nil
}

func (f *fakeBaremetalAPI) CreateServer(*baremetal.CreateServerRequest, ...scw.RequestOption) (*baremetal.Server, error) {
	return nil, nil
}
func (f *fakeBaremetalAPI) DeleteServer(*baremetal.DeleteServerRequest, ...scw.RequestOption) (*baremetal.Server, error) {
	return nil, nil
}
func (f *fakeBaremetalAPI) GetOfferByName(*baremetal.GetOfferByNameRequest) (*baremetal.Offer, error) {
	return nil, nil
}
func (f *fakeBaremetalAPI) ListOptions(*baremetal.ListOptionsRequest, ...scw.RequestOption) (*baremetal.ListOptionsResponse, error) {
	return nil, nil
}
func (f *fakeBaremetalAPI) AddOptionServer(*baremetal.AddOptionServerRequest, ...scw.RequestOption) (*baremetal.Server, error) {
	return nil, nil
}

func installedServer(id, name string) *baremetal.Server {
	return &baremetal.Server{
		ID:      id,
		Name:    name,
		Status:  baremetal.ServerStatusReady,
		Install: &baremetal.ServerInstall{Status: baremetal.ServerInstallStatusCompleted},
	}
}

func TestFindAdoptableServer(t *testing.T) {
	notInstalled := installedServer("not-installed", "tuist-kura-em-3")
	notInstalled.Install.Status = baremetal.ServerInstallStatusInstalling
	api := &fakeBaremetalAPI{servers: []*baremetal.Server{
		installedServer("claimed", "tuist-kura-em-1"),
		installedServer("wrong-prefix", "other-fleet-2"),
		notInstalled,
		installedServer("free", "tuist-kura-em-4"),
	}}
	c := &BaremetalClient{Baremetal: api}

	got, err := c.FindAdoptableServer(context.Background(), scw.ZoneFrPar1, "tuist-kura-em-", map[string]bool{"claimed": true})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got == nil || got.ID != "free" {
		t.Fatalf("FindAdoptableServer = %+v, want free (claimed skipped, prefix + installed filtered)", got)
	}
}

func TestFindAdoptableServerExhausted(t *testing.T) {
	api := &fakeBaremetalAPI{servers: []*baremetal.Server{installedServer("only", "tuist-kura-em-1")}}
	c := &BaremetalClient{Baremetal: api}

	got, err := c.FindAdoptableServer(context.Background(), scw.ZoneFrPar1, "tuist-kura-em-", map[string]bool{"only": true})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got != nil {
		t.Fatalf("FindAdoptableServer = %+v, want nil (pool exhausted)", got)
	}
}

func TestReinstallServerResolvesOSAndReauthorizesKey(t *testing.T) {
	api := &fakeBaremetalAPI{
		getServer: &baremetal.Server{ID: "srv", Name: "tuist-kura-em-1", OfferID: "offer-1"},
		osList:    []*baremetal.OS{{ID: "os-noble", Name: "Ubuntu", Version: "24.04 LTS (Noble Numbat)"}},
	}
	c := &BaremetalClient{Baremetal: api}

	if err := c.ReinstallServer(context.Background(), scw.ZoneFrPar1, "srv", "ubuntu_noble", []string{"key-1"}); err != nil {
		t.Fatalf("ReinstallServer: %v", err)
	}
	if api.installReq == nil {
		t.Fatal("ReinstallServer: expected InstallServer to be called")
	}
	if api.installReq.OsID != "os-noble" {
		t.Fatalf("ReinstallServer OsID = %q, want os-noble", api.installReq.OsID)
	}
	if len(api.installReq.SSHKeyIDs) != 1 || api.installReq.SSHKeyIDs[0] != "key-1" {
		t.Fatalf("ReinstallServer SSHKeyIDs = %v, want [key-1]", api.installReq.SSHKeyIDs)
	}
}

// Every install has to land a separate XFS /data, and the reinstall path is how
// a released box is returned to the pool, so it is also how an already-adopted
// box gets converted.
func TestReinstallServerInstallsWithAPartitioningSchema(t *testing.T) {
	api := &fakeBaremetalAPI{
		getServer: &baremetal.Server{ID: "srv", Name: "kura-1", OfferID: "offer", Zone: scw.Zone("fr-par-2")},
		osList:    []*baremetal.OS{{ID: "os", Name: "Ubuntu", Version: "24.04 LTS"}},
	}
	c := &BaremetalClient{Baremetal: api}

	if err := c.ReinstallServer(context.Background(), scw.Zone("fr-par-2"), "srv", "ubuntu_24.04", []string{"key"}); err != nil {
		t.Fatalf("ReinstallServer: %v", err)
	}
	if api.installReq == nil || api.installReq.PartitioningSchema == nil {
		t.Fatal("reinstall posted no partitioning schema; the box would come up on the default single-root layout")
	}
	if fs := filesystemAt(api.installReq.PartitioningSchema, DataMountPoint); fs == nil ||
		fs.Format != baremetal.SchemaFilesystemFormatXfs {
		t.Fatalf("reinstall schema has no xfs /data: %+v", api.installReq.PartitioningSchema.Filesystems)
	}
	// The same schema must be the one that was checked, or the check proves
	// nothing about what gets installed.
	if api.validated != api.installReq.PartitioningSchema {
		t.Fatal("the validated schema is not the one that was installed")
	}
}

// Validation is the only pre-flight that exists before a wipe, so a schema the
// provider rejects must stop the install rather than being sent anyway.
func TestPartitioningSchemaForFailsClosedOnValidationError(t *testing.T) {
	api := &fakeBaremetalAPI{
		getServer:   &baremetal.Server{ID: "srv", Name: "kura-1", OfferID: "offer"},
		osList:      []*baremetal.OS{{ID: "os", Name: "Ubuntu", Version: "24.04 LTS"}},
		validateErr: errors.New("invalid schema"),
	}
	c := &BaremetalClient{Baremetal: api}

	err := c.ReinstallServer(context.Background(), scw.Zone("fr-par-2"), "srv", "ubuntu_24.04", []string{"key"})
	if err == nil {
		t.Fatal("expected the reinstall to fail when the schema does not validate")
	}
	if api.installReq != nil {
		t.Fatalf("a rejected schema still reached the install: %+v", api.installReq)
	}
}
