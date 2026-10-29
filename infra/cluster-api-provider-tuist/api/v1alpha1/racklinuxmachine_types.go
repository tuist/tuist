package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// RackLinuxMachineSpec is one rack Linux host as a node. The operator creates
// it, and the CAPI Machine that owns it, for each RackLinuxHost, under the
// host's name.
type RackLinuxMachineSpec struct {
	// ProviderID is rack-linux://<site>/<host UUID>.
	// +optional
	ProviderID *string `json:"providerID,omitempty"`

	// Host is the RackLinuxHost this machine is.
	Host string `json:"host"`
}

// RackLinuxMachineStatus is the observed state of one rack Linux node.
type RackLinuxMachineStatus struct {
	// Ready is true while the Node is Ready.
	// +optional
	Ready bool `json:"ready,omitempty"`

	// +optional
	Phase string `json:"phase,omitempty"`

	// NodeName is the name the host joined the cluster under: its hostname
	// when it joined. A host whose hostname changed joins again under the
	// new one.
	// +optional
	NodeName string `json:"nodeName,omitempty"`

	// +optional
	Addresses []clusterv1.MachineAddress `json:"addresses,omitempty"`

	// TailnetDeviceID is the host's tailnet device at the last converge
	// attempt. A host on a different device was reinstalled, and is converged
	// without waiting out the previous device's failure backoff.
	// +optional
	TailnetDeviceID string `json:"tailnetDeviceID,omitempty"`

	// HostConfigHash fingerprints the configuration last converged onto the
	// host over SSH.
	// +optional
	HostConfigHash string `json:"hostConfigHash,omitempty"`

	// NodeConfig is the configuration the host runs as a node, which its
	// node agent keeps applied.
	// +optional
	NodeConfig *RackNodeConfig `json:"nodeConfig,omitempty"`

	// NodeConfigTime is when NodeConfig last changed. A node agent that has
	// not applied it a few minutes later leaves it to a converge over SSH.
	// +optional
	NodeConfigTime *metav1.Time `json:"nodeConfigTime,omitempty"`

	// Agent is what the host's node agent last did. The agent writes it, and
	// nothing else.
	// +optional
	Agent *RackNodeAgentStatus `json:"agent,omitempty"`

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
// +kubebuilder:printcolumn:name="Node",type=string,JSONPath=".status.nodeName"
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.ready"
// +kubebuilder:printcolumn:name="LastConverge",type="date",JSONPath=".status.lastConvergeTime"
// +kubebuilder:printcolumn:name="Agent",type="date",JSONPath=".status.agent.appliedAt"
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
