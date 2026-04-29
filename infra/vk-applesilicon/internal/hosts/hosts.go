// Package hosts discovers the set of bootstrapped Mac minis the VK
// provider can place Pods onto.
//
// Source of truth: ScalewayAppleSiliconMachine CRs in the cluster.
// The CAPI provider operator marks each Machine
// `Status.Ready=true` once Tart is installed via SSH bootstrap. We
// surface those (via their public IP from Status.Addresses) as
// vkprovider.Host entries.
package hosts

import (
	"context"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/tuist/tuist/infra/vk-applesilicon/internal/vkprovider"
)

// Discovery queries the cluster for ready Mac minis.
type Discovery struct {
	Client    client.Client
	Namespace string

	// Defaults baked in from the chart values; per-host overrides
	// could come from labels in the future.
	DefaultCPU      int
	DefaultMemoryMB int
	DefaultSSHUser  string
}

var sasmGVK = schema.GroupVersionKind{
	Group:   "infrastructure.cluster.x-k8s.io",
	Version: "v1alpha1",
	Kind:    "ScalewayAppleSiliconMachine",
}

// Hosts implements vkprovider.Provider.Hosts.
func (d *Discovery) Hosts(ctx context.Context) ([]vkprovider.Host, error) {
	list := &unstructured.UnstructuredList{}
	list.SetGroupVersionKind(sasmGVK)
	if err := d.Client.List(ctx, list, client.InNamespace(d.Namespace)); err != nil {
		return nil, err
	}

	out := make([]vkprovider.Host, 0, len(list.Items))
	for _, item := range list.Items {
		ip, ready := readyIP(&item)
		if !ready || ip == "" {
			continue
		}
		out = append(out, vkprovider.Host{
			IP:       ip,
			SSHUser:  d.DefaultSSHUser,
			CPU:      d.DefaultCPU,
			MemoryMB: d.DefaultMemoryMB,
		})
	}
	return out, nil
}

// readyIP returns the external IPv4 of a Machine if its status has
// `ready: true` AND a non-empty ExternalIP. Robust against
// missing-field shapes since we use unstructured.
func readyIP(item *unstructured.Unstructured) (string, bool) {
	ready, _, _ := unstructured.NestedBool(item.Object, "status", "ready")
	if !ready {
		return "", false
	}
	addrs, _, _ := unstructured.NestedSlice(item.Object, "status", "addresses")
	for _, raw := range addrs {
		a, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		t, _ := a["type"].(string)
		if t != "ExternalIP" {
			continue
		}
		v, _ := a["address"].(string)
		if v != "" {
			return v, true
		}
	}
	return "", true
}
