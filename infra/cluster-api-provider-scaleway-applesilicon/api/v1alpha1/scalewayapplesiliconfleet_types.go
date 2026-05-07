package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// ScalewayAppleSiliconFleetSpec is the operator-facing declarative
// shape for a pool of Mac minis. The chart manages exactly one Fleet
// per logical pool (xcresult-processor, customer runners, ...); the
// Fleet controller owns the Machine instance lifecycle (creation,
// adoption, recycling on template drift, garbage-collection on
// scale-down or delete) so helm never has to touch individual Machine
// CRs after they've been provisioned.
//
// Why this shape (vs. helm rendering Machine CRs directly):
//
//	`helm.sh/resource-policy: keep` on Machine CRs orphans them from
//	helm tracking, so spec.type / spec.zone updates in values are
//	silently dropped. Removing `keep` solves the update-propagation
//	problem but reintroduces the rollback-wedge risk (helm trying to
//	delete a Machine while the operator is being rolled, finalizer
//	blocks forever). Putting the abstraction one level up — Fleet is
//	helm-managed; Machines are operator-managed — gives us both:
//	helm freely patches the Fleet's spec on every upgrade, and the
//	operator handles Machine lifecycle including the awkward
//	rollback-during-operator-roll case.
type ScalewayAppleSiliconFleetSpec struct {
	// Replicas is the desired number of Machines in the fleet.
	// The Fleet controller creates / deletes Machine CRs to
	// converge to this count. Default 1.
	// +kubebuilder:default=1
	Replicas int32 `json:"replicas"`

	// MachineTemplate is the per-Machine spec the Fleet controller
	// stamps onto every Machine it creates. Updates here apply to
	// new Machines immediately and are automatically rolled out to
	// non-Ready Machines (those still Provisioning / Bootstrapping)
	// by recycling them — this covers the "Scaleway out of stock,
	// flip SKU" scenario without manual intervention. Ready
	// Machines are not disturbed; rolling-update them is a
	// follow-up.
	MachineTemplate ScalewayAppleSiliconMachineSpec `json:"machineTemplate"`
}

// ScalewayAppleSiliconFleetStatus is the observed state of the fleet.
type ScalewayAppleSiliconFleetStatus struct {
	// Replicas is the number of Machine CRs that currently exist
	// for this fleet.
	// +optional
	Replicas int32 `json:"replicas,omitempty"`

	// ReadyReplicas is the count of those Machines reporting
	// Status.Ready=true.
	// +optional
	ReadyReplicas int32 `json:"readyReplicas,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=scalewayapplesiliconfleets,scope=Namespaced,categories=cluster-api,shortName=sasf
// +kubebuilder:printcolumn:name="Replicas",type=integer,JSONPath=".spec.replicas"
// +kubebuilder:printcolumn:name="Ready",type=integer,JSONPath=".status.readyReplicas"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// ScalewayAppleSiliconFleet groups N Mac mini instances under a
// single helm-managed declarative spec.
type ScalewayAppleSiliconFleet struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ScalewayAppleSiliconFleetSpec   `json:"spec,omitempty"`
	Status ScalewayAppleSiliconFleetStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// ScalewayAppleSiliconFleetList is a list of ScalewayAppleSiliconFleet.
type ScalewayAppleSiliconFleetList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ScalewayAppleSiliconFleet `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ScalewayAppleSiliconFleet{}, &ScalewayAppleSiliconFleetList{})
}
