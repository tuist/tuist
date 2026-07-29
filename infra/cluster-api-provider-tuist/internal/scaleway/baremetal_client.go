package scaleway

import (
	"context"
	"fmt"
	"strings"

	baremetal "github.com/scaleway/scaleway-sdk-go/api/baremetal/v1"
	ipam "github.com/scaleway/scaleway-sdk-go/api/ipam/v1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

// BaremetalAPI is the slice of the Scaleway SDK's baremetal `API` the Elastic
// Metal machine reconciler touches. An interface so tests drop in a fake; the
// concrete `*baremetal.API` satisfies it structurally.
type BaremetalAPI interface {
	CreateServer(req *baremetal.CreateServerRequest, opts ...scw.RequestOption) (*baremetal.Server, error)
	GetServer(req *baremetal.GetServerRequest, opts ...scw.RequestOption) (*baremetal.Server, error)
	ListServers(req *baremetal.ListServersRequest, opts ...scw.RequestOption) (*baremetal.ListServersResponse, error)
	DeleteServer(req *baremetal.DeleteServerRequest, opts ...scw.RequestOption) (*baremetal.Server, error)
	GetOfferByName(req *baremetal.GetOfferByNameRequest) (*baremetal.Offer, error)
	ListOS(req *baremetal.ListOSRequest, opts ...scw.RequestOption) (*baremetal.ListOSResponse, error)
	ListOptions(req *baremetal.ListOptionsRequest, opts ...scw.RequestOption) (*baremetal.ListOptionsResponse, error)
	AddOptionServer(req *baremetal.AddOptionServerRequest, opts ...scw.RequestOption) (*baremetal.Server, error)
	InstallServer(req *baremetal.InstallServerRequest, opts ...scw.RequestOption) (*baremetal.Server, error)
}

// BaremetalPrivateNetworkAPI is the slice of the baremetal PrivateNetwork API
// the reconciler touches (PN attachment for the runner-cache data plane).
type BaremetalPrivateNetworkAPI interface {
	ListServerPrivateNetworks(req *baremetal.PrivateNetworkAPIListServerPrivateNetworksRequest, opts ...scw.RequestOption) (*baremetal.ListServerPrivateNetworksResponse, error)
	AddServerPrivateNetwork(req *baremetal.PrivateNetworkAPIAddServerPrivateNetworkRequest, opts ...scw.RequestOption) (*baremetal.ServerPrivateNetwork, error)
}

// IPAMAPI is the slice of the SDK's IPAM API the reconciler touches to read the
// Private-Network address Scaleway assigned a server's NIC. Interface so tests
// drop in a fake.
type IPAMAPI interface {
	ListIPs(req *ipam.ListIPsRequest, opts ...scw.RequestOption) (*ipam.ListIPsResponse, error)
}

// BaremetalClient talks to Scaleway's Elastic Metal + IPAM APIs for the
// bare-metal machine kind. Construct with NewBaremetalClient; in tests the API
// fields take fakes.
type BaremetalClient struct {
	Baremetal BaremetalAPI
	PN        BaremetalPrivateNetworkAPI
	IPAM      IPAMAPI
	ProjectID string
}

// NewBaremetalClient builds a BaremetalClient from an authenticated scw client.
func NewBaremetalClient(client *scw.Client) *BaremetalClient {
	projectID, _ := client.GetDefaultProjectID()
	return &BaremetalClient{
		Baremetal: baremetal.NewAPI(client),
		PN:        baremetal.NewPrivateNetworkAPI(client),
		IPAM:      ipam.NewAPI(client),
		ProjectID: projectID,
	}
}

// NewBaremetalClientFromEnv builds a BaremetalClient with the same env/profile
// auth the other clients use, for wiring in the manager.
func NewBaremetalClientFromEnv() (*BaremetalClient, error) {
	if cfg, err := scw.LoadConfig(); err == nil {
		if profile, perr := cfg.GetActiveProfile(); perr == nil {
			client, cerr := scw.NewClient(scw.WithProfile(profile), scw.WithEnv())
			if cerr != nil {
				return nil, fmt.Errorf("scaleway client: %w", cerr)
			}
			return NewBaremetalClient(client), nil
		}
	}
	client, err := scw.NewClient(scw.WithEnv())
	if err != nil {
		return nil, fmt.Errorf("scaleway client: %w", err)
	}
	return NewBaremetalClient(client), nil
}

// BaremetalProviderID is the foreign CAPI providerID for an Elastic Metal
// server, `scaleway://baremetal/<zone>/<id>`. The distinct `baremetal` host
// keeps the Hetzner CCM from reaping the node, same as the instance kind.
func BaremetalProviderID(zone scw.Zone, serverID string) string {
	return fmt.Sprintf("scaleway://baremetal/%s/%s", zone, serverID)
}

// CreateBaremetalParams is the desired shape of one Elastic Metal server.
type CreateBaremetalParams struct {
	Name      string
	Zone      scw.Zone
	OfferType string
	OSLabel   string
	Hostname  string
	SSHKeyIDs []string
	Tags      []string
}

// FindServerByName returns the Elastic Metal server with the given exact name
// in the zone, or nil. Used for create-idempotency: the reconciler names the
// server after the Machine, so a controller restart re-finds it instead of
// ordering a duplicate (and paying for a second box mid-install).
func (c *BaremetalClient) FindServerByName(ctx context.Context, zone scw.Zone, name string) (*baremetal.Server, error) {
	resp, err := c.Baremetal.ListServers(&baremetal.ListServersRequest{
		Zone:      zone,
		Name:      &name,
		ProjectID: &c.ProjectID,
	}, scw.WithContext(ctx), scw.WithAllPages())
	if err != nil {
		return nil, fmt.Errorf("list elastic metal servers by name %q: %w", name, err)
	}
	for _, s := range resp.Servers {
		if s.Name == name {
			return s, nil
		}
	}
	return nil, nil
}

// FindAdoptableServer claims a pre-ordered Elastic Metal server for a fleet:
// the first ready + OS-installed server whose name starts with namePrefix that
// no sibling Machine has already claimed (claimed = the server IDs recorded on
// sibling CR statuses). Returns nil when the pool is exhausted so the caller
// requeues and the operator pre-orders more capacity. Claim state lives
// cluster-side (the CR status), mirroring the OVH kind: bare-metal capacity
// goes out of stock, so we never order a box inline during a reconcile/rollout.
func (c *BaremetalClient) FindAdoptableServer(ctx context.Context, zone scw.Zone, namePrefix string, claimed map[string]bool) (*baremetal.Server, error) {
	resp, err := c.Baremetal.ListServers(&baremetal.ListServersRequest{
		Zone:      zone,
		ProjectID: &c.ProjectID,
	}, scw.WithContext(ctx), scw.WithAllPages())
	if err != nil {
		return nil, fmt.Errorf("list elastic metal servers: %w", err)
	}
	for _, s := range resp.Servers {
		if claimed[s.ID] {
			continue
		}
		if namePrefix != "" && !strings.HasPrefix(s.Name, namePrefix) {
			continue
		}
		if !ServerInstalled(s) {
			continue
		}
		return s, nil
	}
	return nil, nil
}

// ReinstallServer wipes a server back to a clean, claimable state by
// reinstalling its OS — the Elastic Metal analog of the macOS ReleaseToPool.
// Used on Machine delete to RETURN the pre-ordered box to the pool rather than
// terminate it (the operator owns the pool's lifecycle). The sshKeyIDs re-author
// the fleet key so the reinstalled box is bootstrappable on its next claim. An
// absent server (deleted out of band) is treated as already released.
func (c *BaremetalClient) ReinstallServer(ctx context.Context, zone scw.Zone, serverID, osLabel string, sshKeyIDs []string) error {
	server, err := c.GetServer(ctx, zone, serverID)
	if err != nil {
		if IsNotFound(err) {
			return nil
		}
		return err
	}
	osID, err := c.resolveOS(ctx, zone, server.OfferID, osLabel)
	if err != nil {
		return err
	}
	if _, err := c.Baremetal.InstallServer(&baremetal.InstallServerRequest{
		Zone:      zone,
		ServerID:  serverID,
		OsID:      osID,
		Hostname:  server.Name,
		SSHKeyIDs: sshKeyIDs,
	}, scw.WithContext(ctx)); err != nil {
		if IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("reinstall elastic metal server %s: %w", serverID, err)
	}
	return nil
}

// CreateServer orders the Elastic Metal server and kicks off the OS install in
// one call (offer resolved from the type name, OS from the label). Unlike an
// Instance — which boots an image in minutes — a bare-metal server then spends
// ~30-60 min provisioning hardware and installing the OS before it is
// reachable, so the reconciler polls ServerInstalled before bootstrapping. The
// SSH key authorizes the controller's bootstrap user.
func (c *BaremetalClient) CreateServer(ctx context.Context, p CreateBaremetalParams) (*baremetal.Server, error) {
	offer, err := c.Baremetal.GetOfferByName(&baremetal.GetOfferByNameRequest{
		OfferName: p.OfferType,
		Zone:      p.Zone,
	})
	if err != nil {
		return nil, fmt.Errorf("resolve offer %q: %w", p.OfferType, err)
	}

	osID, err := c.resolveOS(ctx, p.Zone, offer.ID, p.OSLabel)
	if err != nil {
		return nil, err
	}

	hostname := p.Hostname
	if hostname == "" {
		hostname = p.Name
	}
	created, err := c.Baremetal.CreateServer(&baremetal.CreateServerRequest{
		Zone:      p.Zone,
		OfferID:   offer.ID,
		ProjectID: &c.ProjectID,
		Name:      p.Name,
		Tags:      p.Tags,
		Install: &baremetal.CreateServerRequestInstall{
			OsID:      osID,
			Hostname:  hostname,
			SSHKeyIDs: p.SSHKeyIDs,
		},
	}, scw.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("create elastic metal server %q: %w", p.Name, err)
	}
	return created, nil
}

// resolveOS maps an `ubuntu_noble`-style label to a baremetal OS UUID
// compatible with the offer. Baremetal has no marketplace image labels, so we
// match the label's `_`-separated tokens against the OS display name
// case-insensitively (e.g. ubuntu_noble -> "Ubuntu 24.04 LTS (Noble Numbat)").
func (c *BaremetalClient) resolveOS(ctx context.Context, zone scw.Zone, offerID, label string) (string, error) {
	resp, err := c.Baremetal.ListOS(&baremetal.ListOSRequest{Zone: zone, OfferID: &offerID}, scw.WithContext(ctx), scw.WithAllPages())
	if err != nil {
		return "", fmt.Errorf("list OS for offer %s: %w", offerID, err)
	}
	tokens := strings.Split(strings.ToLower(label), "_")
	for _, os := range resp.Os {
		name := strings.ToLower(os.Name + " " + os.Version)
		matched := true
		for _, t := range tokens {
			if t != "" && !strings.Contains(name, t) {
				matched = false
				break
			}
		}
		if matched {
			return os.ID, nil
		}
	}
	return "", fmt.Errorf("no baremetal OS matching label %q for offer %s", label, offerID)
}

// GetServer fetches the current server state.
func (c *BaremetalClient) GetServer(ctx context.Context, zone scw.Zone, serverID string) (*baremetal.Server, error) {
	server, err := c.Baremetal.GetServer(&baremetal.GetServerRequest{Zone: zone, ServerID: serverID}, scw.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("get elastic metal server %s: %w", serverID, err)
	}
	return server, nil
}

// ServerInstalled reports whether the server has finished delivery + OS
// install and is bootable — the gate the reconciler waits on before SSH
// bootstrap, since the public IP is unreachable until then.
func ServerInstalled(server *baremetal.Server) bool {
	if server.Status != baremetal.ServerStatusReady {
		return false
	}
	return server.Install != nil && server.Install.Status == baremetal.ServerInstallStatusCompleted
}

// ServerInstallFailed reports a terminal install/order failure (out of stock,
// install error) the reconciler surfaces instead of polling forever.
func ServerInstallFailed(server *baremetal.Server) bool {
	switch server.Status {
	case baremetal.ServerStatusError, baremetal.ServerStatusOutOfStock:
		return true
	}
	return server.Install != nil && server.Install.Status == baremetal.ServerInstallStatusError
}

// PublicIPv4 returns the server's first public IPv4 (for the bootstrap SSH +
// image pulls), or "" if none is assigned yet.
func PublicIPv4(server *baremetal.Server) string {
	for _, ip := range server.IPs {
		if ip != nil && ip.Address.To4() != nil {
			return ip.Address.String()
		}
	}
	return ""
}

// EnsurePrivateNetwork attaches the server to the given Private Network and
// returns the VLAN ID of the attachment — the per-host tag macos-host-bootstrap
// (and the Elastic Metal join cloud-init) needs to create the VLAN interface
// the cache traffic egresses through. Idempotent: returns the existing
// attachment's VLAN when already attached, errors while Scaleway has not yet
// assigned the VLAN so the caller retries rather than bootstrapping a host
// without the interface.
func (c *BaremetalClient) EnsurePrivateNetwork(ctx context.Context, zone scw.Zone, serverID, privateNetworkID string) (uint32, error) {
	if privateNetworkID == "" {
		return 0, nil
	}
	// Elastic Metal delivers Private Networks through a server "Private
	// Network" option that must be installed and enabled before an attachment
	// carries traffic — the analog of enabling the VPC option on the Apple
	// Silicon kind. Without it the API still allocates a VLAN + IPAM address,
	// but the host's VLAN interface stays dark (the console shows "Private
	// Networks feature: Disabled"). Install it and requeue until enabled
	// before attaching, so we never bootstrap a host onto a dead PN.
	if err := c.ensurePrivateNetworkOption(ctx, zone, serverID); err != nil {
		return 0, err
	}
	list, err := c.PN.ListServerPrivateNetworks(&baremetal.PrivateNetworkAPIListServerPrivateNetworksRequest{
		Zone:     zone,
		ServerID: &serverID,
	}, scw.WithContext(ctx), scw.WithAllPages())
	if err != nil {
		return 0, fmt.Errorf("list private networks of server %s: %w", serverID, err)
	}
	for _, attachment := range list.ServerPrivateNetworks {
		if attachment.PrivateNetworkID != privateNetworkID {
			continue
		}
		if attachment.Vlan == nil || *attachment.Vlan == 0 {
			return 0, fmt.Errorf("server %s attachment to %s has no VLAN yet (status %s)", serverID, privateNetworkID, attachment.Status)
		}
		return *attachment.Vlan, nil
	}

	created, err := c.PN.AddServerPrivateNetwork(&baremetal.PrivateNetworkAPIAddServerPrivateNetworkRequest{
		Zone:             zone,
		ServerID:         serverID,
		PrivateNetworkID: privateNetworkID,
	}, scw.WithContext(ctx))
	if err != nil {
		return 0, fmt.Errorf("attach server %s to private network %s: %w", serverID, privateNetworkID, err)
	}
	if created.Vlan == nil || *created.Vlan == 0 {
		return 0, fmt.Errorf("server %s attachment to %s has no VLAN yet (status %s)", serverID, privateNetworkID, created.Status)
	}
	return *created.Vlan, nil
}

// ensurePrivateNetworkOption makes sure the server's "Private Network" option
// is installed and enabled, installing it (idempotently) and returning an error
// to requeue while it is missing or still enabling. The option is identified by
// its typed `PrivateNetwork` field rather than its display name.
func (c *BaremetalClient) ensurePrivateNetworkOption(ctx context.Context, zone scw.Zone, serverID string) error {
	server, err := c.Baremetal.GetServer(&baremetal.GetServerRequest{Zone: zone, ServerID: serverID}, scw.WithContext(ctx))
	if err != nil {
		return fmt.Errorf("get server %s: %w", serverID, err)
	}
	for _, o := range server.Options {
		if o.PrivateNetwork == nil {
			continue
		}
		if o.Status == baremetal.ServerOptionOptionStatusOptionStatusEnable {
			return nil
		}
		return fmt.Errorf("server %s Private Network option not enabled yet (status %s)", serverID, o.Status)
	}
	resp, err := c.Baremetal.ListOptions(&baremetal.ListOptionsRequest{Zone: zone, OfferID: &server.OfferID}, scw.WithContext(ctx), scw.WithAllPages())
	if err != nil {
		return fmt.Errorf("list options for offer %s: %w", server.OfferID, err)
	}
	var optionID string
	for _, o := range resp.Options {
		if o.PrivateNetwork != nil {
			optionID = o.ID
			break
		}
	}
	if optionID == "" {
		return fmt.Errorf("offer %s exposes no Private Network option", server.OfferID)
	}
	if _, err := c.Baremetal.AddOptionServer(&baremetal.AddOptionServerRequest{Zone: zone, ServerID: serverID, OptionID: optionID}, scw.WithContext(ctx)); err != nil {
		return fmt.Errorf("install Private Network option on server %s: %w", serverID, err)
	}
	return fmt.Errorf("installing Private Network option on server %s; will retry", serverID)
}

// DeleteServer tears the Elastic Metal server down, returning done=true once it
// is gone. Bare-metal delete is direct (no stop-first transition the Instance
// kind needs): an absent or already-deleting server counts as in-progress/done
// so a CR whose server was removed out of band releases its finalizer.
func (c *BaremetalClient) DeleteServer(ctx context.Context, zone scw.Zone, serverID string) (bool, error) {
	server, err := c.GetServer(ctx, zone, serverID)
	if err != nil {
		if IsNotFound(err) {
			return true, nil
		}
		return false, err
	}
	if server.Status == baremetal.ServerStatusDeleting {
		return false, nil
	}
	if _, err := c.Baremetal.DeleteServer(&baremetal.DeleteServerRequest{Zone: zone, ServerID: serverID}, scw.WithContext(ctx)); err != nil {
		if IsNotFound(err) {
			return true, nil
		}
		return false, fmt.Errorf("delete elastic metal server %s: %w", serverID, err)
	}
	return false, nil
}

// PrivateNetworkIP returns the IPAM-assigned address of the server on the given
// Private Network (without the CIDR suffix), or "" if not yet assigned. The
// Elastic Metal host DHCPs its VLAN interface from Scaleway's managed PN DHCP,
// which registers the lease in IPAM under the server name; we read it back for
// the node's tuist.dev/pn-ipv4 label.
func (c *BaremetalClient) PrivateNetworkIP(ctx context.Context, server *baremetal.Server, privateNetworkID string) (string, error) {
	region, regErr := server.Zone.Region()
	if regErr != nil {
		return "", fmt.Errorf("region for zone %q: %w", server.Zone, regErr)
	}
	resp, err := c.IPAM.ListIPs(&ipam.ListIPsRequest{
		Region:           region,
		PrivateNetworkID: &privateNetworkID,
		ProjectID:        &c.ProjectID,
	}, scw.WithContext(ctx))
	if err != nil {
		return "", fmt.Errorf("list IPAM IPs for PN %s: %w", privateNetworkID, err)
	}
	for _, ip := range resp.IPs {
		if ip.Resource == nil || ip.Resource.Name == nil || *ip.Resource.Name != server.Name {
			continue
		}
		if ip.Address.IP.To4() == nil {
			continue
		}
		return ip.Address.IP.String(), nil
	}
	return "", nil
}
