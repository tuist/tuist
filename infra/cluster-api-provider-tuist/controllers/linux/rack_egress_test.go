package linux

import (
	"context"
	"regexp"
	"testing"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

var dnsLabel = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$`)

// The Tailscale operator names a Service's proxy <namespace>-<name> unless the
// Service names it, and refuses a name longer than a DNS label, which a host's
// UUID makes the egress Services' names. Each names its proxy after itself.
func TestRackEgressServicesNameTheirProxiesWithinADNSLabel(t *testing.T) {
	c := fake.NewClientBuilder().WithScheme(rackTestScheme(t)).Build()
	e := rackEgress{Namespace: "tailscale-operator", ProxyGroup: "macmini-egress", ProxyTags: "tag:tuist-k8s-staging"}
	host := &infrav1.RackLinuxHost{}
	host.Name = edgeUUID
	host.Status.Tailnet = &infrav1.RackLinuxHostTailnetStatus{Address: "100.64.0.7"}

	if err := e.ensure(context.Background(), c, host); err != nil {
		t.Fatal(err)
	}
	if err := e.ensureKubelet(context.Background(), c, host); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{rackLinuxEgressName(edgeUUID), rackLinuxKubeletEgressName(edgeUUID)} {
		svc := &corev1.Service{}
		if err := c.Get(context.Background(), types.NamespacedName{Namespace: "tailscale-operator", Name: name}, svc); err != nil {
			t.Fatal(err)
		}
		if got := svc.Annotations["tailscale.com/hostname"]; got != name || !dnsLabel.MatchString(got) {
			t.Fatalf("%s names its proxy %q", name, got)
		}
	}
}
