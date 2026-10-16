package controllers

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	"k8s.io/apimachinery/pkg/util/validation"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const (
	nodeLocalPeerConfigHashAnnotation = "tuist.dev/node-local-peer-config-hash"
	nodeLocalPeerConfigDir            = "/etc/kura-peer"
	nodeLocalPeerDefaultConfig        = "default.conf"
	nodeLocalPeerEgressComponent      = "node-local-peer-egress"
)

// nodeLocalPeerHost is the in-cluster name a node-local mesh instance's peer
// plane is dialled at, or empty when the instance has none.
func nodeLocalPeerHost(instance *kurav1alpha1.KuraInstance) string {
	if !instance.Spec.Mesh || instance.Spec.NodeLocalNetwork == nil {
		return ""
	}
	return strings.TrimSpace(instance.Spec.NodeLocalNetwork.PeerHost)
}

// NodeLocalPeerReconciler gives the mesh instances of a node-local region a
// peer plane the rest of the account's mesh can dial.
//
// A node-local pod sits on its node's own bridge: it reaches out through the
// node's NAT, which is how it dials the other regions' public peer hosts, but
// nothing in the cluster reaches it. The other regions pull from it all the
// same, so for every such instance this keeps:
//
//   - a Tailscale egress Service named after the instance's PeerHost, in the
//     egress namespace, on the ProxyGroup the cluster already reaches rack
//     hosts through, targeting the tailnet name of the node the gateway pod
//     runs on. A cluster pod resolving PeerHost reaches that node's :7443.
//   - a host-network SNI-passthrough demux on the region's nodes that
//     forwards :7443 by SNI to the gateway pod's IP on the node's bridge. TLS
//     is not terminated, so the peer connection stays end-to-end mTLS
//     against the account CA.
//
// Keyed by region, like PeerDemuxReconciler, because the demux is shared by
// every instance of the region. The egress Services live outside the watch
// namespace, so they are read and written through EgressClient, which is not
// cached, and cleaned up by label rather than owner reference (an owner
// reference cannot cross namespaces).
type NodeLocalPeerReconciler struct {
	client.Client
	EgressClient     client.Client
	Scheme           *runtime.Scheme
	Image            string
	EgressNamespace  string
	EgressProxyGroup string
	TailnetDomain    string
}

// +kubebuilder:rbac:groups=kura.tuist.dev,resources=kurainstances,verbs=get;list;watch
// +kubebuilder:rbac:groups=apps,resources=daemonsets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=configmaps;services,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch

type nodeLocalPeerRoute struct {
	host    string
	node    string
	backend string
}

type nodeLocalPeerEgress struct {
	name     string
	instance string
	// node is empty while the gateway pod is unscheduled; the Service then
	// keeps the node it last targeted.
	node string
}

type nodeLocalPeerState struct {
	routes       []nodeLocalPeerRoute
	egresses     []nodeLocalPeerEgress
	nodeSelector map[string]string
	tolerations  []corev1.Toleration
	issues       []string
}

func (r *NodeLocalPeerReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("region", req.Name)
	region := req.Name
	namespace := req.Namespace

	instances := &kurav1alpha1.KuraInstanceList{}
	if err := r.List(ctx, instances, client.InNamespace(namespace)); err != nil {
		return ctrl.Result{}, err
	}
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(namespace), client.MatchingLabels{nodeLocalNetworkLabel: "true"}); err != nil {
		return ctrl.Result{}, err
	}

	state := nodeLocalPeerDesiredState(region, r.EgressNamespace, instances.Items, pods.Items)
	for _, issue := range state.issues {
		logger.Error(errors.New(issue), "ignored node-local peer host")
	}

	if err := r.reconcileEgress(ctx, region, state.egresses); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileDemux(ctx, region, namespace, state); err != nil {
		return ctrl.Result{}, err
	}

	logger.V(1).Info("reconciled Kura node-local peer plane", "routes", len(state.routes), "egresses", len(state.egresses))
	return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}

// nodeLocalPeerDesiredState derives, for one region, the demux routes (one per
// instance whose gateway pod has an address) and the egress Services (one per
// instance with a valid PeerHost, whether or not its pod is up yet).
func nodeLocalPeerDesiredState(region, egressNamespace string, instances []kurav1alpha1.KuraInstance, pods []corev1.Pod) nodeLocalPeerState {
	var state nodeLocalPeerState
	var eligible []*kurav1alpha1.KuraInstance
	claimed := map[string]string{}

	sort.Slice(instances, func(i, j int) bool { return peerDemuxInstanceLess(&instances[i], &instances[j]) })
	for i := range instances {
		instance := &instances[i]
		host := nodeLocalPeerHost(instance)
		if instance.Spec.Region != region || host == "" || !instance.DeletionTimestamp.IsZero() {
			continue
		}
		name, err := nodeLocalPeerEgressName(host, egressNamespace)
		if err != nil {
			state.issues = append(state.issues, fmt.Sprintf("%s: %v", instance.Name, err))
			continue
		}
		if owner, ok := claimed[name]; ok {
			state.issues = append(state.issues, fmt.Sprintf("%s: peer host %s is already %s's", instance.Name, host, owner))
			continue
		}
		claimed[name] = instance.Name
		eligible = append(eligible, instance)

		egress := nodeLocalPeerEgress{name: name, instance: instance.Name}
		if pod := nodeLocalPeerGatewayPod(instance, pods); pod != nil {
			egress.node = pod.Spec.NodeName
			state.routes = append(state.routes, nodeLocalPeerRoute{
				host:    host,
				node:    pod.Spec.NodeName,
				backend: fmt.Sprintf("%s:%d", pod.Status.PodIP, peerPort),
			})
		}
		state.egresses = append(state.egresses, egress)
	}

	if len(eligible) > 0 {
		state.nodeSelector = eligible[0].Spec.NodeSelector
		state.tolerations = eligible[0].Spec.Tolerations
	}
	sort.Slice(state.routes, func(i, j int) bool {
		if state.routes[i].node != state.routes[j].node {
			return state.routes[i].node < state.routes[j].node
		}
		return state.routes[i].host < state.routes[j].host
	})
	return state
}

// nodeLocalPeerEgressName is the Service PeerHost names, which has to be a
// Service in the egress namespace: that is the namespace the ProxyGroup's
// egress Services live in and the one this controller may write to there.
func nodeLocalPeerEgressName(host, egressNamespace string) (string, error) {
	if egressNamespace == "" {
		return "", errors.New("no node-local peer egress namespace is configured")
	}
	suffix := "." + egressNamespace + ".svc.cluster.local"
	name, ok := strings.CutSuffix(host, suffix)
	if !ok {
		return "", fmt.Errorf("peer host %s is not a Service in %s", host, egressNamespace)
	}
	if errs := validation.IsDNS1035Label(name); len(errs) > 0 {
		return "", fmt.Errorf("peer host %s does not name a Service: %s", host, strings.Join(errs, "; "))
	}
	return name, nil
}

// nodeLocalPeerGatewayPod is the pod the instance's peer plane forwards to: the
// one its published roles name as gateway, else the lowest-ordinal pod that
// has an address. Only a scheduled pod with an IP qualifies, since the route
// is to that address on that node.
func nodeLocalPeerGatewayPod(instance *kurav1alpha1.KuraInstance, pods []corev1.Pod) *corev1.Pod {
	gatewayURL := ""
	for _, role := range instance.Status.PeerRoles {
		if role.Gateway {
			gatewayURL = role.NodeURL
			break
		}
	}

	var fallback *corev1.Pod
	fallbackOrdinal := 0
	for i := range pods {
		pod := &pods[i]
		if pod.Labels["app.kubernetes.io/instance"] != instance.Name || pod.DeletionTimestamp != nil ||
			pod.Spec.NodeName == "" || pod.Status.PodIP == "" {
			continue
		}
		if gatewayURL != "" && podNodeURL(instance, pod.Name) == gatewayURL {
			return pod
		}
		ordinal, ok := podOrdinal(pod.Name, instance.Name)
		if !ok {
			continue
		}
		if fallback == nil || ordinal < fallbackOrdinal {
			fallback, fallbackOrdinal = pod, ordinal
		}
	}
	return fallback
}

func (r *NodeLocalPeerReconciler) egressConfigured() bool {
	return r.EgressClient != nil && r.EgressNamespace != "" && r.EgressProxyGroup != "" && r.TailnetDomain != ""
}

func (r *NodeLocalPeerReconciler) reconcileEgress(ctx context.Context, region string, egresses []nodeLocalPeerEgress) error {
	if !r.egressConfigured() {
		if len(egresses) > 0 {
			log.FromContext(ctx).Info("node-local peer egress is not configured; other regions cannot reach this region's peers", "region", region)
		}
		return nil
	}

	desired := map[string]bool{}
	for _, egress := range egresses {
		desired[egress.name] = true
		if err := r.applyEgressService(ctx, region, egress); err != nil {
			return err
		}
	}

	existing := &corev1.ServiceList{}
	if err := r.EgressClient.List(ctx, existing, client.InNamespace(r.EgressNamespace), client.MatchingLabels(nodeLocalPeerEgressSelector(region))); err != nil {
		return err
	}
	for i := range existing.Items {
		service := &existing.Items[i]
		if desired[service.Name] {
			continue
		}
		if err := r.EgressClient.Delete(ctx, service); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
	}
	return nil
}

// applyEgressService writes the egress Service for one instance. The Tailscale
// operator rewrites spec.externalName to the ProxyGroup's Service once it has
// configured the proxies, so an existing value is kept rather than stamped
// back.
func (r *NodeLocalPeerReconciler) applyEgressService(ctx context.Context, region string, egress nodeLocalPeerEgress) error {
	service := &corev1.Service{}
	err := r.EgressClient.Get(ctx, types.NamespacedName{Namespace: r.EgressNamespace, Name: egress.name}, service)
	notFound := apierrors.IsNotFound(err)
	if err != nil && !notFound {
		return err
	}
	if notFound {
		if egress.node == "" {
			// Nothing to target yet.
			return nil
		}
		service = &corev1.Service{ObjectMeta: metav1.ObjectMeta{Namespace: r.EgressNamespace, Name: egress.name}}
	} else if !nodeLocalPeerEgressOwnedBy(service, region) {
		return fmt.Errorf("egress Service %s/%s exists and is not this controller's", r.EgressNamespace, egress.name)
	}

	before := service.DeepCopy()
	if service.Labels == nil {
		service.Labels = map[string]string{}
	}
	for key, value := range nodeLocalPeerEgressSelector(region) {
		service.Labels[key] = value
	}
	service.Labels["tuist.dev/kura-instance"] = egress.instance
	if service.Annotations == nil {
		service.Annotations = map[string]string{}
	}
	if egress.node != "" {
		service.Annotations["tailscale.com/tailnet-fqdn"] = egress.node + "." + strings.TrimPrefix(r.TailnetDomain, ".")
	}
	service.Annotations["tailscale.com/proxy-group"] = r.EgressProxyGroup
	service.Spec.Type = corev1.ServiceTypeExternalName
	if service.Spec.ExternalName == "" {
		service.Spec.ExternalName = "placeholder." + r.EgressNamespace + ".svc.cluster.local"
	}
	service.Spec.Ports = []corev1.ServicePort{{Name: "peer", Port: peerPort, Protocol: corev1.ProtocolTCP}}

	if notFound {
		return r.EgressClient.Create(ctx, service)
	}
	if equalServiceIntent(before, service) {
		return nil
	}
	return r.EgressClient.Update(ctx, service)
}

func equalServiceIntent(left, right *corev1.Service) bool {
	return fmt.Sprint(left.Labels) == fmt.Sprint(right.Labels) &&
		fmt.Sprint(left.Annotations) == fmt.Sprint(right.Annotations) &&
		left.Spec.Type == right.Spec.Type &&
		left.Spec.ExternalName == right.Spec.ExternalName &&
		fmt.Sprint(left.Spec.Ports) == fmt.Sprint(right.Spec.Ports)
}

func nodeLocalPeerEgressSelector(region string) map[string]string {
	return map[string]string{
		"app.kubernetes.io/managed-by": "kura-controller",
		"app.kubernetes.io/component":  nodeLocalPeerEgressComponent,
		"tuist.dev/region":             region,
	}
}

func nodeLocalPeerEgressOwnedBy(service *corev1.Service, region string) bool {
	for key, value := range nodeLocalPeerEgressSelector(region) {
		if service.Labels[key] != value {
			return false
		}
	}
	return true
}

func (r *NodeLocalPeerReconciler) reconcileDemux(ctx context.Context, region, namespace string, state nodeLocalPeerState) error {
	name := nodeLocalPeerDemuxName(region)
	configMap := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: namespace}}
	daemonSet := &appsv1.DaemonSet{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: namespace}}

	if len(state.egresses) == 0 {
		if err := r.Delete(ctx, daemonSet); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
		if err := r.Delete(ctx, configMap); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
		return nil
	}

	files := nodeLocalPeerDemuxConfigs(state.routes)
	if _, err := controllerutil.CreateOrUpdate(ctx, r.Client, configMap, func() error {
		configMap.Labels = nodeLocalPeerDemuxLabels(region)
		configMap.Data = files
		return nil
	}); err != nil {
		return err
	}

	configHash := nodeLocalPeerConfigHash(files)
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, daemonSet, func() error {
		daemonSet.Labels = nodeLocalPeerDemuxLabels(region)
		daemonSet.Spec.Selector = &metav1.LabelSelector{MatchLabels: nodeLocalPeerDemuxSelectorLabels(region)}
		daemonSet.Spec.Template = nodeLocalPeerDemuxPodTemplate(region, name, configHash, state.nodeSelector, state.tolerations, r.image())
		return nil
	})
	return err
}

// nodeLocalPeerDemuxConfigs renders one nginx config per node that holds a
// route, plus a default with none for the region's other nodes. A route is a
// pod IP on one node's bridge, and every rack node numbers its bridge the same
// way, so a node must only ever forward to its own pods: the same address on
// another node is somebody else's pod.
func nodeLocalPeerDemuxConfigs(routes []nodeLocalPeerRoute) map[string]string {
	byNode := map[string][]nodeLocalPeerRoute{}
	for _, route := range routes {
		byNode[route.node] = append(byNode[route.node], route)
	}
	files := map[string]string{nodeLocalPeerDefaultConfig: nodeLocalPeerNginxConf(nil)}
	for node, nodeRoutes := range byNode {
		files[node+".conf"] = nodeLocalPeerNginxConf(nodeRoutes)
	}
	return files
}

// nodeLocalPeerNginxConf routes each peer host's SNI to a pod address. Unknown
// SNI maps to an empty backend, which nginx closes. The backends are
// addresses, so unlike the regional demux no resolver is involved: a rack
// node resolves no cluster name.
func nodeLocalPeerNginxConf(routes []nodeLocalPeerRoute) string {
	var b strings.Builder
	b.WriteString("worker_processes auto;\n")
	b.WriteString("error_log /dev/stderr warn;\n")
	b.WriteString("pid /tmp/nginx.pid;\n")
	b.WriteString("events {\n  worker_connections 4096;\n}\n")
	b.WriteString("stream {\n")
	fmt.Fprintf(&b, "  map_hash_bucket_size %d;\n", peerDemuxMapHashBucketSize)
	fmt.Fprintf(&b, "  map_hash_max_size %d;\n", peerDemuxMapHashMaxSize)
	b.WriteString("  map $ssl_preread_server_name $kura_peer_backend {\n")
	b.WriteString("    default \"\";\n")
	for _, route := range routes {
		fmt.Fprintf(&b, "    %s %s;\n", route.host, route.backend)
	}
	b.WriteString("  }\n")
	b.WriteString("  server {\n")
	fmt.Fprintf(&b, "    listen %d;\n", peerDemuxPort)
	b.WriteString("    ssl_preread on;\n")
	b.WriteString("    proxy_pass $kura_peer_backend;\n")
	b.WriteString("    proxy_connect_timeout 5s;\n")
	b.WriteString("    proxy_timeout 10m;\n")
	b.WriteString("  }\n")
	b.WriteString("}\n")
	return b.String()
}

func nodeLocalPeerConfigHash(files map[string]string) string {
	keys := make([]string, 0, len(files))
	for key := range files {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	hash := sha256.New()
	for _, key := range keys {
		fmt.Fprintf(hash, "%s\x00%s\x00", key, files[key])
	}
	return fmt.Sprintf("%x", hash.Sum(nil))
}

// nodeLocalPeerDemuxScript starts nginx on the node's own config, or on the
// route-less default when the node holds none of the region's pods.
const nodeLocalPeerDemuxScript = `conf="` + nodeLocalPeerConfigDir + `/${NODE_NAME}.conf"
[ -f "$conf" ] || conf="` + nodeLocalPeerConfigDir + `/` + nodeLocalPeerDefaultConfig + `"
exec nginx -c "$conf" -g 'daemon off;'
`

func nodeLocalPeerDemuxPodTemplate(region, name, configHash string, nodeSelector map[string]string, tolerations []corev1.Toleration, image string) corev1.PodTemplateSpec {
	return corev1.PodTemplateSpec{
		ObjectMeta: metav1.ObjectMeta{
			Labels:      nodeLocalPeerDemuxSelectorLabels(region),
			Annotations: map[string]string{nodeLocalPeerConfigHashAnnotation: configHash},
		},
		Spec: corev1.PodSpec{
			EnableServiceLinks: ptr(false),
			HostNetwork:        true,
			// The node's own resolver: a rack node has no route to cluster
			// DNS, and the config resolves nothing anyway.
			DNSPolicy:    corev1.DNSDefault,
			NodeSelector: nodeSelector,
			Tolerations:  tolerations,
			Containers: []corev1.Container{{
				Name:            "demux",
				Image:           image,
				ImagePullPolicy: corev1.PullIfNotPresent,
				Command:         []string{"/bin/sh", "-c", nodeLocalPeerDemuxScript},
				Env: []corev1.EnvVar{{
					Name:      "NODE_NAME",
					ValueFrom: &corev1.EnvVarSource{FieldRef: &corev1.ObjectFieldSelector{FieldPath: "spec.nodeName"}},
				}},
				Ports: []corev1.ContainerPort{
					{Name: "peer", ContainerPort: peerDemuxPort, Protocol: corev1.ProtocolTCP},
				},
				VolumeMounts: []corev1.VolumeMount{
					{Name: "config", MountPath: nodeLocalPeerConfigDir, ReadOnly: true},
				},
				ReadinessProbe: &corev1.Probe{
					ProbeHandler: corev1.ProbeHandler{
						TCPSocket: &corev1.TCPSocketAction{Port: intstr.FromInt(peerDemuxPort)},
					},
					InitialDelaySeconds: 5,
					PeriodSeconds:       10,
				},
				Resources: corev1.ResourceRequirements{
					Requests: corev1.ResourceList{
						corev1.ResourceCPU:    resource.MustParse("50m"),
						corev1.ResourceMemory: resource.MustParse("64Mi"),
					},
					Limits: corev1.ResourceList{
						corev1.ResourceMemory: resource.MustParse("256Mi"),
					},
				},
			}},
			Volumes: []corev1.Volume{{
				Name: "config",
				VolumeSource: corev1.VolumeSource{
					ConfigMap: &corev1.ConfigMapVolumeSource{
						LocalObjectReference: corev1.LocalObjectReference{Name: name},
					},
				},
			}},
		},
	}
}

func (r *NodeLocalPeerReconciler) image() string {
	if strings.TrimSpace(r.Image) != "" {
		return strings.TrimSpace(r.Image)
	}
	return defaultPeerDemuxImage
}

func nodeLocalPeerDemuxName(region string) string {
	return "kura-node-local-peer-" + region
}

func nodeLocalPeerDemuxLabels(region string) map[string]string {
	labels := nodeLocalPeerDemuxSelectorLabels(region)
	labels["app.kubernetes.io/managed-by"] = "kura-controller"
	labels["tuist.dev/region"] = region
	return labels
}

func nodeLocalPeerDemuxSelectorLabels(region string) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":      "kura-node-local-peer",
		"app.kubernetes.io/component": "node-local-peer-demux",
		"app.kubernetes.io/instance":  region,
	}
}

// nodeLocalPeerRegionRequests maps an instance, one of its pods, or a demux
// DaemonSet to the region it belongs to.
func nodeLocalPeerRegionRequests(_ context.Context, obj client.Object) []reconcile.Request {
	region := ""
	switch object := obj.(type) {
	case *kurav1alpha1.KuraInstance:
		if object.Spec.NodeLocalNetwork == nil {
			return nil
		}
		region = object.Spec.Region
	case *corev1.Pod:
		if object.Labels[nodeLocalNetworkLabel] != "true" {
			return nil
		}
		region = object.Labels["tuist.dev/region"]
	case *appsv1.DaemonSet:
		if object.Labels["app.kubernetes.io/name"] != "kura-node-local-peer" {
			return nil
		}
		region = object.Labels["tuist.dev/region"]
	}
	if region == "" {
		return nil
	}
	return []reconcile.Request{{NamespacedName: types.NamespacedName{Name: region, Namespace: obj.GetNamespace()}}}
}

// nodeLocalPeerRoutingChanged lets a node-local pod through when what a route
// is built from changes: its address, its node, or its deletion.
func nodeLocalPeerRoutingChanged() predicate.Predicate {
	return predicate.Funcs{
		CreateFunc:  func(event.CreateEvent) bool { return true },
		DeleteFunc:  func(event.DeleteEvent) bool { return true },
		GenericFunc: func(event.GenericEvent) bool { return false },
		UpdateFunc: func(e event.UpdateEvent) bool {
			oldPod, ok := e.ObjectOld.(*corev1.Pod)
			newPod, okNew := e.ObjectNew.(*corev1.Pod)
			if !ok || !okNew {
				return false
			}
			return oldPod.Status.PodIP != newPod.Status.PodIP ||
				oldPod.Spec.NodeName != newPod.Spec.NodeName ||
				oldPod.DeletionTimestamp.IsZero() != newPod.DeletionTimestamp.IsZero()
		},
	}
}

// nodeLocalPeerInstanceChanged also passes status updates, because the
// published gateway role decides which pod the plane forwards to.
func nodeLocalPeerInstanceChanged() predicate.Predicate {
	return predicate.Funcs{
		CreateFunc:  func(event.CreateEvent) bool { return true },
		DeleteFunc:  func(event.DeleteEvent) bool { return true },
		GenericFunc: func(event.GenericEvent) bool { return false },
		UpdateFunc: func(e event.UpdateEvent) bool {
			oldInstance, ok := e.ObjectOld.(*kurav1alpha1.KuraInstance)
			newInstance, okNew := e.ObjectNew.(*kurav1alpha1.KuraInstance)
			if !ok || !okNew {
				return false
			}
			return oldInstance.Generation != newInstance.Generation ||
				oldInstance.DeletionTimestamp.IsZero() != newInstance.DeletionTimestamp.IsZero() ||
				!peerRolesEqual(oldInstance.Status.PeerRoles, newInstance.Status.PeerRoles)
		},
	}
}

func (r *NodeLocalPeerReconciler) SetupWithManager(mgr ctrl.Manager) error {
	regionRequests := handler.EnqueueRequestsFromMapFunc(nodeLocalPeerRegionRequests)
	return ctrl.NewControllerManagedBy(mgr).
		Named("node-local-peer").
		Watches(&kurav1alpha1.KuraInstance{}, regionRequests, builder.WithPredicates(nodeLocalPeerInstanceChanged())).
		Watches(&corev1.Pod{}, regionRequests, builder.WithPredicates(nodeLocalPeerRoutingChanged())).
		Watches(&appsv1.DaemonSet{}, regionRequests, builder.WithPredicates(predicate.GenerationChangedPredicate{})).
		Complete(r)
}
