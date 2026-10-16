package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"slices"
	"strings"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

const privateNetworkLabel = "tuist.dev/private-network"
const privateMembershipAnnotation = "tuist.dev/private-network-members"
const peerTopologyEnv = "KURA_PEER_TOPOLOGY"
const managedTopologyAnnotation = "kura.tuist.dev/managed-peer-topology"
const privateCanonicalNetworksAnnotation = "tuist.dev/private-network-canonical-peers"

// Only advertise a provider domain after every possible placement carries the
// host controller's converged route attestation. A pool name is not a provider.
func (r *KuraInstanceReconciler) configurePrivateReplication(ctx context.Context, instance *kurav1alpha1.KuraInstance, template, previous *corev1.PodTemplateSpec) error {
	if !r.PrivateReplication || hasEnvVar(instance.Spec.ExtraEnv, peerTopologyEnv) {
		return nil
	}
	nodes := &corev1.NodeList{}
	if err := r.List(ctx, nodes, client.MatchingLabels(nodeSelector(instance))); err != nil {
		return err
	}
	provider, network, err := privateReplicationDomain(nodes.Items)
	var canonicalNetworks []string
	if err == nil && provider != "" {
		canonicalNetworks, err = privateCanonicalNetworks(nodes.Items, network)
	}
	if err != nil || provider == "" {
		// Qualification gates topology publication, not unrelated workload
		// reconciliation. Preserve policy through observation gaps only while
		// the requested placement is unchanged; an explicit move withdraws it.
		preservePrivateReplication(template, previous)
		log.FromContext(ctx).V(1).Info("Private topology publication pending", "reason", err)
		return nil
	}
	value, err := json.Marshal(struct {
		Provider          string   `json:"provider"`
		Network           string   `json:"private_network"`
		URL               string   `json:"private_url"`
		CanonicalNetworks []string `json:"canonical_networks,omitempty"`
	}{provider, network, renderPodNodeURL(instance, "$(POD_NAME)", "$(POD_NAMESPACE)"), canonicalNetworks})
	if err != nil {
		return err
	}
	for i := range template.Spec.Containers {
		if template.Spec.Containers[i].Name == kuraContainerName {
			template.Spec.Containers[i].Env = append(template.Spec.Containers[i].Env, corev1.EnvVar{Name: peerTopologyEnv, Value: string(value)})
		}
	}
	if template.Spec.NodeSelector == nil {
		template.Spec.NodeSelector = map[string]string{}
	}
	template.Spec.NodeSelector[privateNetworkLabel] = network
	if template.Annotations == nil {
		template.Annotations = map[string]string{}
	}
	template.Annotations[managedTopologyAnnotation] = "true"
	return nil
}

// Publish a host-controller policy only when every possible placement agrees.
// Domain IDs come from verified provider inventory, never from region aliases.
func privateCanonicalNetworks(nodes []corev1.Node, ownNetwork string) ([]string, error) {
	var result []string
	for index, node := range nodes {
		var networks []string
		if raw := node.Annotations[privateCanonicalNetworksAnnotation]; raw != "" {
			if err := json.Unmarshal([]byte(raw), &networks); err != nil {
				return nil, fmt.Errorf("invalid canonical network policy on %s: %w", node.Name, err)
			}
		}
		if len(networks) > 32 {
			return nil, fmt.Errorf("canonical network policy on %s exceeds 32 domains", node.Name)
		}
		slices.Sort(networks)
		for i, network := range networks {
			if network == "" || network != strings.TrimSpace(network) || network == ownNetwork || (i > 0 && networks[i-1] == network) {
				return nil, fmt.Errorf("invalid canonical domain on %s", node.Name)
			}
		}
		if index > 0 && !slices.Equal(result, networks) {
			return nil, fmt.Errorf("private replication waits for matching canonical network policies")
		}
		result = networks
	}
	return result, nil
}

func preservePrivateReplication(template, previous *corev1.PodTemplateSpec) {
	if previous == nil || previous.Annotations[managedTopologyAnnotation] != "true" {
		return
	}
	requestedSelector := maps.Clone(template.Spec.NodeSelector)
	previousSelector := maps.Clone(previous.Spec.NodeSelector)
	delete(requestedSelector, privateNetworkLabel)
	delete(previousSelector, privateNetworkLabel)
	if !maps.Equal(requestedSelector, previousSelector) {
		return
	}
	template.Spec.NodeSelector = previous.DeepCopy().Spec.NodeSelector
	if template.Annotations == nil {
		template.Annotations = map[string]string{}
	}
	template.Annotations[managedTopologyAnnotation] = "true"
	for _, container := range previous.Spec.Containers {
		if container.Name != kuraContainerName {
			continue
		}
		for _, env := range container.Env {
			if env.Name == peerTopologyEnv {
				for i := range template.Spec.Containers {
					if template.Spec.Containers[i].Name == kuraContainerName {
						template.Spec.Containers[i].Env = append(template.Spec.Containers[i].Env, *env.DeepCopy())
					}
				}
			}
		}
	}
}

func privateReplicationDomain(nodes []corev1.Node) (string, string, error) {
	provider := ""
	for _, node := range nodes {
		if strings.HasPrefix(node.Spec.ProviderID, "ovh://") {
			provider = "ovh"
			break
		}
		if strings.HasPrefix(node.Spec.ProviderID, "vultr://") && node.Labels[privateNetworkLabel] != "" {
			provider = "vultr"
		}
	}
	if provider == "" {
		return "", "", nil
	}
	for _, node := range nodes {
		if !strings.HasPrefix(node.Spec.ProviderID, provider+"://") {
			return "", "", fmt.Errorf("private replication placement mixes qualified and unqualified providers")
		}
		if provider == "vultr" && (node.Status.NodeInfo.BootID == "" || !strings.HasSuffix(node.Annotations["tuist.dev/private-network-revision"], ":"+node.Status.NodeInfo.BootID)) {
			return "", "", fmt.Errorf("private replication waits for node %s's current boot attestation", node.Name)
		}
	}

	network, membership := "", ""
	for _, node := range nodes {
		n, m := node.Labels[privateNetworkLabel], node.Annotations[privateMembershipAnnotation]
		if n == "" || m == "" || node.Annotations[privateNetworkLabel] != n {
			return "", "", fmt.Errorf("private replication waits for node %s's verified routes", node.Name)
		}
		if network != "" && (network != n || membership != m) {
			return "", "", fmt.Errorf("private replication placement has different domains or route memberships")
		}
		network, membership = n, m
	}
	return provider, network, nil
}
