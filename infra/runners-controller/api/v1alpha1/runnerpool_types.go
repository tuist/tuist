package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// RunnerPoolSpec is the operator-facing declarative shape for a
// fleet of macOS runners. The chart renders one RunnerPool CR per
// fleet (today one); the controller maintains `MinWarm` Pods +
// per-Pod ServiceAccounts on hosts matching `FleetSelector`.
//
// No customer fields here — customers are not modeled on the K8s
// side. The Tuist server's dispatch endpoint mints a per-job JIT
// runner registration for whichever customer's queued workflow_job
// the polling Pod claims, looking up customer config from the
// `accounts` table (`runner_max_concurrent`).
type RunnerPoolSpec struct {
	// Labels are stamped on the Pods + SAs the controller creates;
	// not the GitHub Actions runner labels (those come from the
	// dispatch label at JIT-mint time).
	// +optional
	Labels []string `json:"labels,omitempty"`

	// MinWarm is the count of Pods the controller maintains. By
	// convention this equals the fleet's host count, so every host
	// always carries either an idle warm Pod or a Pod running a
	// customer job. (Apple's SLA permits up to two VMs per host;
	// v1 runs one per host to keep capacity reasoning simple.)
	// +kubebuilder:default=0
	MinWarm int32 `json:"minWarm,omitempty"`

	// Image is the OCI ref of the runner Tart image, digest-pinned.
	Image string `json:"image"`

	// FleetSelector is the value of `tuist.dev/fleet=<name>` Pods
	// in this pool pin to via nodeSelector.
	FleetSelector string `json:"fleetSelector"`

	// PodCPUMilli + PodMemoryMB shape the runner Pod's
	// resources.requests so kube-scheduler bin-packs one Pod per
	// host AND tart-kubelet's `tart set` between clone and run
	// gives the VM the host's full budget.
	// +kubebuilder:default=8000
	PodCPUMilli int32 `json:"podCPUMilli,omitempty"`
	// +kubebuilder:default=14336
	PodMemoryMB int32 `json:"podMemoryMB,omitempty"`
}

// RunnerPoolStatus is the observed state of the pool.
type RunnerPoolStatus struct {
	// ObservedReplicas is the count of Pods the controller
	// currently owns.
	// +optional
	ObservedReplicas int32 `json:"observedReplicas,omitempty"`

	// LastReconcile is the timestamp of the last successful
	// reconcile pass for this pool.
	// +optional
	LastReconcile metav1.Time `json:"lastReconcile,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=runnerpools,scope=Namespaced,shortName=rpool
// +kubebuilder:printcolumn:name="MinWarm",type=integer,JSONPath=".spec.minWarm"
// +kubebuilder:printcolumn:name="Replicas",type=integer,JSONPath=".status.observedReplicas"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// RunnerPool declares one Mac mini fleet's worth of runners.
type RunnerPool struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RunnerPoolSpec   `json:"spec,omitempty"`
	Status RunnerPoolStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RunnerPoolList is a list of RunnerPool.
type RunnerPoolList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RunnerPool `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RunnerPool{}, &RunnerPoolList{})
}
