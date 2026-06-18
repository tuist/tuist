package scaleway

import (
	"context"
	"fmt"
	"net"
	"strings"
	"sync"

	vpc "github.com/scaleway/scaleway-sdk-go/api/vpc/v2"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

// VPCAPI is the slice of the SDK's VPC API the provider touches to find-or-create
// the per-env runner-cache Private Network. An interface so tests drop in a fake;
// the concrete `*vpc.API` satisfies it structurally.
type VPCAPI interface {
	ListPrivateNetworks(req *vpc.ListPrivateNetworksRequest, opts ...scw.RequestOption) (*vpc.ListPrivateNetworksResponse, error)
	CreatePrivateNetwork(req *vpc.CreatePrivateNetworkRequest, opts ...scw.RequestOption) (*vpc.PrivateNetwork, error)
}

// VPCClient resolves the per-env runner-cache Private Network by name, creating
// it if it doesn't exist yet, and returns its ID. The Elastic Metal and Apple
// Silicon reconcilers attach their servers to the *same* PN, so it's addressed
// by a stable name + CIDR (declared in values) rather than a hand-pasted UUID,
// and the operator owns its lifecycle.
type VPCClient struct {
	VPC       VPCAPI
	ProjectID string

	// mu serializes find-or-create across the concurrently-running Elastic
	// Metal and Apple Silicon reconcilers: without it both could list, find
	// nothing, and each create a PN — forking the shared cache data plane.
	// cache memoizes the resolved ID per (region, name) so steady-state
	// reconciles don't re-list.
	mu    sync.Mutex
	cache map[string]string
}

func NewVPCClient(client *scw.Client) *VPCClient {
	projectID, _ := client.GetDefaultProjectID()
	return &VPCClient{VPC: vpc.NewAPI(client), ProjectID: projectID, cache: map[string]string{}}
}

// NewVPCClientFromEnv builds a VPCClient from the standard Scaleway environment
// variables — the same construction the baremetal client uses.
func NewVPCClientFromEnv() (*VPCClient, error) {
	if cfg, err := scw.LoadConfig(); err == nil {
		if profile, perr := cfg.GetActiveProfile(); perr == nil {
			client, cerr := scw.NewClient(scw.WithProfile(profile), scw.WithEnv())
			if cerr != nil {
				return nil, fmt.Errorf("scaleway client: %w", cerr)
			}
			return NewVPCClient(client), nil
		}
	}
	client, err := scw.NewClient(scw.WithEnv())
	if err != nil {
		return nil, fmt.Errorf("scaleway client: %w", err)
	}
	return NewVPCClient(client), nil
}

// EnsurePrivateNetworkByName returns the ID of the Private Network named `name`
// in `region`, creating it with `cidr` if no PN by that name exists. It exact-
// matches the name (the List filter is a substring match) and errors on an
// ambiguous >1 match rather than guessing. Safe to call from multiple
// reconcilers: the lookup + create are serialized and the result is cached.
func (c *VPCClient) EnsurePrivateNetworkByName(ctx context.Context, region scw.Region, name, cidr string) (string, error) {
	if name == "" {
		return "", fmt.Errorf("private network name is required")
	}
	key := string(region) + "|" + name

	c.mu.Lock()
	defer c.mu.Unlock()
	if id, ok := c.cache[key]; ok {
		return id, nil
	}

	var projectFilter *string
	if c.ProjectID != "" {
		p := c.ProjectID
		projectFilter = &p
	}
	resp, err := c.VPC.ListPrivateNetworks(&vpc.ListPrivateNetworksRequest{
		Region:    region,
		Name:      &name,
		ProjectID: projectFilter,
	}, scw.WithContext(ctx), scw.WithAllPages())
	if err != nil {
		return "", fmt.Errorf("list private networks named %q in %s: %w", name, region, err)
	}
	var matches []*vpc.PrivateNetwork
	for _, pn := range resp.PrivateNetworks {
		if pn.Name == name {
			matches = append(matches, pn)
		}
	}
	switch len(matches) {
	case 1:
		c.cache[key] = matches[0].ID
		return matches[0].ID, nil
	case 0:
		// fall through to create
	default:
		return "", fmt.Errorf("ambiguous: %d private networks named %q in project %s/%s — rename or remove the duplicates",
			len(matches), name, c.ProjectID, region)
	}

	subnet, err := parseSubnet(cidr)
	if err != nil {
		return "", err
	}
	// VpcID is left unset so the PN lands in the project's default VPC.
	created, err := c.VPC.CreatePrivateNetwork(&vpc.CreatePrivateNetworkRequest{
		Region:    region,
		Name:      name,
		ProjectID: c.ProjectID,
		Subnets:   []scw.IPNet{subnet},
		Tags:      []string{"capi", "tuist.dev/runner-cache"},
	}, scw.WithContext(ctx))
	if err != nil {
		return "", fmt.Errorf("create private network %q (%s) in %s: %w", name, cidr, region, err)
	}
	c.cache[key] = created.ID
	return created.ID, nil
}

func parseSubnet(cidr string) (scw.IPNet, error) {
	if cidr == "" {
		return scw.IPNet{}, fmt.Errorf("private network CIDR is required")
	}
	ip, network, err := net.ParseCIDR(cidr)
	if err != nil {
		return scw.IPNet{}, fmt.Errorf("parse private network CIDR %q: %w", cidr, err)
	}
	network.IP = ip
	return scw.IPNet{IPNet: *network}, nil
}

// RegionFromZone reduces a Scaleway zone (`fr-par-1`) to its region (`fr-par`)
// — the granularity the VPC API works at.
func RegionFromZone(zone scw.Zone) scw.Region {
	s := string(zone)
	if i := strings.LastIndex(s, "-"); i > 0 {
		return scw.Region(s[:i])
	}
	return scw.Region(s)
}
