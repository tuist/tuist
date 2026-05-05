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

	// Type is Scaleway's Mac mini SKU (M1-M, M4-S, M4-M, etc.).
	// Defaults to M4-S: only zone fr-par-1 currently carries M2/M4
	// SKUs (fr-par-3 has M1-M only and it's been unstocked).
	// +kubebuilder:default=M4-S
	Type string `json:"type,omitempty"`

	// Zone is the Scaleway zone (fr-par-1, fr-par-3, etc.).
	// +kubebuilder:default=fr-par-1
	Zone string `json:"zone,omitempty"`

	// OS is the Scaleway-provided macOS image name. The controller
	// resolves this to an OS UUID via `scw apple-silicon os list`.
	// +kubebuilder:default=macos-tahoe-26.0
	OS string `json:"os,omitempty"`

	// FleetName groups Machines that share an SSH key. Set by the
	// MachineTemplate (typically to the parent MachineDeployment's
	// name). The operator generates one Ed25519 keypair per fleet,
	// registers the public half with Scaleway via the IAM API, and
	// stores the private half in `<fleetName>-ssh` so all Machines
	// in the fleet share the same operator-held credential.
	// +optional
	FleetName string `json:"fleetName,omitempty"`

	// KubeletVersion override; defaults to the operator's
	// chart-level value when empty.
	// +optional
	KubeletVersion string `json:"kubeletVersion,omitempty"`
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

	// TartKubeletBinarySHA is the SHA-256 of the tart-kubelet binary
	// currently installed on the Mac mini. Drift between this and the
	// operator's own baked-in binary SHA triggers a rolling update of
	// the agent on each reconcile.
	// +optional
	TartKubeletBinarySHA string `json:"tartKubeletBinarySHA,omitempty"`

	// TartKubeletUpdateAttempts counts consecutive failures of the
	// drift-loop's UpdateTartKubelet call. Reset to zero on success.
	// Once it crosses the operator's max-attempts threshold the CR
	// transitions to a terminal Failed state with FailureReason set
	// to "TartKubeletUpdateExceededRetries"; CAPI core surfaces that
	// on the parent Machine and stops auto-driving it. Recovery is
	// manual: clear FailureReason + zero this counter to resume the
	// loop. Without this cap a persistently-broken host (binary
	// corruption, disk-full, network partition) gets SSH-hammered
	// every 60s indefinitely with no terminal-failure signal.
	// +optional
	TartKubeletUpdateAttempts int32 `json:"tartKubeletUpdateAttempts,omitempty"`
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
