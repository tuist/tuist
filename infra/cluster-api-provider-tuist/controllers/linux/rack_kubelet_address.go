package linux

import (
	"context"
	"fmt"
	"strings"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/equality"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// cloudProviderUninitializedTaint is the taint a kubelet run with
// --cloud-provider=external registers with, until a cloud provider has set the
// node's addresses.
const cloudProviderUninitializedTaint = "node.cloudprovider.kubernetes.io/uninitialized"

// reconcileNodeAddresses stands in for a cloud provider on a rack node. The API
// server dials a kubelet at the node's ExternalIP before its InternalIP, and a
// rack node's InternalIP is on the tailnet, which the control plane is not on,
// so logs, exec and port-forward would time out. The node's ExternalIP is its
// kubelet proxy's Pod address instead, which the control plane routes to. The
// node is initialized once its tailnet address is set, whether or not the proxy
// is up yet.
func (r *RackLinuxMachineReconciler) reconcileNodeAddresses(ctx context.Context, host *infrav1.RackLinuxHost, node *corev1.Node) error {
	if err := r.egress().ensureKubelet(ctx, r.Client, host); err != nil {
		return fmt.Errorf("reconcile kubelet egress Service for %s: %w", host.Spec.Hostname, err)
	}
	if node == nil {
		return nil
	}
	proxy, err := r.egress().kubeletProxyAddress(ctx, r.Client, host.Name)
	if err != nil {
		return err
	}

	addresses := []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: host.Status.Tailnet.Address}}
	if proxy != "" {
		addresses = append(addresses, corev1.NodeAddress{Type: corev1.NodeExternalIP, Address: proxy})
	}
	addresses = append(addresses, corev1.NodeAddress{Type: corev1.NodeHostName, Address: host.Spec.Hostname})
	if !equality.Semantic.DeepEqual(node.Status.Addresses, addresses) {
		before := node.DeepCopy()
		node.Status.Addresses = addresses
		if err := r.Status().Patch(ctx, node, client.MergeFrom(before)); err != nil {
			return fmt.Errorf("set the addresses of Node %s: %w", node.Name, err)
		}
	}

	taints := make([]corev1.Taint, 0, len(node.Spec.Taints))
	for _, taint := range node.Spec.Taints {
		if taint.Key != cloudProviderUninitializedTaint {
			taints = append(taints, taint)
		}
	}
	if len(taints) != len(node.Spec.Taints) {
		before := node.DeepCopy()
		node.Spec.Taints = taints
		if err := r.Patch(ctx, node, client.MergeFrom(before)); err != nil {
			return fmt.Errorf("initialize Node %s: %w", node.Name, err)
		}
	}
	return nil
}

// machineForKubeletProxy wakes a host's machine, which has the host's name,
// when the host's kubelet proxy Pod changes, since the node's ExternalIP follows the Pod.
func (r *RackLinuxMachineReconciler) machineForKubeletProxy(ctx context.Context, o client.Object) []reconcile.Request {
	parent := o.GetLabels()["tailscale.com/parent-resource"]
	if o.GetNamespace() != r.EgressNamespace || o.GetLabels()["tailscale.com/parent-resource-type"] != "svc" ||
		!strings.HasPrefix(parent, rackLinuxEgressName("")) || !strings.HasSuffix(parent, "-kubelet") {
		return nil
	}
	hostName := strings.TrimSuffix(strings.TrimPrefix(parent, rackLinuxEgressName("")), "-kubelet")
	hosts := &infrav1.RackLinuxHostList{}
	if err := r.List(ctx, hosts); err != nil {
		return nil
	}
	var requests []reconcile.Request
	for i := range hosts.Items {
		host := &hosts.Items[i]
		if host.Name == hostName {
			requests = append(requests, reconcile.Request{NamespacedName: types.NamespacedName{Namespace: host.Namespace, Name: host.Name}})
		}
	}
	return requests
}
