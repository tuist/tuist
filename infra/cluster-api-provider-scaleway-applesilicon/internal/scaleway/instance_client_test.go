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
	deleteServer *instance.DeleteServerRequest
}

func (f *fakeInstanceAPI) CreateServer(req *instance.CreateServerRequest, _ ...scw.RequestOption) (*instance.CreateServerResponse, error) {
	f.created = req
	return &instance.CreateServerResponse{Server: &instance.Server{ID: "srv-1", Name: req.Name, Zone: req.Zone}}, nil
}

func (f *fakeInstanceAPI) GetServer(req *instance.GetServerRequest, _ ...scw.RequestOption) (*instance.GetServerResponse, error) {
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

func TestCreateInstance_OrdersResolvesAttachesAndPowersOn(t *testing.T) {
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
	if inst.nic == nil || inst.nic.PrivateNetworkID != "pn-1" {
		t.Fatalf("expected PN attach, got %#v", inst.nic)
	}
	if len(inst.actions) != 1 || inst.actions[0] != instance.ServerActionPoweron {
		t.Fatalf("expected exactly one poweron action, got %v", inst.actions)
	}
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
