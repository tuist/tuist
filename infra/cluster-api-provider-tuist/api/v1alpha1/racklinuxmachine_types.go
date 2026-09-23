package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// RackLinuxMachineSpec is the workload shape of one rack Linux node. The box
// comes from the RackLinuxHost it claims, so a MachineDeployment can clone it.
type RackLinuxMachineSpec struct {
	// ProviderID is rack-linux://<site>/<host>, set once a host is claimed.
	// +optional
	ProviderID *string `json:"providerID,omitempty"`

	// AdoptPool is the RackLinuxHost pool this machine claims from.
	// +optional
	AdoptPool string `json:"adoptPool,omitempty"`

	// FleetName names the `<fleetName>-ssh` Secret holding the key the
	// install stick authorizes. It is read, never minted.
	// +optional
	FleetName string `json:"fleetName,omitempty"`

	// NodeLabels are registered with the Node on top of the labels every rack
	// Linux node carries.
	// +optional
	NodeLabels map[string]string `json:"nodeLabels,omitempty"`

	// NodeTaints are registered with the Node.
	// +optional
	NodeTaints []corev1.Taint `json:"nodeTaints,omitempty"`
}

// RackLinuxMachineStatus is the observed state of one rack Linux node.
type RackLinuxMachineStatus struct {
	// Ready is true while the Node is Ready.
	// +optional
	Ready bool `json:"ready,omitempty"`

	// +optional
	Phase string `json:"phase,omitempty"`

	// RackLinuxHost is the host this machine holds.
	// +optional
	RackLinuxHost string `json:"rackLinuxHost,omitempty"`

	// +optional
	Addresses []clusterv1.MachineAddress `json:"addresses,omitempty"`

	// TailnetDeviceID is the host's tailnet device at the last successful
	// converge. A host on a different device was reinstalled.
	// +optional
	TailnetDeviceID string `json:"tailnetDeviceID,omitempty"`

	// HostConfigHash fingerprints the configuration last converged onto the
	// host.
	// +optional
	HostConfigHash string `json:"hostConfigHash,omitempty"`

	// LastConvergeTime is when the host last converged successfully.
	// +optional
	LastConvergeTime *metav1.Time `json:"lastConvergeTime,omitempty"`

	// LastConvergeAttemptTime is when a converge was last attempted.
	// +optional
	LastConvergeAttemptTime *metav1.Time `json:"lastConvergeAttemptTime,omitempty"`

	// ConvergeFailures counts consecutive failed converges.
	// +optional
	ConvergeFailures int32 `json:"convergeFailures,omitempty"`

	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=racklinuxmachines,scope=Namespaced,categories=cluster-api,shortName=rlm
// +kubebuilder:printcolumn:name="Host",type=string,JSONPath=".status.rackLinuxHost"
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.ready"
// +kubebuilder:printcolumn:name="LastConverge",type="date",JSONPath=".status.lastConvergeTime"
// +kubebuilder:printcolumn:name="ProviderID",type=string,priority=1,JSONPath=".spec.providerID"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// RackLinuxMachine is one rack Linux node, joined over the tailnet and kept
// converged afterwards.
type RackLinuxMachine struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RackLinuxMachineSpec   `json:"spec,omitempty"`
	Status RackLinuxMachineStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RackLinuxMachineList is a list of RackLinuxMachine.
type RackLinuxMachineList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackLinuxMachine `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackLinuxMachine{}, &RackLinuxMachineList{})
}

func (m *RackLinuxMachine) GetConditions() clusterv1.Conditions {
	return m.Status.Conditions
}

func (m *RackLinuxMachine) SetConditions(c clusterv1.Conditions) {
	m.Status.Conditions = c
}
