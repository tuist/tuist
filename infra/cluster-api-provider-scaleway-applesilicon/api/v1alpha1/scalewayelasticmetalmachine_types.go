package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// ScalewayElasticMetalMachineSpec is the desired state of one Scaleway
// Elastic Metal (bare-metal) server. Unlike the Instance kind, Elastic Metal
// servers are ordered through the Baremetal API and pass through an OS-install
// step (~30-60 min) before they are reachable; like the Instance kind they
// then join as ordinary Linux worker Nodes via a provider-generated self-join
// cloud-init. The runner-cache pool uses these for their 10G+ Private Network
// NIC and local NVMe — a regenerable cache wants fast local disk, and Elastic
// Metal can't attach scw-bssd anyway. Benchmarked at ~4.4-6.5x the PRO2-S
// sustained PN throughput with no token-bucket clamp (see PR #11256).
type ScalewayElasticMetalMachineSpec struct {
	// ProviderID, set by the controller after provisioning, takes the shape
	// `scaleway://baremetal/<zone>/<server-id>` — the same foreign providerID
	// shape the Instance kind uses so the Hetzner CCM never reaps the node.
	// CAPI core expects this to populate; without it the parent Machine never
	// goes Ready.
	// +optional
	ProviderID *string `json:"providerID,omitempty"`

	// OfferType is the Elastic Metal offer name (e.g. EM-B220E-NVME,
	// EM-B320E-NVME, EM-I220E-NVME). Defaults to EM-B220E-NVME — the
	// benchmarked 10G-PN / local-NVMe runner-cache shape.
	// +kubebuilder:default=EM-B220E-NVME
	OfferType string `json:"offerType,omitempty"`

	// Zone is the Scaleway zone (fr-par-1, fr-par-2, ...).
	// +kubebuilder:default=fr-par-1
	Zone string `json:"zone,omitempty"`

	// OS is the Baremetal OS label the install uses, resolved to an os-id
	// compatible with the offer at provision time.
	// +kubebuilder:default=ubuntu_noble
	OS string `json:"os,omitempty"`

	// PrivateNetworkID is the Scaleway VPC Private Network the server is
	// attached to. Elastic Metal delivers the PN as a tagged VLAN on the
	// primary NIC (not an auto-configured second interface like Instances),
	// so the controller records the attachment's VLAN in status and the
	// self-join cloud-init materializes the VLAN interface and DHCPs it to
	// pick up the PN address.
	// +optional
	PrivateNetworkID string `json:"privateNetworkID,omitempty"`

	// NodeTaints are passed to the kubelet's `--register-with-taints` in the
	// generated join cloud-init. The kura runner-cache pool carries
	// `tuist.dev/runner-cache=true:NoSchedule` here so only the cache pods
	// (which tolerate it) land on the shared-NIC node.
	// +optional
	NodeTaints []corev1.Taint `json:"nodeTaints,omitempty"`
}

// Bootstrap is provider-generated, identical in shape to the Instance kind:
// the reconciler mints a kubelet token kubeconfig and renders a cloud-init
// that installs kubelet and self-registers the node against the externally
// managed control plane. The bare-metal differences the controller handles
// are the OS-install wait (Status.Phase = Installing), the `ubuntu` install
// user (not root, with sudo), and bringing up the PN as a VLAN interface from
// Status.PrivateNetworkVLAN before the kubelet starts so the
// `tuist.dev/pn-ipv4` label and cache traffic have a path.

// ScalewayElasticMetalMachineStatus is the observed state of the Machine.
type ScalewayElasticMetalMachineStatus struct {
	// Ready is true once the server has joined the cluster and its Node
	// reports Ready=True. CAPI core reads this to mark the parent Machine
	// Ready.
	// +optional
	Ready bool `json:"ready,omitempty"`

	// ServerID is the Scaleway-assigned UUID for the underlying Elastic Metal
	// server, used for install polling, delete, and status.
	// +optional
	ServerID string `json:"serverID,omitempty"`

	// PrivateNetworkVLAN is the VLAN ID Scaleway assigned to this server's PN
	// attachment. Fed into the self-join cloud-init so the host brings up the
	// VLAN interface and DHCPs its PN address. Zero until the attachment is
	// resolved; the controller requeues until Scaleway stamps it.
	// +optional
	PrivateNetworkVLAN uint32 `json:"privateNetworkVLAN,omitempty"`

	// Addresses surfaces the server's public, PN, and hostname addresses for
	// kubectl describe / event correlation.
	// +optional
	Addresses []clusterv1.MachineAddress `json:"addresses,omitempty"`

	// Phase tracks lifecycle: Pending | Ordered | Installing | Provisioning |
	// Bootstrapping | Ready | Deleting | Failed. The Ordered/Installing phases
	// cover the bare-metal OS install the Instance kind doesn't have.
	// Operator-facing only; CAPI core drives off Ready + Conditions.
	// +optional
	Phase string `json:"phase,omitempty"`

	// FailureReason / FailureMessage are set on terminal failures.
	// +optional
	FailureReason *string `json:"failureReason,omitempty"`
	// +optional
	FailureMessage *string `json:"failureMessage,omitempty"`

	// Conditions are CAPI-style condition entries (Provisioned, Installed,
	// Bootstrapped, NodeReady).
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`

	// BootstrapAttempts counts consecutive bootstrap failures on the current
	// server. Reset on a successful bootstrap or whenever the underlying
	// ServerID changes. Drives tiered recovery in the BootstrapFailed path.
	// +optional
	BootstrapAttempts int32 `json:"bootstrapAttempts,omitempty"`

	// BootstrapRebootIssued records that a recovery reboot has already been
	// triggered for the current server, so retries don't re-reboot it.
	// Cleared when the ServerID changes or on successful bootstrap.
	// +optional
	BootstrapRebootIssued bool `json:"bootstrapRebootIssued,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=scalewayelasticmetalmachines,scope=Namespaced,categories=cluster-api,shortName=semm
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="ProviderID",type=string,JSONPath=".spec.providerID"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.ready"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// ScalewayElasticMetalMachine is one Scaleway Elastic Metal server in the
// cluster.
type ScalewayElasticMetalMachine struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ScalewayElasticMetalMachineSpec   `json:"spec,omitempty"`
	Status ScalewayElasticMetalMachineStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// ScalewayElasticMetalMachineList is a list of ScalewayElasticMetalMachine.
type ScalewayElasticMetalMachineList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ScalewayElasticMetalMachine `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ScalewayElasticMetalMachine{}, &ScalewayElasticMetalMachineList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter
// interface so the controller can use util/conditions helpers.
func (m *ScalewayElasticMetalMachine) GetConditions() clusterv1.Conditions {
	return m.Status.Conditions
}

func (m *ScalewayElasticMetalMachine) SetConditions(c clusterv1.Conditions) {
	m.Status.Conditions = c
}
