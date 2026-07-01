package controllers

import (
	"slices"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func gatewayFixture(hostNetwork bool) *kurav1alpha1.KuraGateway {
	return &kurav1alpha1.KuraGateway{
		ObjectMeta: metav1.ObjectMeta{Name: "kgw-test", Namespace: "kura"},
		Spec: kurav1alpha1.KuraGatewaySpec{
			Region:           "dedibox-staging",
			IngressClassName: "kura-dedibox-staging",
			HostNetwork:      hostNetwork,
		},
	}
}

func TestGatewayPodTemplateHostNetwork(t *testing.T) {
	pod := gatewayPodTemplate(gatewayFixture(true), defaultGatewayServiceAccount)
	if !pod.Spec.HostNetwork {
		t.Errorf("hostNetwork gateway pod must run on the host network")
	}
	if pod.Spec.DNSPolicy != corev1.DNSClusterFirstWithHostNet {
		t.Errorf("hostNetwork gateway pod must use ClusterFirstWithHostNet DNS, got %q", pod.Spec.DNSPolicy)
	}
}

func TestGatewayPodTemplateDefaultNetwork(t *testing.T) {
	pod := gatewayPodTemplate(gatewayFixture(false), defaultGatewayServiceAccount)
	if pod.Spec.HostNetwork {
		t.Errorf("LoadBalancer gateway pod must not run on the host network")
	}
	if pod.Spec.DNSPolicy != corev1.DNSClusterFirst {
		t.Errorf("LoadBalancer gateway pod must use the default ClusterFirst DNS, got %q", pod.Spec.DNSPolicy)
	}
}

// A bare-metal cache node carries tuist.dev/kura-cache=true:NoSchedule, and the
// host-network gateway is pinned to that node (it binds the box's public IP), so
// the pod template must carry the toleration or the gateway never schedules and
// the region has no ingress.
func TestGatewayPodTemplatePropagatesTolerations(t *testing.T) {
	gateway := gatewayFixture(true)
	gateway.Spec.Tolerations = []corev1.Toleration{{
		Key:      "tuist.dev/kura-cache",
		Operator: corev1.TolerationOpExists,
		Effect:   corev1.TaintEffectNoSchedule,
	}}
	pod := gatewayPodTemplate(gateway, defaultGatewayServiceAccount)
	if !slices.ContainsFunc(pod.Spec.Tolerations, func(tol corev1.Toleration) bool {
		return tol.Key == "tuist.dev/kura-cache" && tol.Effect == corev1.TaintEffectNoSchedule
	}) {
		t.Errorf("gateway pod must carry the kura-cache toleration, got %+v", pod.Spec.Tolerations)
	}
}

// A host-network gateway has no LoadBalancer to prepend a PROXY header, so
// proxy-protocol must be off (it would mangle every connection); LB-fronted
// gateways keep it on.
func TestGatewayHostNetworkDisablesProxyProtocol(t *testing.T) {
	if got := gatewayNginxConfigData(true)["use-proxy-protocol"]; got != "false" {
		t.Errorf("hostNetwork gateway must disable proxy-protocol, got %q", got)
	}
	if got := gatewayNginxConfigData(false)["use-proxy-protocol"]; got != "true" {
		t.Errorf("LoadBalancer gateway must keep proxy-protocol on, got %q", got)
	}
}

// A host-network gateway must report the node's own InternalIP into Ingress
// status for external-dns; an LB-fronted one publishes its Service instead.
// Reporting the ClusterIP publish-service on host-network resolves the
// per-account host to an unreachable address.
func TestGatewayControllerArgsByNetwork(t *testing.T) {
	host := gatewayControllerArgs(gatewayFixture(true))
	if !slices.Contains(host, "--report-node-internal-ip-address=true") {
		t.Errorf("hostNetwork gateway must report the node InternalIP, args=%v", host)
	}
	if slices.ContainsFunc(host, func(a string) bool { return strings.HasPrefix(a, "--publish-service") }) {
		t.Errorf("hostNetwork gateway must not publish a ClusterIP service, args=%v", host)
	}

	lb := gatewayControllerArgs(gatewayFixture(false))
	if !slices.ContainsFunc(lb, func(a string) bool { return strings.HasPrefix(a, "--publish-service=") }) {
		t.Errorf("LoadBalancer gateway must publish its service, args=%v", lb)
	}
	if slices.ContainsFunc(lb, func(a string) bool { return strings.HasPrefix(a, "--report-node-internal-ip") }) {
		t.Errorf("LoadBalancer gateway must not report node IP, args=%v", lb)
	}
}
