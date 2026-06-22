package controllers

import (
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
