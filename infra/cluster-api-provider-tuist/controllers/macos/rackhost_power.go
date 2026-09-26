package macos

import (
	"context"
	"fmt"
	"net"
	"net/url"
	"sort"
	"strconv"
	"strings"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

const (
	// pduEgressComponent labels the egress Services that front PDUs.
	pduEgressComponent = "rack-pdu-egress"
	// pduEgressLabel carries the PDU address a Service fronts.
	pduEgressLabel = "tuist.dev/rack-pdu"
)

// rackHostOutlet resolves a host's power driver and outlet: the endpoint's
// credentials and certificate pin from its Secret, and, when the tailnet egress
// is configured, the PDU's egress Service to dial in place of its address.
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
	driver, err := registry.Get(host.Spec.Power.Driver)
	if err != nil {
		return nil, power.Outlet{}, err
	}

	outlet := power.Outlet{
		Driver: host.Spec.Power.Driver,
		Host:   host.Spec.Power.Host,
		Outlet: host.Spec.Power.Outlet,
		Dial:   pduEgressHost(egress, host.Spec.Power),
	}
	if ref := host.Spec.Power.CredentialsSecretRef; ref != nil && ref.Name != "" {
		secret := &corev1.Secret{}
		if err := c.Get(ctx, types.NamespacedName{Namespace: secretsNamespace, Name: ref.Name}, secret); err != nil {
			return nil, power.Outlet{}, fmt.Errorf("read power credentials %s/%s: %w", secretsNamespace, ref.Name, err)
		}
		outlet.Username = string(secret.Data["username"])
		outlet.Password = string(secret.Data["password"])
		outlet.TLSFingerprint = string(secret.Data["tlsFingerprint"])
	}
	return driver, outlet, nil
}

// pduEndpoint is where a power block's endpoint is: its IP address and the TCP
// port its driver talks to. ok is false for an endpoint named by a hostname,
// which no egress Service can front by address.
func pduEndpoint(ref *infrav1.PowerOutletRef) (address string, port int32, ok bool) {
	if ref == nil || strings.TrimSpace(ref.Host) == "" {
		return "", 0, false
	}
	scheme := "http"
	if ref.Driver == power.DriverEaton {
		scheme = "https"
	}
	raw := strings.TrimSpace(ref.Host)
	if !strings.Contains(raw, "://") {
		raw = scheme + "://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil {
		return "", 0, false
	}
	ip := net.ParseIP(u.Hostname())
	if ip == nil {
		return "", 0, false
	}
	switch p := u.Port(); {
	case p != "":
		n, err := strconv.ParseUint(p, 10, 16)
		if err != nil || n == 0 {
			return "", 0, false
		}
		port = int32(n)
	case u.Scheme == "https":
		port = 443
	case u.Scheme == "http":
		port = 80
	default:
		return "", 0, false
	}
	return ip.String(), port, true
}

// pduEgressServiceName is the egress Service fronting one PDU address, shared
// by every host plugged into that PDU.
func pduEgressServiceName(address string) string {
	return "pdu-" + strings.NewReplacer(".", "-", ":", "-").Replace(address)
}

// pduEgressHost is the in-cluster DNS name a power block's endpoint is dialled
// by, empty when the tailnet egress is not configured or the endpoint is not
// an IP address.
func pduEgressHost(cfg egressConfig, ref *infrav1.PowerOutletRef) string {
	if !cfg.enabled() {
		return ""
	}
	address, _, ok := pduEndpoint(ref)
	if !ok {
		return ""
	}
	return fmt.Sprintf("%s.%s.svc.cluster.local", pduEgressServiceName(address), cfg.Namespace)
}

// reconcilePDUEgressServices keeps one egress Service per PDU address that a
// RackHost names, with the ports its hosts' drivers use, and deletes the ones
// no RackHost names any more. It works from every RackHost rather than the one
// being reconciled because a PDU is shared: a Service is only unused once the
// last host plugged into its PDU is gone.
func reconcilePDUEgressServices(ctx context.Context, c client.Client, cfg egressConfig) error {
	if !cfg.enabled() {
		return nil
	}
	hosts := &infrav1.RackHostList{}
	if err := c.List(ctx, hosts); err != nil {
		return fmt.Errorf("list rack hosts: %w", err)
	}
	wanted := map[string]map[int32]bool{}
	for i := range hosts.Items {
		host := &hosts.Items[i]
		if !host.DeletionTimestamp.IsZero() {
			continue
		}
		address, port, ok := pduEndpoint(host.Spec.Power)
		if !ok {
			continue
		}
		if wanted[address] == nil {
			wanted[address] = map[int32]bool{}
		}
		wanted[address][port] = true
	}

	keep := map[string]bool{}
	for address, ports := range wanted {
		keep[pduEgressServiceName(address)] = true
		if err := ensurePDUEgressService(ctx, c, cfg, address, ports); err != nil {
			return err
		}
	}

	existing := &corev1.ServiceList{}
	if err := c.List(ctx, existing,
		client.InNamespace(cfg.Namespace),
		client.MatchingLabels{
			"app.kubernetes.io/component":  pduEgressComponent,
			"app.kubernetes.io/managed-by": cfg.ManagedBy,
		},
	); err != nil {
		return fmt.Errorf("list PDU egress Services: %w", err)
	}
	for i := range existing.Items {
		svc := &existing.Items[i]
		if keep[svc.Name] {
			continue
		}
		if err := c.Delete(ctx, svc); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete unused PDU egress Service %s/%s: %w", svc.Namespace, svc.Name, err)
		}
	}
	return nil
}

func ensurePDUEgressService(ctx context.Context, c client.Client, cfg egressConfig, address string, ports map[int32]bool) error {
	numbers := make([]int, 0, len(ports))
	for p := range ports {
		numbers = append(numbers, int(p))
	}
	sort.Ints(numbers)

	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{
		Name:      pduEgressServiceName(address),
		Namespace: cfg.Namespace,
	}}
	_, err := controllerutil.CreateOrUpdate(ctx, c, svc, func() error {
		if svc.Labels == nil {
			svc.Labels = map[string]string{}
		}
		svc.Labels["app.kubernetes.io/managed-by"] = cfg.ManagedBy
		svc.Labels["app.kubernetes.io/component"] = pduEgressComponent
		svc.Labels[pduEgressLabel] = strings.NewReplacer(":", "-").Replace(address)

		if svc.Annotations == nil {
			svc.Annotations = map[string]string{}
		}
		svc.Annotations["tailscale.com/tailnet-ip"] = address
		svc.Annotations["tailscale.com/proxy-group"] = cfg.ProxyGroup

		svc.Spec.Type = corev1.ServiceTypeExternalName
		if svc.Spec.ExternalName == "" {
			svc.Spec.ExternalName = "placeholder." + cfg.Namespace + ".svc.cluster.local"
		}
		servicePorts := make([]corev1.ServicePort, 0, len(numbers))
		for _, p := range numbers {
			name := "tcp-" + strconv.Itoa(p)
			switch p {
			case 443:
				name = "https"
			case 80:
				name = "http"
			}
			servicePorts = append(servicePorts, corev1.ServicePort{Name: name, Port: int32(p), Protocol: corev1.ProtocolTCP})
		}
		svc.Spec.Ports = servicePorts
		return nil
	})
	if err != nil {
		return fmt.Errorf("keep PDU egress Service %s/%s: %w", cfg.Namespace, svc.Name, err)
	}
	return nil
}
