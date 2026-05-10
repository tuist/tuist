package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// AssignmentTrigger is what caused this Pod to come into existence.
// +kubebuilder:validation:Enum=PreBound;Burst
type AssignmentTrigger string

const (
	// TriggerPreBound — created by the RunnerPool reconciler to fill
	// the steady-state MinWarm gap.
	TriggerPreBound AssignmentTrigger = "PreBound"

	// TriggerBurst — created by the Tuist server's webhook handler
	// in response to a workflow_job: queued event that GitHub
	// couldn't dispatch to an `online + idle` runner because the
	// MinWarm pool was saturated.
	TriggerBurst AssignmentTrigger = "Burst"
)

// AssignmentPhase tracks the Pod's lifecycle through this CR.
// +kubebuilder:validation:Enum=Pending;Running;Terminated
type AssignmentPhase string

const (
	// PhasePending — controller hasn't created the Pod yet, or
	// the Pod is still booting (kubelet hasn't reported Ready).
	PhasePending AssignmentPhase = "Pending"

	// PhaseRunning — Pod is up; the runner has registered with
	// GitHub and is either idle or running its single job.
	PhaseRunning AssignmentPhase = "Running"

	// PhaseTerminated — the runner exited; tart-kubelet flipped
	// the Pod to Succeeded/Failed; the controller's GC will
	// delete the Pod, the SA, and this CR shortly.
	PhaseTerminated AssignmentPhase = "Terminated"
)

// RunnerAssignmentSpec is the desired state of one Pod-and-SA pair.
// Lightweight: no credentials, no JIT, no dispatch token. The
// authentication contract is "this Pod's projected SA token =
// authority to mint a JIT for this pool"; the dispatch endpoint
// validates that via TokenReview at runtime.
type RunnerAssignmentSpec struct {
	// PoolRef is the RunnerPool this assignment belongs to. The
	// controller resolves it to load the Pod template (image,
	// labels, resources, fleet selector). Same namespace.
	PoolRef corev1.LocalObjectReference `json:"poolRef"`

	// Trigger records why the controller (or the server) created
	// this assignment. Operationally distinguishes "steady-state
	// warm pool" from "on-demand burst from a queued webhook"
	// for metrics + debugging; both go through the same
	// reconcile path and produce identical Pods.
	// +kubebuilder:default=PreBound
	Trigger AssignmentTrigger `json:"trigger,omitempty"`
}

// RunnerAssignmentStatus is the observed state of the Pod.
type RunnerAssignmentStatus struct {
	// PodName is the name of the Pod the controller created for
	// this assignment. Set when the controller's reconciler
	// writes the Pod manifest.
	// +optional
	PodName string `json:"podName,omitempty"`

	// PodUID is the API-server-assigned UID of the Pod.
	// Populated alongside PodName.
	// +optional
	PodUID string `json:"podUID,omitempty"`

	// ServiceAccountName is the per-Pod SA the controller created
	// alongside the Pod. The Pod mounts its projected token; the
	// dispatch endpoint validates that token via TokenReview to
	// authorize JIT mint requests for this pool.
	// +optional
	ServiceAccountName string `json:"serviceAccountName,omitempty"`

	// Phase is a coarse state field for `kubectl get rassign`
	// readability. Standard CAPI-style observed state.
	// +optional
	Phase AssignmentPhase `json:"phase,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=runnerassignments,scope=Namespaced,shortName=rassign
// +kubebuilder:printcolumn:name="Pool",type=string,JSONPath=".spec.poolRef.name"
// +kubebuilder:printcolumn:name="Trigger",type=string,JSONPath=".spec.trigger"
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="Pod",type=string,JSONPath=".status.podName"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// RunnerAssignment owns one Pod's lifecycle.
type RunnerAssignment struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RunnerAssignmentSpec   `json:"spec,omitempty"`
	Status RunnerAssignmentStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RunnerAssignmentList is a list of RunnerAssignment.
type RunnerAssignmentList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RunnerAssignment `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RunnerAssignment{}, &RunnerAssignmentList{})
}
