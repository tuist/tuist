package linux

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// rackEgress fronts a rack Linux host's tailnet address with an egress Service
// on the Tailscale ProxyGroup, since a Pod has no route to the tailnet.
type rackEgress struct {
	Namespace  string
	ProxyGroup string
}

func (e rackEgress) enabled() bool {
	return e.Namespace != "" && e.ProxyGroup != ""
}

func rackLinuxEgressName(hostName string) string {
	return "rack-linux-" + hostName
}

func (e rackEgress) dialTarget(host *infrav1.RackLinuxHost) string {
	if !e.enabled() {
		return host.Status.Tailnet.Address
	}
	return fmt.Sprintf("%s.%s.svc.cluster.local", rackLinuxEgressName(host.Name), e.Namespace)
}

func (e rackEgress) ensure(ctx context.Context, c client.Client, host *infrav1.RackLinuxHost) error {
	if !e.enabled() {
		return nil
	}
	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: rackLinuxEgressName(host.Name), Namespace: e.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, c, svc, func() error {
		if svc.Labels == nil {
			svc.Labels = map[string]string{}
		}
		svc.Labels["app.kubernetes.io/managed-by"] = "capi-scaleway-applesilicon"
		svc.Labels["app.kubernetes.io/component"] = "rack-linux-host-egress"
		svc.Labels["tuist.dev/rack-linux-host"] = host.Name
		if svc.Annotations == nil {
			svc.Annotations = map[string]string{}
		}
		svc.Annotations["tailscale.com/tailnet-ip"] = host.Status.Tailnet.Address
		svc.Annotations["tailscale.com/proxy-group"] = e.ProxyGroup
		svc.Spec.Type = corev1.ServiceTypeExternalName
		if svc.Spec.ExternalName == "" {
			svc.Spec.ExternalName = "placeholder." + e.Namespace + ".svc.cluster.local"
		}
		svc.Spec.Ports = []corev1.ServicePort{{Name: "ssh", Port: 22, Protocol: corev1.ProtocolTCP}}
		return nil
	})
	return err
}

func (e rackEgress) remove(ctx context.Context, c client.Client, hostName string) error {
	if !e.enabled() {
		return nil
	}
	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: rackLinuxEgressName(hostName), Namespace: e.Namespace}}
	if err := c.Delete(ctx, svc); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete egress Service %s: %w", svc.Name, err)
	}
	return nil
}
