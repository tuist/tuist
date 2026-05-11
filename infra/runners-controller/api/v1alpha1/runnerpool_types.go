package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// PoolRole tags a pool with the function it serves. Customer pools
// (the default) hold runners pre-registered with GitHub for a
// specific org; shared-warm pools hold runners that are booted and
// polling the dispatch endpoint without being bound to any
// customer yet — they get claimed by Burst CRs at dispatch time so
// the cold-start cost is amortized across customers.
// +kubebuilder:validation:Enum=Customer;SharedWarm
type PoolRole string

const (
	// RoleCustomer is the default — runners register with GitHub
	// at boot under the customer's org runner group and sit
	// online + idle until a workflow_job binds to them.
	RoleCustomer PoolRole = "Customer"

	// RoleSharedWarm holds runners booted and polling the dispatch
	// endpoint but NOT yet registered with GitHub. When a Burst
	// RunnerAssignment for any customer is pending, the dispatch
	// endpoint atomically "claims" the Burst on behalf of a polling
	// warm Pod and mints a JIT for the customer's pool — the warm
	// Pod registers under the customer at that point. Skips the
	// ~30-90s clone+boot tax on the customer-facing cold path.
	RoleSharedWarm PoolRole = "SharedWarm"
)

// RunnerPoolSpec is the operator-facing declarative shape for a
// customer's runner pool. The chart renders one RunnerPool CR
// per `Tuist.Runners.PoolConfig` entry; the controller reconciles
// each pool to keep `MinWarm` pre-bound Pods alive.
type RunnerPoolSpec struct {
	// Role determines whether the pool's Pods register with GitHub
	// at boot (`Customer`) or stay anonymous and claim Burst
	// assignments at dispatch time (`SharedWarm`). Defaults to
	// `Customer`. There can be at most one SharedWarm pool per
	// namespace; the dispatch endpoint picks the first it finds.
	// +kubebuilder:default=Customer
	// +optional
	Role PoolRole `json:"role,omitempty"`

	// Owner is the GitHub org/login this pool serves. Used by the
	// dispatch endpoint to select the right pool when validating
	// a workflow_job: queued event, and as the labels-prefix on
	// the per-Pod ServiceAccount. Required for Customer pools;
	// SharedWarm pools leave this empty.
	// +optional
	Owner string `json:"owner,omitempty"`

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

	// AllowedRepos mirrors the GitHub runner group's repo allowlist
	// for the webhook handler's short-circuit check: a queued
	// workflow_job from a repo not on this list won't materialize
	// a Burst RunnerAssignment + VM, since GitHub would refuse to
	// dispatch the job to the runner group anyway. Empty means
	// "every repo in the org" (the runner group default). Strings
	// are `<owner>/<repo>`, case-insensitive.
	// +optional
	AllowedRepos []string `json:"allowedRepos,omitempty"`

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
