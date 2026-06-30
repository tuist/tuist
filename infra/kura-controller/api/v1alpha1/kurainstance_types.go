package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type KuraInstanceSpec struct {
	AccountHandle string `json:"accountHandle"`
	TenantID      string `json:"tenantID"`
	Region        string `json:"region"`
	Image         string `json:"image"`
	Replicas      *int32 `json:"replicas,omitempty"`
	PublicHost    string `json:"publicHost,omitempty"`
	// Deprecated: the value is ignored. gRPC co-hosts on PublicHost (see
	// reconcileGRPCIngress), and PublicHost alone enables the gRPC Ingress.
	// Retained for backward compatibility.
	// See https://github.com/tuist/tuist/issues/11390.
	GRPCPublicHost    string            `json:"grpcPublicHost,omitempty"`
	IngressClassName  string            `json:"ingressClassName,omitempty"`
	PeerTLSSecretName string            `json:"peerTLSSecretName,omitempty"`
	StorageClassName  string            `json:"storageClassName,omitempty"`
	StorageSize       string            `json:"storageSize,omitempty"`
	NodeSelector      map[string]string `json:"nodeSelector,omitempty"`
	// Tolerations let the runtime pod schedule onto tainted nodes. Preview
	// environments use this to colocate Kura on the generic preview pool
	// (which carries role=preview:NoSchedule) instead of pinning to a
	// dedicated Kura node pool, so the preview lifecycle does not depend on
	// Kura-specific capacity.
	Tolerations     []corev1.Toleration `json:"tolerations,omitempty"`
	ExtraEnv        []corev1.EnvVar     `json:"extraEnv,omitempty"`
	ExtensionScript string              `json:"extensionScript,omitempty"`

	// Private marks a region with no public endpoint, reachable only
	// over the cluster's internal Service DNS (today: the runner-cache
	// regions, serving an in-cluster runner fleet). When true the
	// controller leaves the public/gRPC Ingress and Certificate
	// unreconciled and the primary Service stays ClusterIP — there is
	// no public host to advertise, and the runner Pods reach the cache
	// at `<instance>.<namespace>.svc.cluster.local`.
	Private bool `json:"private,omitempty"`

	// ExposeNodePort additionally publishes http/grpc through a
	// NodePort Service (`<instance>-external`) pinned to the primary
	// pod with externalTrafficPolicy: Local. This is the data plane
	// for runner fleets that share an L2/L3 network with the
	// instance's node pool but are NOT on the cluster's pod network —
	// the macOS Tart VMs reach the pool over a cloud Private Network,
	// where ClusterIP DNS doesn't resolve and isn't routed. Traffic
	// must enter on the node hosting the pod; status.NodeAddress +
	// status.NodePortHTTP are what dispatch hands those clients.
	ExposeNodePort bool `json:"exposeNodePort,omitempty"`

	// ClientCIDRs are source ranges allowed to reach http/grpc in
	// addition to in-cluster namespaces. NodePort clients arrive with
	// their original source IP (externalTrafficPolicy: Local), which
	// no namespaceSelector matches — without an ipBlock rule the
	// instance NetworkPolicy drops them.
	ClientCIDRs []string `json:"clientCIDRs,omitempty"`

	// PodAnnotations are merged into the pod template (controller-owned
	// annotations win). Used per region for traffic shaping, e.g.
	// `kubernetes.io/egress-bandwidth` on pools whose node NIC is
	// shared by many tenants.
	PodAnnotations map[string]string `json:"podAnnotations,omitempty"`

	// EgressGuaranteedMbps is the per-tenant egress floor, in Mbps, this
	// instance reserves on a shared bare-metal box. When set, the pod requests
	// it as the `tuist.dev/egress-mbps` extended resource (request == limit;
	// extended resources are integer and non-overcommittable), so the scheduler
	// bin-packs instances against the node's advertised egress budget (the CAPI
	// provider patches matching node capacity from the box's EgressBudgetMbps).
	// Pairs with the `kubernetes.io/egress-bandwidth` PodAnnotation, which is the
	// burst ceiling. Zero on cloud regions whose NIC isn't shared.
	EgressGuaranteedMbps int32 `json:"egressGuaranteedMbps,omitempty"`

	// Mesh enables controller-managed cross-region peering for this
	// instance. The controller maintains a per-account CA
	// (`kura-<account>-peer-ca`) and signs a leaf for the instance whose
	// SANs cover the account peer Service, so every one of an account's
	// instances mutually authenticates while another account's leaf
	// (signed by a different CA) is rejected at the TLS layer. Each
	// account's pods then discover and replicate to each other through
	// the account peer Service (`KURA_GLOBAL_DISCOVERY_DNS_NAME`).
	// `PeerTLSSecretName` takes precedence when set (externally managed
	// peer TLS); Mesh is the in-cluster, controller-issued path.
	Mesh bool `json:"mesh,omitempty"`

	// MeshPublicPeerHost is the public hostname the account peer plane is
	// reachable at from outside the cluster. When set (Mesh mode), the
	// controller provisions a LoadBalancer Service for the account peer
	// port (TLS-passthrough: the peer connection is end-to-end mTLS, so the
	// LB only forwards L4) and adds the host to every managed instance's
	// peer-cert SAN. That lets a customer's self-hosted Kura node dial into
	// the managed mesh over the internet and verify the managed peers
	// against the shared account CA. The reverse leg (managed dialing the
	// self-hosted nodes) is `MeshExternalPeers`.
	MeshPublicPeerHost string `json:"meshPublicPeerHost,omitempty"`

	// MeshExternalPeers are peer URLs of the account's self-hosted Kura
	// nodes, injected into every managed pod's `KURA_PEERS` so the managed
	// mesh dials them for replication (the managed->self-hosted leg of
	// two-way cross-mesh replication). The self-hosted->managed leg is
	// seeded server-side through the enrollment peer list. Requires Mesh.
	MeshExternalPeers []string `json:"meshExternalPeers,omitempty"`

	// MeshPublicPeerLoadBalancerAnnotations are provider-specific annotations
	// applied to the public peer LoadBalancer Service. They are infra/region
	// specific (e.g. the hcloud `location` and a `node-selector` restricting the
	// LB's targets to the account's node pool — without the latter the cloud
	// controller targets every node, including ones that can't route to the
	// account's pods), so the control plane supplies them.
	MeshPublicPeerLoadBalancerAnnotations map[string]string `json:"meshPublicPeerLoadBalancerAnnotations,omitempty"`
}

type KuraInstanceStatus struct {
	Phase            string       `json:"phase,omitempty"`
	PublicURL        string       `json:"publicURL,omitempty"`
	GRPCPublicURL    string       `json:"grpcPublicURL,omitempty"`
	ObservedImage    string       `json:"observedImage,omitempty"`
	ReadyReplicas    int32        `json:"readyReplicas,omitempty"`
	Message          string       `json:"message,omitempty"`
	LastReconciledAt *metav1.Time `json:"lastReconciledAt,omitempty"`

	// NodePort exposure (spec.exposeNodePort): the address clients
	// outside the pod network dial. NodeAddress is the
	// `tuist.dev/pn-ipv4` label of the node hosting the primary pod —
	// its Private-Network address, not a public one — and moves when
	// the pod reschedules. Empty until the Service has allocated
	// ports and the primary pod is placed on a labeled node.
	NodeAddress  string `json:"nodeAddress,omitempty"`
	NodePortHTTP int32  `json:"nodePortHTTP,omitempty"`
	NodePortGRPC int32  `json:"nodePortGRPC,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=kurainstances,scope=Namespaced,shortName=kura
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="Host",type=string,JSONPath=".spec.publicHost"
// +kubebuilder:printcolumn:name="Ready",type=integer,JSONPath=".status.readyReplicas"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"
type KuraInstance struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   KuraInstanceSpec   `json:"spec,omitempty"`
	Status KuraInstanceStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type KuraInstanceList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []KuraInstance `json:"items"`
}

func init() {
	SchemeBuilder.Register(&KuraInstance{}, &KuraInstanceList{})
}
