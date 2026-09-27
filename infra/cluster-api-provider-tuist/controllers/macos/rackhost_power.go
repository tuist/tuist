package macos

import (
	"context"
	"fmt"
	"strings"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

// pduNotReadyError is a host's RackPDU that power cannot go through yet.
type pduNotReadyError struct {
	pdu, detail string
}

func (e *pduNotReadyError) Error() string {
	return fmt.Sprintf("RackPDU %s is not Ready: %s", e.pdu, e.detail)
}

// rackHostOutlet resolves a host's power driver and outlet. An outlet of a
// RackPDU is reached through the PDU's egress Service, with the credentials
// and certificate pin its controller owns; an outlet of its own endpoint is
// dialled directly, with its credentials Secret's.
func rackHostOutlet(
	ctx context.Context,
	c client.Reader,
	registry *power.Registry,
	secretsNamespace string,
	egress egressConfig,
	host *infrav1.RackHost,
) (power.Driver, power.Outlet, error) {
	if host.Spec.Power == nil {
		return nil, power.Outlet{}, fmt.Errorf("host has no power outlet configured; it cannot be rebooted remotely")
	}
	if registry == nil {
		return nil, power.Outlet{}, fmt.Errorf("no power drivers wired into this operator build")
	}
	if name := strings.TrimSpace(host.Spec.Power.PDU); name != "" {
		return rackHostPDUOutlet(ctx, c, registry, egress, host, name)
	}
	if strings.TrimSpace(host.Spec.Power.Host) == "" {
		return nil, power.Outlet{}, fmt.Errorf("power names neither a pdu nor a host")
	}
	driver, err := registry.Get(host.Spec.Power.Driver)
	if err != nil {
		return nil, power.Outlet{}, err
	}
	outlet := power.Outlet{
		Driver: host.Spec.Power.Driver,
		Host:   host.Spec.Power.Host,
		Outlet: host.Spec.Power.Outlet,
	}
	if ref := host.Spec.Power.CredentialsSecretRef; ref != nil && ref.Name != "" {
		secret := &corev1.Secret{}
		if err := c.Get(ctx, types.NamespacedName{Namespace: secretsNamespace, Name: ref.Name}, secret); err != nil {
			return nil, power.Outlet{}, fmt.Errorf("read power credentials %s/%s: %w", secretsNamespace, ref.Name, err)
		}
		outlet.Username = string(secret.Data["username"])
		outlet.Password = string(secret.Data["password"])
	}
	return driver, outlet, nil
}

func rackHostPDUOutlet(ctx context.Context, c client.Reader, registry *power.Registry, egress egressConfig, host *infrav1.RackHost, name string) (power.Driver, power.Outlet, error) {
	pdu := &infrav1.RackPDU{}
	if err := c.Get(ctx, types.NamespacedName{Namespace: host.Namespace, Name: name}, pdu); err != nil {
		if apierrors.IsNotFound(err) {
			return nil, power.Outlet{}, &pduNotReadyError{pdu: name, detail: "no such RackPDU in " + host.Namespace}
		}
		return nil, power.Outlet{}, err
	}
	if pdu.Spec.ManagedBy != infrav1.RackPDUManagedByController {
		return nil, power.Outlet{}, &pduNotReadyError{pdu: name, detail: "it is standalone: the controller does not manage it"}
	}
	if !conditions.IsTrue(pdu, clusterv1.ReadyCondition) {
		detail := conditions.GetMessage(pdu, clusterv1.ReadyCondition)
		if detail == "" {
			detail = "not adopted yet"
		}
		return nil, power.Outlet{}, &pduNotReadyError{pdu: name, detail: detail}
	}
	secret := &corev1.Secret{}
	if err := c.Get(ctx, types.NamespacedName{Namespace: pdu.Namespace, Name: rackPDUSecretName(pdu)}, secret); err != nil {
		return nil, power.Outlet{}, fmt.Errorf("read %s's credentials: %w", name, err)
	}
	driver, err := registry.Get(power.DriverEaton)
	if err != nil {
		return nil, power.Outlet{}, err
	}
	outlet := rackPDUOutlet(egress, pdu, secret)
	outlet.Outlet = host.Spec.Power.Outlet
	return driver, outlet, nil
}

// rackPDUEgressServiceName is the egress Service fronting one RackPDU's card.
func rackPDUEgressServiceName(pdu string) string {
	return "rackpdu-" + pdu
}

// rackPDUEgressHost is the in-cluster DNS name a RackPDU's card is dialled by,
// empty when the tailnet egress is not configured.
func rackPDUEgressHost(cfg egressConfig, pdu string) string {
	if !cfg.enabled() {
		return ""
	}
	return fmt.Sprintf("%s.%s.svc.cluster.local", rackPDUEgressServiceName(pdu), cfg.Namespace)
}

// reconcileRackPDUEgressService fronts a RackPDU's card on :443, by its
// address, which the ProxyGroup reaches through the rack's edge. The RackPDU's
// finalizer deletes it: a Service in another namespace cannot be owned.
func reconcileRackPDUEgressService(ctx context.Context, c client.Client, cfg egressConfig, pdu *infrav1.RackPDU) error {
	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{
		Name:      rackPDUEgressServiceName(pdu.Name),
		Namespace: cfg.Namespace,
	}}
	_, err := controllerutil.CreateOrUpdate(ctx, c, svc, func() error {
		if svc.Labels == nil {
			svc.Labels = map[string]string{}
		}
		svc.Labels["app.kubernetes.io/managed-by"] = cfg.ManagedBy
		svc.Labels["app.kubernetes.io/component"] = "rack-pdu-egress"
		svc.Labels["tuist.dev/rack-pdu"] = pdu.Name
		if svc.Annotations == nil {
			svc.Annotations = map[string]string{}
		}
		svc.Annotations["tailscale.com/tailnet-ip"] = pdu.Spec.Address
		svc.Annotations["tailscale.com/proxy-group"] = cfg.ProxyGroup
		svc.Spec.Type = corev1.ServiceTypeExternalName
		if svc.Spec.ExternalName == "" {
			svc.Spec.ExternalName = "placeholder." + cfg.Namespace + ".svc.cluster.local"
		}
		svc.Spec.Ports = []corev1.ServicePort{{Name: "https", Port: 443, Protocol: corev1.ProtocolTCP}}
		return nil
	})
	if err != nil {
		return fmt.Errorf("keep egress Service %s/%s: %w", cfg.Namespace, svc.Name, err)
	}
	return nil
}
