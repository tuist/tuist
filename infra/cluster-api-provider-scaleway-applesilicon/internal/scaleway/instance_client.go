package scaleway

import (
	"bytes"
	"context"
	"fmt"

	instance "github.com/scaleway/scaleway-sdk-go/api/instance/v1"
	ipam "github.com/scaleway/scaleway-sdk-go/api/ipam/v1"
	marketplace "github.com/scaleway/scaleway-sdk-go/api/marketplace/v2"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

// InstanceAPI is the slice of the Scaleway SDK's `instance.API` the Linux
// machine reconciler touches. An interface so tests drop in a fake; the
// concrete `*instance.API` satisfies it structurally.
type InstanceAPI interface {
	CreateServer(req *instance.CreateServerRequest, opts ...scw.RequestOption) (*instance.CreateServerResponse, error)
	GetServer(req *instance.GetServerRequest, opts ...scw.RequestOption) (*instance.GetServerResponse, error)
	ListServers(req *instance.ListServersRequest, opts ...scw.RequestOption) (*instance.ListServersResponse, error)
	DeleteServer(req *instance.DeleteServerRequest, opts ...scw.RequestOption) error
	ServerAction(req *instance.ServerActionRequest, opts ...scw.RequestOption) (*instance.ServerActionResponse, error)
	SetServerUserData(req *instance.SetServerUserDataRequest, opts ...scw.RequestOption) error
	CreatePrivateNIC(req *instance.CreatePrivateNICRequest, opts ...scw.RequestOption) (*instance.CreatePrivateNICResponse, error)
}

// MarketplaceAPI resolves an image label (e.g. ubuntu_noble) to a local
// image UUID for the instance's commercial type.
type MarketplaceAPI interface {
	GetLocalImageByLabel(req *marketplace.GetLocalImageByLabelRequest, opts ...scw.RequestOption) (*marketplace.LocalImage, error)
}

// IPAMAPI reads the Private-Network address Scaleway assigned the instance's
// PN NIC, which becomes the node's tuist.dev/pn-ipv4 label.
type IPAMAPI interface {
	ListIPs(req *ipam.ListIPsRequest, opts ...scw.RequestOption) (*ipam.ListIPsResponse, error)
}

// InstanceClient talks to Scaleway's Instance + Marketplace + IPAM APIs for
// the regular-Linux machine kind. Construct with NewInstanceClient; in tests
// the API fields take fakes.
type InstanceClient struct {
	Instance    InstanceAPI
	Marketplace MarketplaceAPI
	IPAM        IPAMAPI
	ProjectID   string
}

// NewInstanceClient builds an InstanceClient from an authenticated scw client.
func NewInstanceClient(client *scw.Client) *InstanceClient {
	projectID, _ := client.GetDefaultProjectID()
	return &InstanceClient{
		Instance:    instance.NewAPI(client),
		Marketplace: marketplace.NewAPI(client),
		IPAM:        ipam.NewAPI(client),
		ProjectID:   projectID,
	}
}

// CreateInstanceParams is the desired shape of one Linux instance.
type CreateInstanceParams struct {
	Name             string
	Zone             scw.Zone
	CommercialType   string
	ImageLabel       string
	RootVolumeGB     int
	PrivateNetworkID string
	CloudInit        []byte
	Tags             []string
}

// ProviderID is the foreign CAPI providerID for a Scaleway instance,
// `scaleway://instance/<zone>/<id>`. Matches the value used when the node was
// hand-joined so the Hetzner CCM never reaps it.
func ProviderID(zone scw.Zone, serverID string) string {
	return fmt.Sprintf("scaleway://instance/%s/%s", zone, serverID)
}

// FindServerByName returns the instance with the given exact name in the
// zone, or nil if none. Used for create-idempotency: the reconciler names the
// server after the Machine, so a controller restart re-finds it instead of
// ordering a duplicate.
func (c *InstanceClient) FindServerByName(ctx context.Context, zone scw.Zone, name string) (*instance.Server, error) {
	resp, err := c.Instance.ListServers(&instance.ListServersRequest{
		Zone:    zone,
		Name:    &name,
		Project: &c.ProjectID,
	}, scw.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("list servers by name %q: %w", name, err)
	}
	for _, s := range resp.Servers {
		if s.Name == name {
			return s, nil
		}
	}
	return nil, nil
}

// CreateInstance orders the server (root volume from the resolved image),
// sets the bootstrap cloud-init as user-data, attaches the Private Network,
// and powers it on. Returns the created server. Idempotent at the caller via
// FindServerByName.
func (c *InstanceClient) CreateInstance(ctx context.Context, p CreateInstanceParams) (*instance.Server, error) {
	img, err := c.Marketplace.GetLocalImageByLabel(&marketplace.GetLocalImageByLabelRequest{
		ImageLabel:     p.ImageLabel,
		Zone:           p.Zone,
		CommercialType: p.CommercialType,
	}, scw.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("resolve image %q for %s: %w", p.ImageLabel, p.CommercialType, err)
	}

	rootSize := scw.Size(uint64(p.RootVolumeGB) * uint64(scw.GB))
	created, err := c.Instance.CreateServer(&instance.CreateServerRequest{
		Zone:           p.Zone,
		Name:           p.Name,
		CommercialType: p.CommercialType,
		Image:          &img.ID,
		Project:        &c.ProjectID,
		Tags:           p.Tags,
		Volumes: map[string]*instance.VolumeServerTemplate{
			"0": {
				Boot:       scw.BoolPtr(true),
				Size:       &rootSize,
				VolumeType: instance.VolumeVolumeTypeSbsVolume,
			},
		},
	}, scw.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("create server %q: %w", p.Name, err)
	}
	server := created.Server

	if len(p.CloudInit) > 0 {
		if err := c.Instance.SetServerUserData(&instance.SetServerUserDataRequest{
			Zone:     p.Zone,
			ServerID: server.ID,
			Key:      "cloud-init",
			Content:  bytes.NewReader(p.CloudInit),
		}, scw.WithContext(ctx)); err != nil {
			return nil, fmt.Errorf("set cloud-init user-data on %s: %w", server.ID, err)
		}
	}

	if p.PrivateNetworkID != "" {
		if _, err := c.Instance.CreatePrivateNIC(&instance.CreatePrivateNICRequest{
			Zone:             p.Zone,
			ServerID:         server.ID,
			PrivateNetworkID: p.PrivateNetworkID,
		}, scw.WithContext(ctx)); err != nil {
			return nil, fmt.Errorf("attach private network %s to %s: %w", p.PrivateNetworkID, server.ID, err)
		}
	}

	if _, err := c.Instance.ServerAction(&instance.ServerActionRequest{
		Zone:     p.Zone,
		ServerID: server.ID,
		Action:   instance.ServerActionPoweron,
	}, scw.WithContext(ctx)); err != nil {
		return nil, fmt.Errorf("power on %s: %w", server.ID, err)
	}

	return server, nil
}

// GetServer fetches the current server state.
func (c *InstanceClient) GetServer(ctx context.Context, zone scw.Zone, serverID string) (*instance.Server, error) {
	resp, err := c.Instance.GetServer(&instance.GetServerRequest{Zone: zone, ServerID: serverID}, scw.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("get server %s: %w", serverID, err)
	}
	return resp.Server, nil
}

// DeleteInstance powers the server off and deletes it. Caller drains the Node
// first (CAPI handles cordon/drain on the Machine).
func (c *InstanceClient) DeleteInstance(ctx context.Context, zone scw.Zone, serverID string) error {
	if _, err := c.Instance.ServerAction(&instance.ServerActionRequest{
		Zone:     zone,
		ServerID: serverID,
		Action:   instance.ServerActionPoweroff,
	}, scw.WithContext(ctx)); err != nil {
		return fmt.Errorf("power off %s: %w", serverID, err)
	}
	if err := c.Instance.DeleteServer(&instance.DeleteServerRequest{Zone: zone, ServerID: serverID}, scw.WithContext(ctx)); err != nil {
		return fmt.Errorf("delete server %s: %w", serverID, err)
	}
	return nil
}

// PrivateNetworkIP returns the IPAM-assigned address of the server's NIC on
// the given Private Network (without the CIDR suffix), or "" if not yet
// assigned. Used for the node's tuist.dev/pn-ipv4 label.
func (c *InstanceClient) PrivateNetworkIP(ctx context.Context, server *instance.Server, privateNetworkID string) (string, error) {
	var nic *instance.PrivateNIC
	for _, n := range server.PrivateNics {
		if n.PrivateNetworkID == privateNetworkID {
			nic = n
			break
		}
	}
	if nic == nil {
		return "", nil
	}

	zonal := server.Zone.String()
	resp, err := c.IPAM.ListIPs(&ipam.ListIPsRequest{
		Zonal:            &zonal,
		PrivateNetworkID: &privateNetworkID,
		MacAddress:       &nic.MacAddress,
		ProjectID:        &c.ProjectID,
	}, scw.WithContext(ctx))
	if err != nil {
		return "", fmt.Errorf("list IPAM IPs for PN %s: %w", privateNetworkID, err)
	}
	for _, ip := range resp.IPs {
		return ip.Address.IP.String(), nil
	}
	return "", nil
}
