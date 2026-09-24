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
	for _, name := range []string{rackLinuxEgressName(hostName), rackLinuxKubeletEgressName(hostName)} {
		svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: e.Namespace}}
		if err := c.Delete(ctx, svc); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete egress Service %s: %w", svc.Name, err)
		}
	}
	return nil
}

func rackLinuxKubeletEgressName(hostName string) string {
	return rackLinuxEgressName(hostName) + "-kubelet"
}

// ensureKubelet fronts the host's kubelet with an egress proxy of its own. An
// egress Service outside the ProxyGroup gets a dedicated proxy Pod that
// forwards every port to the tailnet address, so the kubelet answers on its own
// port at that Pod's address, which the control plane can route to.
func (e rackEgress) ensureKubelet(ctx context.Context, c client.Client, host *infrav1.RackLinuxHost) error {
	if !e.enabled() {
		return nil
	}
	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: rackLinuxKubeletEgressName(host.Name), Namespace: e.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, c, svc, func() error {
		if svc.Labels == nil {
			svc.Labels = map[string]string{}
		}
		svc.Labels["app.kubernetes.io/managed-by"] = "capi-scaleway-applesilicon"
		svc.Labels["app.kubernetes.io/component"] = "rack-linux-host-kubelet-egress"
		svc.Labels["tuist.dev/rack-linux-host"] = host.Name
		if svc.Annotations == nil {
			svc.Annotations = map[string]string{}
		}
		svc.Annotations["tailscale.com/tailnet-ip"] = host.Status.Tailnet.Address
		svc.Spec.Type = corev1.ServiceTypeExternalName
		if svc.Spec.ExternalName == "" {
			svc.Spec.ExternalName = "placeholder." + e.Namespace + ".svc.cluster.local"
		}
		svc.Spec.Ports = []corev1.ServicePort{{Name: "kubelet", Port: 10250, Protocol: corev1.ProtocolTCP}}
		return nil
	})
	return err
}

// kubeletProxyAddress is the address of the host's kubelet proxy Pod, or empty
// while it has none that is ready.
func (e rackEgress) kubeletProxyAddress(ctx context.Context, c client.Client, hostName string) (string, error) {
	if !e.enabled() {
		return "", nil
	}
	pods := &corev1.PodList{}
	if err := c.List(ctx, pods, client.InNamespace(e.Namespace), client.MatchingLabels{
		"tailscale.com/parent-resource":      rackLinuxKubeletEgressName(hostName),
		"tailscale.com/parent-resource-ns":   e.Namespace,
		"tailscale.com/parent-resource-type": "svc",
	}); err != nil {
		return "", fmt.Errorf("list kubelet proxy Pods for %s: %w", hostName, err)
	}
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.DeletionTimestamp == nil && pod.Status.Phase == corev1.PodRunning && pod.Status.PodIP != "" && podReady(pod) {
			return pod.Status.PodIP, nil
		}
	}
	return "", nil
}

func podReady(pod *corev1.Pod) bool {
	for _, c := range pod.Status.Conditions {
		if c.Type == corev1.PodReady {
			return c.Status == corev1.ConditionTrue
		}
	}
	return false
}
