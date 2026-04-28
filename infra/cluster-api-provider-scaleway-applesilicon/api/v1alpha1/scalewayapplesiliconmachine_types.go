package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// ScalewayAppleSiliconMachineSpec is the desired state of one Mac mini.
type ScalewayAppleSiliconMachineSpec struct {
	// ProviderID, set by the controller after provisioning, takes the
	// shape `scw-applesilicon://<zone>/<server-id>`. CAPI core expects
	// this to populate; without it the parent Machine never goes Ready.
	// +optional
	ProviderID *string `json:"providerID,omitempty"`

	// Type is Scaleway's Mac mini SKU (M2-M, M2-L, M2-Pro-M, etc.).
	// Defaults to M2-M (mid-tier; balance of cost vs CI throughput).
	// +kubebuilder:default=M2-M
	Type string `json:"type,omitempty"`

	// Zone is the Scaleway zone (fr-par-3, nl-ams-3, etc.).
	// +kubebuilder:default=fr-par-3
	Zone string `json:"zone,omitempty"`

	// OS is the Scaleway-provided macOS image name. The controller
	// resolves this to an OS UUID via `scw apple-silicon os list`.
	// +kubebuilder:default=macos-tahoe-26.0
	OS string `json:"os,omitempty"`

	// PodCIDR is the per-host CIDR slice this Mac mini's CNI plugin
	// hands out to Pods. Cluster operators carve the cluster CIDR
	// (e.g. 10.42.0.0/16) into per-machine /24s and set this field
	// per-Machine — there's no automatic IPAM at this layer.
	PodCIDR string `json:"podCIDR"`

	// SSHKeySecretRef points at a Secret with `id_ed25519` containing
	// the private key the controller uses to SSH into the Mac mini
	// during bootstrap. Public half must already be associated with
	// the Scaleway tenant so it lands in the host's
	// ~/.ssh/authorized_keys at first boot.
	SSHKeySecretRef SecretReference `json:"sshKeySecretRef"`

	// BootstrapSecretRef points at a Secret with the cluster join
	// material (`bootstrap-token`, `api-server`, `ca-cert-data`).
	// The controller writes a kubelet bootstrap kubeconfig from
	// these values when provisioning each machine.
	BootstrapSecretRef SecretReference `json:"bootstrapSecretRef"`
}

// SecretReference is a typed reference to a Secret in the same namespace.
type SecretReference struct {
	Name string `json:"name"`
}

// ScalewayAppleSiliconMachineStatus is the observed state of the Machine.
type ScalewayAppleSiliconMachineStatus struct {
	// Ready is set to true once the Mac mini has joined the cluster
	// and the corresponding Node object reports Ready=True. CAPI core
	// reads this to mark the parent Machine Ready.
	// +optional
	Ready bool `json:"ready,omitempty"`

	// ServerID is the Scaleway-assigned UUID for the underlying Mac
	// mini. The Machine reconciler uses this for delete + status
	// polling against Scaleway's API.
	// +optional
	ServerID string `json:"serverID,omitempty"`

	// Addresses surfaces the IP and the Scaleway-assigned hostname so
	// kubectl describe / event correlation can map back to the host.
	// +optional
	Addresses []clusterv1.MachineAddress `json:"addresses,omitempty"`

	// Phase tracks lifecycle: Pending | Provisioning | Bootstrapping |
	// Ready | Deleting | Failed. Operator-facing only; CAPI core
	// drives off Ready + Conditions.
	// +optional
	Phase string `json:"phase,omitempty"`

	// FailureReason / FailureMessage are set on terminal failures. CAPI
	// core surfaces them on the Machine object and prevents auto-retry.
	// +optional
	FailureReason *string `json:"failureReason,omitempty"`
	// +optional
	FailureMessage *string `json:"failureMessage,omitempty"`

	// Conditions are CAPI-style condition entries (Provisioned,
	// Bootstrapped, NodeReady).
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=scalewayapplesiliconmachines,scope=Namespaced,categories=cluster-api,shortName=samm
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="ProviderID",type=string,JSONPath=".spec.providerID"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.ready"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// ScalewayAppleSiliconMachine is one Mac mini in the cluster.
type ScalewayAppleSiliconMachine struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ScalewayAppleSiliconMachineSpec   `json:"spec,omitempty"`
	Status ScalewayAppleSiliconMachineStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// ScalewayAppleSiliconMachineList is a list of ScalewayAppleSiliconMachine.
type ScalewayAppleSiliconMachineList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ScalewayAppleSiliconMachine `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ScalewayAppleSiliconMachine{}, &ScalewayAppleSiliconMachineList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter
// interface so the controller can use util/conditions helpers.
func (m *ScalewayAppleSiliconMachine) GetConditions() clusterv1.Conditions {
	return m.Status.Conditions
}

func (m *ScalewayAppleSiliconMachine) SetConditions(c clusterv1.Conditions) {
	m.Status.Conditions = c
}
