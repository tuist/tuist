package scaleway

import (
	"context"
	"net"
	"testing"

	instance "github.com/scaleway/scaleway-sdk-go/api/instance/v1"
	ipam "github.com/scaleway/scaleway-sdk-go/api/ipam/v1"
	marketplace "github.com/scaleway/scaleway-sdk-go/api/marketplace/v2"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

type fakeInstanceAPI struct {
	created      *instance.CreateServerRequest
	userData     *instance.SetServerUserDataRequest
	nic          *instance.CreatePrivateNICRequest
	actions      []instance.ServerAction
	listServers  []*instance.Server
	getServer    *instance.Server
	getServerErr error
	deleteServer *instance.DeleteServerRequest
}

func (f *fakeInstanceAPI) CreateServer(req *instance.CreateServerRequest, _ ...scw.RequestOption) (*instance.CreateServerResponse, error) {
	f.created = req
	return &instance.CreateServerResponse{Server: &instance.Server{ID: "srv-1", Name: req.Name, Zone: req.Zone}}, nil
}

func (f *fakeInstanceAPI) GetServer(req *instance.GetServerRequest, _ ...scw.RequestOption) (*instance.GetServerResponse, error) {
	if f.getServerErr != nil {
		return nil, f.getServerErr
	}
	return &instance.GetServerResponse{Server: f.getServer}, nil
}

func (f *fakeInstanceAPI) ListServers(req *instance.ListServersRequest, _ ...scw.RequestOption) (*instance.ListServersResponse, error) {
	return &instance.ListServersResponse{Servers: f.listServers}, nil
}

func (f *fakeInstanceAPI) DeleteServer(req *instance.DeleteServerRequest, _ ...scw.RequestOption) error {
	f.deleteServer = req
	return nil
}

func (f *fakeInstanceAPI) ServerAction(req *instance.ServerActionRequest, _ ...scw.RequestOption) (*instance.ServerActionResponse, error) {
	f.actions = append(f.actions, req.Action)
	return &instance.ServerActionResponse{}, nil
}

func (f *fakeInstanceAPI) SetServerUserData(req *instance.SetServerUserDataRequest, _ ...scw.RequestOption) error {
	f.userData = req
	return nil
}

func (f *fakeInstanceAPI) CreatePrivateNIC(req *instance.CreatePrivateNICRequest, _ ...scw.RequestOption) (*instance.CreatePrivateNICResponse, error) {
	f.nic = req
	return &instance.CreatePrivateNICResponse{PrivateNic: &instance.PrivateNIC{ID: "nic-1", PrivateNetworkID: req.PrivateNetworkID}}, nil
}

type fakeMarketplaceAPI struct{ label, commercialType string }

func (f *fakeMarketplaceAPI) GetLocalImageByLabel(req *marketplace.GetLocalImageByLabelRequest, _ ...scw.RequestOption) (*marketplace.LocalImage, error) {
	f.label = req.ImageLabel
	f.commercialType = req.CommercialType
	return &marketplace.LocalImage{ID: "img-uuid"}, nil
}

type fakeIPAMAPI struct{ ips []*ipam.IP }

func (f *fakeIPAMAPI) ListIPs(req *ipam.ListIPsRequest, _ ...scw.RequestOption) (*ipam.ListIPsResponse, error) {
	return &ipam.ListIPsResponse{IPs: f.ips}, nil
}

func TestCreateInstance_OrdersAndSetsUserDataOnly(t *testing.T) {
	inst := &fakeInstanceAPI{}
	mkt := &fakeMarketplaceAPI{}
	c := &InstanceClient{Instance: inst, Marketplace: mkt, IPAM: &fakeIPAMAPI{}, ProjectID: "proj-1"}

	srv, err := c.CreateInstance(context.Background(), CreateInstanceParams{
		Name:             "kura-scw-fr-par-abc",
		Zone:             scw.ZoneFrPar1,
		CommercialType:   "PRO2-S",
		ImageLabel:       "ubuntu_noble",
		RootVolumeGB:     50,
		PrivateNetworkID: "pn-1",
		CloudInit:        []byte("#cloud-config\n"),
	})
	if err != nil {
		t.Fatal(err)
	}
	if srv.ID != "srv-1" {
		t.Fatalf("expected created server id, got %q", srv.ID)
	}
	if mkt.label != "ubuntu_noble" || mkt.commercialType != "PRO2-S" {
		t.Fatalf("expected image resolution by label+type, got %q/%q", mkt.label, mkt.commercialType)
	}
	if inst.created == nil || inst.created.Image == nil || *inst.created.Image != "img-uuid" {
		t.Fatalf("expected server created with resolved image, got %#v", inst.created)
	}
	if inst.userData == nil || inst.userData.Key != "cloud-init" {
		t.Fatalf("expected cloud-init user-data set, got %#v", inst.userData)
	}
	// PN attach and poweron are separate idempotent steps now, not part of create.
	if inst.nic != nil {
		t.Fatalf("expected no PN attach during create, got %#v", inst.nic)
	}
	if len(inst.actions) != 0 {
		t.Fatalf("expected no power actions during create, got %v", inst.actions)
	}
}

func TestEnsurePrivateNIC_AttachesWhenAbsentSkipsWhenPresent(t *testing.T) {
	inst := &fakeInstanceAPI{}
	c := &InstanceClient{Instance: inst, ProjectID: "proj-1"}

	if err := c.EnsurePrivateNIC(context.Background(), scw.ZoneFrPar1, &instance.Server{ID: "srv-1"}, "pn-1"); err != nil {
		t.Fatal(err)
	}
	if inst.nic == nil || inst.nic.PrivateNetworkID != "pn-1" {
		t.Fatalf("expected PN attach when absent, got %#v", inst.nic)
	}

	inst.nic = nil
	attached := &instance.Server{ID: "srv-1", PrivateNics: []*instance.PrivateNIC{{ID: "nic-1", PrivateNetworkID: "pn-1"}}}
	if err := c.EnsurePrivateNIC(context.Background(), scw.ZoneFrPar1, attached, "pn-1"); err != nil {
		t.Fatal(err)
	}
	if inst.nic != nil {
		t.Fatalf("expected no re-attach when NIC already present, got %#v", inst.nic)
	}
}

func TestEnsurePoweredOn_PowersStoppedSkipsRunning(t *testing.T) {
	inst := &fakeInstanceAPI{}
	c := &InstanceClient{Instance: inst, ProjectID: "proj-1"}

	if err := c.EnsurePoweredOn(context.Background(), scw.ZoneFrPar1, &instance.Server{ID: "srv-1", State: instance.ServerStateStopped}); err != nil {
		t.Fatal(err)
	}
	if len(inst.actions) != 1 || inst.actions[0] != instance.ServerActionPoweron {
		t.Fatalf("expected one poweron on a stopped server, got %v", inst.actions)
	}

	inst.actions = nil
	if err := c.EnsurePoweredOn(context.Background(), scw.ZoneFrPar1, &instance.Server{ID: "srv-1", State: instance.ServerStateRunning}); err != nil {
		t.Fatal(err)
	}
	if len(inst.actions) != 0 {
		t.Fatalf("expected no action on a running server, got %v", inst.actions)
	}
}

func TestDeleteInstance_StateMachine(t *testing.T) {
	ctx := context.Background()

	t.Run("running powers off and requeues", func(t *testing.T) {
		inst := &fakeInstanceAPI{getServer: &instance.Server{ID: "srv-1", State: instance.ServerStateRunning}}
		c := &InstanceClient{Instance: inst, ProjectID: "proj-1"}
		done, err := c.DeleteInstance(ctx, scw.ZoneFrPar1, "srv-1")
		if err != nil {
			t.Fatal(err)
		}
		if done {
			t.Fatal("expected not-done while powering off")
		}
		if len(inst.actions) != 1 || inst.actions[0] != instance.ServerActionPoweroff {
			t.Fatalf("expected one poweroff, got %v", inst.actions)
		}
		if inst.deleteServer != nil {
			t.Fatal("expected no delete before the server is stopped")
		}
	})

	t.Run("stopping just requeues", func(t *testing.T) {
		inst := &fakeInstanceAPI{getServer: &instance.Server{ID: "srv-1", State: instance.ServerStateStopping}}
		c := &InstanceClient{Instance: inst, ProjectID: "proj-1"}
		done, err := c.DeleteInstance(ctx, scw.ZoneFrPar1, "srv-1")
		if err != nil || done {
			t.Fatalf("expected (false,nil) while stopping, got (%v,%v)", done, err)
		}
		if len(inst.actions) != 0 || inst.deleteServer != nil {
			t.Fatal("expected no poweroff/delete while already stopping")
		}
	})

	t.Run("stopped deletes and is done", func(t *testing.T) {
		inst := &fakeInstanceAPI{getServer: &instance.Server{ID: "srv-1", State: instance.ServerStateStopped}}
		c := &InstanceClient{Instance: inst, ProjectID: "proj-1"}
		done, err := c.DeleteInstance(ctx, scw.ZoneFrPar1, "srv-1")
		if err != nil {
			t.Fatal(err)
		}
		if !done {
			t.Fatal("expected done after delete")
		}
		if len(inst.actions) != 0 {
			t.Fatalf("expected no poweroff on an already-stopped server, got %v", inst.actions)
		}
		if inst.deleteServer == nil {
			t.Fatal("expected the server to be deleted")
		}
	})

	t.Run("already gone is done", func(t *testing.T) {
		inst := &fakeInstanceAPI{getServerErr: &scw.ResourceNotFoundError{Resource: "server", ResourceID: "srv-1"}}
		c := &InstanceClient{Instance: inst, ProjectID: "proj-1"}
		done, err := c.DeleteInstance(ctx, scw.ZoneFrPar1, "srv-1")
		if err != nil {
			t.Fatal(err)
		}
		if !done {
			t.Fatal("expected done when the server is already gone")
		}
		if len(inst.actions) != 0 || inst.deleteServer != nil {
			t.Fatal("expected no actions on an absent server")
		}
	})
}

func TestFindServerByName_MatchesExact(t *testing.T) {
	inst := &fakeInstanceAPI{listServers: []*instance.Server{{ID: "srv-9", Name: "kura-x"}}}
	c := &InstanceClient{Instance: inst, ProjectID: "proj-1"}

	got, err := c.FindServerByName(context.Background(), scw.ZoneFrPar1, "kura-x")
	if err != nil {
		t.Fatal(err)
	}
	if got == nil || got.ID != "srv-9" {
		t.Fatalf("expected to find srv-9, got %#v", got)
	}

	none, err := c.FindServerByName(context.Background(), scw.ZoneFrPar1, "missing")
	if err != nil {
		t.Fatal(err)
	}
	if none != nil {
		t.Fatalf("expected nil for unknown name, got %#v", none)
	}
}

func TestPrivateNetworkIP_ReadsIPAMForTheNIC(t *testing.T) {
	server := &instance.Server{
		Zone:        scw.ZoneFrPar1,
		PrivateNics: []*instance.PrivateNIC{{ID: "nic-1", PrivateNetworkID: "pn-1", MacAddress: "de:ad:be:ef:00:01"}},
	}
	c := &InstanceClient{
		IPAM:      &fakeIPAMAPI{ips: []*ipam.IP{{Address: scw.IPNet{IPNet: net.IPNet{IP: net.ParseIP("172.16.0.2"), Mask: net.CIDRMask(22, 32)}}}}},
		ProjectID: "proj-1",
	}

	ip, err := c.PrivateNetworkIP(context.Background(), server, "pn-1")
	if err != nil {
		t.Fatal(err)
	}
	if ip != "172.16.0.2" {
		t.Fatalf("expected 172.16.0.2, got %q", ip)
	}
}
