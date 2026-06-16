package scaleway

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"

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

// NewInstanceClientFromEnv builds an InstanceClient with the same env/profile
// auth the Apple Silicon NewClient uses, for wiring in the manager.
func NewInstanceClientFromEnv() (*InstanceClient, error) {
	if cfg, err := scw.LoadConfig(); err == nil {
		if profile, perr := cfg.GetActiveProfile(); perr == nil {
			client, cerr := scw.NewClient(scw.WithProfile(profile), scw.WithEnv())
			if cerr != nil {
				return nil, fmt.Errorf("scaleway client: %w", cerr)
			}
			return NewInstanceClient(client), nil
		}
	}
	client, err := scw.NewClient(scw.WithEnv())
	if err != nil {
		return nil, fmt.Errorf("scaleway client: %w", err)
	}
	return NewInstanceClient(client), nil
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

// CreateInstance orders the server (root volume from the resolved image) and
// sets the bootstrap cloud-init as user-data. It deliberately stops short of
// attaching the Private Network and powering on: those are separate idempotent
// steps (EnsurePrivateNIC, EnsurePoweredOn) the reconciler drives once the
// server's ID is recorded, so a failure after create (e.g. a PN-attach IAM
// denial) is retried instead of stranding a half-configured paid server.
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
		// A dynamic public IPv4 so cloud-init can pull kubelet/containerd and
		// the node can reach the externally-managed (Hetzner) control plane to
		// register. Cache traffic still rides the Private Network; only the
		// join path and image pulls use the public IP.
		DynamicIPRequired: scw.BoolPtr(true),
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

	return server, nil
}

// EnsurePrivateNIC attaches the server to the Private Network unless a NIC on
// that PN already exists. Idempotent, so a reconcile that re-finds a server
// whose attach previously failed retries it without duplicating the NIC.
func (c *InstanceClient) EnsurePrivateNIC(ctx context.Context, zone scw.Zone, server *instance.Server, privateNetworkID string) error {
	if privateNetworkID == "" {
		return nil
	}
	for _, n := range server.PrivateNics {
		if n.PrivateNetworkID == privateNetworkID {
			return nil
		}
	}
	if _, err := c.Instance.CreatePrivateNIC(&instance.CreatePrivateNICRequest{
		Zone:             zone,
		ServerID:         server.ID,
		PrivateNetworkID: privateNetworkID,
	}, scw.WithContext(ctx)); err != nil {
		return fmt.Errorf("attach private network %s to %s: %w", privateNetworkID, server.ID, err)
	}
	return nil
}

// EnsurePoweredOn issues a poweron unless the server is already running or
// starting. Idempotent: Scaleway rejects poweron outside a stopped state, so
// gating on State keeps a retried provision from erroring on a live server.
func (c *InstanceClient) EnsurePoweredOn(ctx context.Context, zone scw.Zone, server *instance.Server) error {
	switch server.State {
	case instance.ServerStateRunning, instance.ServerStateStarting:
		return nil
	}
	if _, err := c.Instance.ServerAction(&instance.ServerActionRequest{
		Zone:     zone,
		ServerID: server.ID,
		Action:   instance.ServerActionPoweron,
	}, scw.WithContext(ctx)); err != nil {
		return fmt.Errorf("power on %s: %w", server.ID, err)
	}
	return nil
}

// GetServer fetches the current server state.
func (c *InstanceClient) GetServer(ctx context.Context, zone scw.Zone, serverID string) (*instance.Server, error) {
	resp, err := c.Instance.GetServer(&instance.GetServerRequest{Zone: zone, ServerID: serverID}, scw.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("get server %s: %w", serverID, err)
	}
	return resp.Server, nil
}

// DeleteInstance tears the server down across the stop→delete transition,
// returning done=true only once the server is gone. It's a small state machine
// the caller re-drives on requeue: a running server is powered off (Scaleway
// rejects DeleteServer on a live server), an in-flight stop just requeues, a
// stopped server is deleted. An already-absent server (or one that 404s mid
// stop) counts as done, so a CR whose instance was removed out of band — or
// whose poweroff already ran — releases its finalizer instead of wedging.
func (c *InstanceClient) DeleteInstance(ctx context.Context, zone scw.Zone, serverID string) (bool, error) {
	server, err := c.GetServer(ctx, zone, serverID)
	if err != nil {
		if isNotFound(err) {
			return true, nil
		}
		return false, err
	}

	switch server.State {
	case instance.ServerStateStopped, instance.ServerStateStoppedInPlace:
		if delErr := c.Instance.DeleteServer(&instance.DeleteServerRequest{Zone: zone, ServerID: serverID}, scw.WithContext(ctx)); delErr != nil {
			if isNotFound(delErr) {
				return true, nil
			}
			return false, fmt.Errorf("delete server %s: %w", serverID, delErr)
		}
		return true, nil
	case instance.ServerStateStopping:
		return false, nil
	default:
		if _, actErr := c.Instance.ServerAction(&instance.ServerActionRequest{
			Zone:     zone,
			ServerID: serverID,
			Action:   instance.ServerActionPoweroff,
		}, scw.WithContext(ctx)); actErr != nil {
			return false, fmt.Errorf("power off %s: %w", serverID, actErr)
		}
		return false, nil
	}
}

// isNotFound reports whether a Scaleway SDK error is a 404 / resource-not-found,
// the signal that a server is already gone.
func isNotFound(err error) bool {
	var notFound *scw.ResourceNotFoundError
	if errors.As(err, &notFound) {
		return true
	}
	var respErr *scw.ResponseError
	if errors.As(err, &respErr) {
		return respErr.StatusCode == http.StatusNotFound
	}
	return false
}

// PrivateNetworkIP returns the IPAM-assigned address of the server's NIC on
// the given Private Network (without the CIDR suffix), or "" if not yet
// assigned. Used for the node's tuist.dev/pn-ipv4 label.
func (c *InstanceClient) PrivateNetworkIP(ctx context.Context, server *instance.Server, privateNetworkID string) (string, error) {
	// Filter by the Private Network only: the IPAM API requires exactly one of
	// Zonal/PrivateNetworkID/SubnetID, so the original Zonal+PN combination was
	// rejected and returned nothing.
	resp, err := c.IPAM.ListIPs(&ipam.ListIPsRequest{
		PrivateNetworkID: &privateNetworkID,
		ProjectID:        &c.ProjectID,
	}, scw.WithContext(ctx))
	if err != nil {
		return "", fmt.Errorf("list IPAM IPs for PN %s: %w", privateNetworkID, err)
	}

	// Match this server's IPAM row by the resource name (Scaleway sets the PN
	// DNS record to the server name) or any of its NIC MACs, then return the
	// IPv4. Both are needed because GetServer doesn't always populate
	// PrivateNics, and when it does the Instance API reports the MAC lowercase
	// while IPAM stores it uppercase; the NIC also carries an IPv6 to skip.
	macs := map[string]bool{}
	for _, n := range server.PrivateNics {
		if n.PrivateNetworkID == privateNetworkID {
			macs[strings.ToLower(n.MacAddress)] = true
		}
	}
	for _, ip := range resp.IPs {
		if ip.Resource == nil {
			continue
		}
		nameMatch := ip.Resource.Name != nil && *ip.Resource.Name == server.Name
		macMatch := ip.Resource.MacAddress != nil && macs[strings.ToLower(*ip.Resource.MacAddress)]
		if !nameMatch && !macMatch {
			continue
		}
		if ip.Address.IP.To4() == nil {
			continue
		}
		return ip.Address.IP.String(), nil
	}
	return "", nil
}
