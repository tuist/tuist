package controllers

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
)

// EgressFinalizer holds a PicOS RackSwitch until its egress Service is gone: a
// Service in another namespace cannot be owned by it.
const EgressFinalizer = "tuist.dev/rackswitch-egress"

// Egress is the Tailscale egress a cluster Pod reaches a rack's LAN through.
// A PicOS switch's management address is on the rack's side of an edge, which
// advertises it to the tailnet, and only the ProxyGroup's proxies route there,
// so the controller dials each switch at an ExternalName Service the
// Tailscale operator points at the ProxyGroup, the way the RackPDU and RackATS
// controllers reach the power cards. Empty dials the address itself.
type Egress struct {
	// Namespace is the Tailscale operator's, where the ProxyGroup is.
	Namespace  string
	ProxyGroup string
}

// Enabled is whether switches are dialled through the egress.
func (e Egress) Enabled() bool { return e.Namespace != "" && e.ProxyGroup != "" }

func egressServiceName(rs *v1alpha1.RackSwitch) string { return "rackswitch-" + rs.Name }

// picosHost is where the controller dials rs: its egress Service's DNS name,
// kept pointing at its management address, or the address itself without an
// egress.
func (r *RackSwitchReconciler) picosHost(ctx context.Context, rs *v1alpha1.RackSwitch) (string, error) {
	if !r.Egress.Enabled() {
		return rs.Spec.ManagementAddress, nil
	}
	if !controllerutil.ContainsFinalizer(rs, EgressFinalizer) {
		// Patched on a copy, so the status this reconcile is building is not
		// replaced by the stored one.
		obj := rs.DeepCopy()
		base := obj.DeepCopy()
		controllerutil.AddFinalizer(obj, EgressFinalizer)
		if err := r.Patch(ctx, obj, client.MergeFrom(base)); err != nil {
			return "", fmt.Errorf("add finalizer %s: %w", EgressFinalizer, err)
		}
		rs.Finalizers = obj.Finalizers
		rs.ResourceVersion = obj.ResourceVersion
	}
	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: egressServiceName(rs), Namespace: r.Egress.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, svc, func() error {
		if svc.Labels == nil {
			svc.Labels = map[string]string{}
		}
		svc.Labels["app.kubernetes.io/managed-by"] = "rack-switch-controller"
		svc.Labels["tuist.dev/rackswitch"] = rs.Name
		if svc.Annotations == nil {
			svc.Annotations = map[string]string{}
		}
		svc.Annotations["tailscale.com/tailnet-ip"] = rs.Spec.ManagementAddress
		svc.Annotations["tailscale.com/proxy-group"] = r.Egress.ProxyGroup
		svc.Spec.Type = corev1.ServiceTypeExternalName
		// The Tailscale operator replaces it with its proxies' Service.
		if svc.Spec.ExternalName == "" {
			svc.Spec.ExternalName = "placeholder." + r.Egress.Namespace + ".svc.cluster.local"
		}
		svc.Spec.Ports = []corev1.ServicePort{
			{Name: "ssh", Port: 22, Protocol: corev1.ProtocolTCP},
			{Name: "netconf", Port: 830, Protocol: corev1.ProtocolTCP},
		}
		return nil
	})
	if err != nil {
		return "", fmt.Errorf("keep egress Service %s/%s: %w", r.Egress.Namespace, svc.Name, err)
	}
	return fmt.Sprintf("%s.%s.svc.cluster.local", svc.Name, r.Egress.Namespace), nil
}

// releaseEgress deletes a deleted RackSwitch's egress Service and lets it go.
func (r *RackSwitchReconciler) releaseEgress(ctx context.Context, rs *v1alpha1.RackSwitch) error {
	if !controllerutil.ContainsFinalizer(rs, EgressFinalizer) {
		return nil
	}
	if r.Egress.Namespace != "" {
		svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: egressServiceName(rs), Namespace: r.Egress.Namespace}}
		if err := r.Delete(ctx, svc); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete egress Service %s/%s: %w", svc.Namespace, svc.Name, err)
		}
	}
	controllerutil.RemoveFinalizer(rs, EgressFinalizer)
	return client.IgnoreNotFound(r.Update(ctx, rs))
}
