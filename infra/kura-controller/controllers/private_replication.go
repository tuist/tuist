package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const privateNetworkLabel = "tuist.dev/private-network"
const privateMembershipAnnotation = "tuist.dev/private-network-members"
const peerTopologyEnv = "KURA_PEER_TOPOLOGY"
const managedTopologyAnnotation = "kura.tuist.dev/managed-peer-topology"

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
	if err != nil {
		return err
	}
	if provider == "" {
		if previous != nil && previous.Annotations[managedTopologyAnnotation] == "true" {
			return fmt.Errorf("private replication lost its qualified placement; explicit rollback is required")
		}
		return nil
	}
	value, err := json.Marshal(struct {
		Provider string `json:"provider"`
		Network  string `json:"private_network"`
		URL      string `json:"private_url"`
	}{provider, network, renderPodNodeURL(instance, "$(POD_NAME)", "$(POD_NAMESPACE)")})
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

func privateReplicationDomain(nodes []corev1.Node) (string, string, error) {
	ovh := 0
	for _, node := range nodes {
		if strings.HasPrefix(node.Spec.ProviderID, "ovh://") {
			ovh++
		}
	}
	if ovh == 0 {
		return "", "", nil
	}
	if ovh != len(nodes) {
		return "", "", fmt.Errorf("private replication placement spans OVH and unqualified providers")
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
	return "ovh", network, nil
}
