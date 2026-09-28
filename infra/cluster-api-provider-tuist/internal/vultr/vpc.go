package vultr

import (
	"context"
	"fmt"
	"net/http"
	"net/netip"
	"net/url"
	"strconv"
	"strings"
)

// VPC is one location's private network, not an inter-location transport.
type VPC struct {
	ID          string `json:"id,omitempty"`
	Region      string `json:"region"`
	Description string `json:"description"`
	Subnet      string `json:"v4_subnet"`
	Mask        int    `json:"v4_subnet_mask"`
}

func (v VPC) prefix() (netip.Prefix, error) {
	p, err := netip.ParsePrefix(v.Subnet + "/" + strconv.Itoa(v.Mask))
	if err != nil || !p.Addr().Is4() || !p.Addr().IsPrivate() || p != p.Masked() || p.Bits() < 16 || p.Bits() > 28 {
		return netip.Prefix{}, fmt.Errorf("VPC requires an aligned private IPv4 subnet with prefix length 16–28")
	}
	return p, nil
}

// ListVPCs reads every page so idempotency and overlap checks see the full account.
func (c *Client) ListVPCs(ctx context.Context) ([]VPC, error) {
	result := []VPC{}
	cursor := ""
	seen := map[string]bool{}
	for {
		q := url.Values{"per_page": {"100"}}
		if cursor != "" {
			q.Set("cursor", cursor)
		}
		var out struct {
			VPCs []VPC `json:"vpcs"`
			Meta struct {
				Links struct {
					Next string `json:"next"`
				} `json:"links"`
			} `json:"meta"`
		}
		if err := c.do(ctx, http.MethodGet, "/vpcs", q, nil, &out); err != nil {
			return nil, err
		}
		if out.VPCs == nil {
			return nil, fmt.Errorf("provider returned no VPC inventory; refusing to infer an empty account")
		}
		result = append(result, out.VPCs...)
		cursor = out.Meta.Links.Next
		if cursor == "" {
			return result, nil
		}
		if seen[cursor] {
			return nil, fmt.Errorf("VPC pagination repeated a cursor")
		}
		seen[cursor] = true
	}
}

// EnsureVPC plans by default. Apply creates only an empty VPC: no NAT gateway,
// attachment, restart, route or runtime configuration. Run serially per account;
// Vultr's create API has no idempotency key. A timed-out POST must be inspected
// before retrying, since the provider may have accepted it.
func (c *Client) EnsureVPC(ctx context.Context, desired VPC, apply bool) (*VPC, error) {
	if desired.ID != "" || strings.TrimSpace(desired.Region) != desired.Region || desired.Region == "" || strings.TrimSpace(desired.Description) != desired.Description || desired.Description == "" {
		return nil, fmt.Errorf("VPC requires a region and description without surrounding spaces, and no input ID")
	}
	prefix, err := desired.prefix()
	if err != nil {
		return nil, err
	}
	networks, err := c.ListVPCs(ctx)
	if err != nil {
		return nil, err
	}
	var match *VPC
	for _, network := range networks {
		if network.Description == desired.Description {
			if match != nil {
				return nil, fmt.Errorf("multiple VPCs match description %q; resolve manually", desired.Description)
			}
			if network.ID == "" || network.Region != desired.Region || network.Subnet != desired.Subnet || network.Mask != desired.Mask {
				return nil, fmt.Errorf("existing VPC %q differs from requested location or subnet", desired.Description)
			}
			copy := network
			match = &copy
			continue
		}
		other, err := network.prefix()
		if err != nil {
			return nil, fmt.Errorf("cannot validate existing VPC %s: %w", network.ID, err)
		}
		if prefix.Overlaps(other) {
			return nil, fmt.Errorf("requested subnet overlaps existing VPC %s in %s", network.ID, network.Region)
		}
	}
	if match != nil {
		return match, nil
	}
	if !apply {
		return &desired, nil
	}
	var out struct {
		VPC VPC `json:"vpc"`
	}
	if err := c.do(ctx, http.MethodPost, "/vpcs", nil, desired, &out); err != nil {
		return nil, fmt.Errorf("create VPC (inspect provider state before retrying): %w", err)
	}
	if out.VPC.ID == "" || out.VPC.Region != desired.Region || out.VPC.Description != desired.Description || out.VPC.Subnet != desired.Subnet || out.VPC.Mask != desired.Mask {
		return nil, fmt.Errorf("provider returned unexpected VPC; inspect state before retrying")
	}
	return &out.VPC, nil
}
