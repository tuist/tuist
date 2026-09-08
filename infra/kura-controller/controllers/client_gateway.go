package controllers

import (
	"context"
	"net"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const gatewayClassLabel = "tuist.dev/kura-ingress-class"

// Private instances explicitly opt into a gateway. A leftover PublicHost must
// never turn a legacy private instance into a public endpoint.
func clientHost(instance *kurav1alpha1.KuraInstance) string {
	if !instance.Spec.Private {
		return instance.Spec.PublicHost
	}
	if !instance.Spec.PublicHostNetwork || instance.Spec.IngressClassName == "" || len(instance.Spec.ClientCIDRs) == 0 {
		return ""
	}
	for _, cidr := range instance.Spec.ClientCIDRs {
		if _, _, err := net.ParseCIDR(cidr); err != nil {
			return ""
		}
	}
	return instance.Spec.PrivateHost
}

func clientIngressAnnotations(instance *kurav1alpha1.KuraInstance, annotations map[string]string) map[string]string {
	if instance.Spec.Private {
		annotations["nginx.ingress.kubernetes.io/whitelist-source-range"] = strings.Join(instance.Spec.ClientCIDRs, ",")
	}
	return annotations
}

// Readiness is about the complete private entrance, independently of whether a
// StatefulSet image rollout has converged. Ingress status publication is disabled
// on this gateway so external-dns cannot replace the PN record with a public IP.
func (r *KuraInstanceReconciler) privateGatewayURL(ctx context.Context, instance *kurav1alpha1.KuraInstance, primary string, pods []corev1.Pod, samples map[string]runtimeStatus) (string, error) {
	host := clientHost(instance)
	if !instance.Spec.Private || host == "" {
		return "", nil
	}
	health, _ := primaryPodHealthFromSamples(instance, pods, samples, time.Now())
	if _, fresh := samples[primary]; !fresh || !health[primary] {
		return "", nil
	}
	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: publicTLSSecretName(instance)}, cert); err != nil {
		return "", client.IgnoreNotFound(err)
	}
	conditions, _, _ := unstructured.NestedSlice(cert.Object, "status", "conditions")
	ready := false
	for _, entry := range conditions {
		condition, ok := entry.(map[string]interface{})
		if ok && condition["type"] == "Ready" && condition["status"] == "True" && condition["observedGeneration"] == cert.GetGeneration() {
			ready = true
		}
	}
	if !ready {
		return "", nil
	}
	target, err := r.instanceNodeAddress(ctx, instance, true)
	if err != nil || target == "" {
		return "", err
	}
	reader := r.APIReader
	if reader == nil {
		reader = r.Client
	}
	gateways := &corev1.PodList{}
	if err := reader.List(ctx, gateways, client.InNamespace("platform"), client.MatchingLabels{gatewayClassLabel: instance.Spec.IngressClassName}); err != nil {
		return "", err
	}
	ready = false
	for i := range gateways.Items {
		gateway := &gateways.Items[i]
		if !podReady(gateway) || !gateway.Spec.HostNetwork || gateway.Spec.NodeName == "" {
			continue
		}
		node := &corev1.Node{}
		if err := r.Get(ctx, types.NamespacedName{Name: gateway.Spec.NodeName}, node); err != nil {
			return "", client.IgnoreNotFound(err)
		}
		if nodeReady(node) && node.Labels["tuist.dev/pn-ipv4"] == target {
			ready = true
			break
		}
	}
	if !ready {
		return "", nil
	}
	resolver := r.PeerDNSResolver
	if resolver == nil {
		resolver = netPeerDNSResolver{}
	}
	lookupCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	addresses, err := resolver.LookupHost(lookupCtx, host)
	if err != nil || len(addresses) == 0 {
		return "", nil
	}
	for _, address := range addresses {
		if address != target {
			return "", nil
		}
	}
	return "https://" + host, nil
}
