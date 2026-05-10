package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// RunnerPoolSpec is the operator-facing declarative shape for a
// customer's runner pool. The chart renders one RunnerPool CR
// per `Tuist.Runners.PoolConfig` entry; the controller reconciles
// each pool to keep `MinWarm` pre-bound Pods alive.
type RunnerPoolSpec struct {
	// Owner is the GitHub org/login this pool serves. Used by the
	// dispatch endpoint to select the right pool when validating
	// a workflow_job: queued event, and as the labels-prefix on
	// the per-Pod ServiceAccount.
	Owner string `json:"owner"`

	// Labels are advertised on every runner registered for this
	// pool. The last entry by convention is the dispatch label —
	// the customer-scoped tag a workflow_job's `runs-on` must
	// include for its job to bind here. Generic labels like
	// `self-hosted` / `macOS` aren't authorization boundaries.
	Labels []string `json:"labels"`

	// MinWarm is the count of pre-bound Pods the controller keeps
	// alive. The controller materializes them with the JIT
	// minted at create time; they register with GitHub at boot
	// and sit `online + idle` ready for sub-second pickup.
	// Default 0; opt-in feature.
	// +kubebuilder:default=0
	MinWarm int32 `json:"minWarm,omitempty"`

	// RunnerGroupID is the GitHub org runner-group id this pool's
	// JIT registrations land in. Repo allowlisting on the runner
	// group is the authoritative authorization boundary; nil
	// falls back to GitHub's default group (id=1, every repo)
	// which is wrong for production.
	// +optional
	RunnerGroupID *int64 `json:"runnerGroupID,omitempty"`

	// Image is the OCI ref of the runner Tart image, digest-pinned
	// (`ghcr.io/tuist/tuist-runner@sha256:…`).
	Image string `json:"image"`

	// FleetSelector is the value of `tuist.dev/fleet=<name>` Pods
	// in this pool pin to via nodeSelector. Matches the Mac mini
	// fleet that should host these runners.
	FleetSelector string `json:"fleetSelector"`

	// PodCPUMilli + PodMemoryMB shape the runner Pod's
	// resources.requests so kube-scheduler bin-packs one Pod per
	// host AND tart-kubelet's `tart set` between clone and run
	// gives the VM the host's full budget. Match the Scaleway
	// SKU's capacity minus VZ overhead.
	// +kubebuilder:default=8000
	PodCPUMilli int32 `json:"podCPUMilli,omitempty"`
	// +kubebuilder:default=14336
	PodMemoryMB int32 `json:"podMemoryMB,omitempty"`
}

// RunnerPoolStatus is the observed state of the pool.
type RunnerPoolStatus struct {
	// ObservedReplicas is the count of RunnerAssignment CRs the
	// controller currently owns for this pool — alive + pending,
	// not including terminal Pods on their way out.
	// +optional
	ObservedReplicas int32 `json:"observedReplicas,omitempty"`

	// LastReconcile is the timestamp of the last successful
	// reconcile pass for this pool. Surfaced for ops debugging.
	// +optional
	LastReconcile metav1.Time `json:"lastReconcile,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=runnerpools,scope=Namespaced,shortName=rpool
// +kubebuilder:printcolumn:name="Owner",type=string,JSONPath=".spec.owner"
// +kubebuilder:printcolumn:name="MinWarm",type=integer,JSONPath=".spec.minWarm"
// +kubebuilder:printcolumn:name="Replicas",type=integer,JSONPath=".status.observedReplicas"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// RunnerPool declares one customer's reserved runner capacity.
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
