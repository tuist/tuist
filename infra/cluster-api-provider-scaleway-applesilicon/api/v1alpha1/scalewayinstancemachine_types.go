package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// ScalewayInstanceMachineSpec is the desired state of one regular Scaleway
// Instance (a Linux x86/ARM server, not an Apple Silicon Mac mini). Unlike
// the Apple Silicon kind, Instances are created on demand through the
// Instance API rather than adopted from a pre-ordered pool, and they join
// the cluster as ordinary Linux worker Nodes via kubeadm.
type ScalewayInstanceMachineSpec struct {
	// ProviderID, set by the controller after provisioning, takes the
	// shape `scaleway://instance/<zone>/<server-id>` — the same foreign
	// providerID a hand-join uses so the Hetzner CCM never reaps the
	// node. CAPI core expects this to populate; without it the parent
	// Machine never goes Ready.
	// +optional
	ProviderID *string `json:"providerID,omitempty"`

	// CommercialType is the Scaleway Instance SKU (e.g. PRO2-S,
	// POP2-HC-16C-32G). Defaults to PRO2-S — the staging kura
	// runner-cache shape.
	// +kubebuilder:default=PRO2-S
	CommercialType string `json:"commercialType,omitempty"`

	// Zone is the Scaleway zone (fr-par-1, fr-par-2, ...).
	// +kubebuilder:default=fr-par-1
	Zone string `json:"zone,omitempty"`

	// Image is the Scaleway image label the root volume is created from.
	// Resolved to an image UUID for the instance's architecture.
	// +kubebuilder:default=ubuntu_noble
	Image string `json:"image,omitempty"`

	// RootVolumeGB sizes the root block volume.
	// +kubebuilder:default=50
	RootVolumeGB int `json:"rootVolumeGB,omitempty"`

	// PrivateNetworkID is the Scaleway VPC Private Network the instance is
	// attached to before bootstrap. The kura runner-cache pool reaches the
	// Mac fleet over this PN; the controller reads the PN-assigned address
	// to set the node's `tuist.dev/pn-ipv4` label after it registers.
	// +optional
	PrivateNetworkID string `json:"privateNetworkID,omitempty"`
}

// Bootstrap, node labels, and taints are deliberately NOT on this spec.
// The instance joins via a standard CAPI KubeadmConfigTemplate: the kubeadm
// bootstrap provider renders the join cloud-init (token, CA hash, join
// endpoint, `nodeRegistration` labels + taints) into the Machine's bootstrap
// data Secret, and the reconciler passes that as the instance's cloud-init
// user-data. Static labels/taints (pool, runner-cache) live in that template;
// the dynamic `tuist.dev/pn-ipv4` label is patched onto the Node by the
// controller once the PN address is known.

// ScalewayInstanceMachineStatus is the observed state of the Machine.
type ScalewayInstanceMachineStatus struct {
	// Ready is true once the instance has joined the cluster and its Node
	// reports Ready=True. CAPI core reads this to mark the parent Machine
	// Ready.
	// +optional
	Ready bool `json:"ready,omitempty"`

	// ServerID is the Scaleway-assigned UUID for the underlying instance,
	// used for delete + status polling.
	// +optional
	ServerID string `json:"serverID,omitempty"`

	// Addresses surfaces the instance's public, PN, and hostname
	// addresses for kubectl describe / event correlation.
	// +optional
	Addresses []clusterv1.MachineAddress `json:"addresses,omitempty"`

	// Phase tracks lifecycle: Pending | Provisioning | Bootstrapping |
	// Ready | Deleting | Failed. Operator-facing only; CAPI core drives
	// off Ready + Conditions.
	// +optional
	Phase string `json:"phase,omitempty"`

	// FailureReason / FailureMessage are set on terminal failures.
	// +optional
	FailureReason *string `json:"failureReason,omitempty"`
	// +optional
	FailureMessage *string `json:"failureMessage,omitempty"`

	// Conditions are CAPI-style condition entries (Provisioned,
	// Bootstrapped, NodeReady).
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`

	// BootstrapAttempts counts consecutive bootstrap failures on the
	// current instance. Reset on a successful bootstrap or whenever the
	// underlying ServerID changes. Drives tiered recovery (reboot, then
	// re-create) in the BootstrapFailed path.
	// +optional
	BootstrapAttempts int32 `json:"bootstrapAttempts,omitempty"`

	// BootstrapRebootIssued records that a recovery reboot has already
	// been triggered for the current instance, so retries don't re-reboot
	// it. Cleared when the ServerID changes or on successful bootstrap.
	// +optional
	BootstrapRebootIssued bool `json:"bootstrapRebootIssued,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=scalewayinstancemachines,scope=Namespaced,categories=cluster-api,shortName=sim
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="ProviderID",type=string,JSONPath=".spec.providerID"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.ready"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// ScalewayInstanceMachine is one regular Scaleway Instance in the cluster.
type ScalewayInstanceMachine struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ScalewayInstanceMachineSpec   `json:"spec,omitempty"`
	Status ScalewayInstanceMachineStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// ScalewayInstanceMachineList is a list of ScalewayInstanceMachine.
type ScalewayInstanceMachineList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ScalewayInstanceMachine `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ScalewayInstanceMachine{}, &ScalewayInstanceMachineList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter
// interface so the controller can use util/conditions helpers.
func (m *ScalewayInstanceMachine) GetConditions() clusterv1.Conditions {
	return m.Status.Conditions
}

func (m *ScalewayInstanceMachine) SetConditions(c clusterv1.Conditions) {
	m.Status.Conditions = c
}
