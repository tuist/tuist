package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// RunnerPoolSpec is the operator-facing declarative shape for a
// fleet of runners (macOS on Scaleway Mac minis, or Linux on
// Hetzner Cloud). The chart renders one RunnerPool CR per entry in
// `runnersFleet.pools` / `runnersFleetLinux.pools`; the controller
// maintains `Replicas` Pods + per-Pod ServiceAccounts on hosts
// matching `FleetSelector`.
//
// Multiple RunnerPools coexist in the same namespace so different
// runner images (e.g. Xcode versions, base macOS releases, Linux
// distros) can be surfaced as distinct fleets. Customers route to
// a fleet by putting its `DispatchLabel` in their workflow's
// `runs-on`; the Tuist server's webhook handler matches the
// workflow_job's labels against every pool's `DispatchLabel` and
// enqueues against the matching fleet. `RunnerLabels` carry the
// OS/arch triple stamped on the GitHub runner at JIT mint time.
//
// No customer fields here — customers are not modeled on the K8s
// side. Per-customer config lives in `accounts.runner_max_concurrent`.
type RunnerPoolSpec struct {
	// Labels are stamped on the Pods + SAs the controller creates;
	// not the GitHub Actions runner labels (those come from
	// `DispatchLabel` at JIT-mint time).
	// +optional
	Labels []string `json:"labels,omitempty"`

	// Replicas is the count of Pods the controller maintains. The
	// chart's `runnersFleet.pools[].replicas` flows straight into
	// this field. Across all pools in a namespace, the sum should
	// fit within the host fleet's capacity (one VM per host at v1;
	// Apple's SLA permits up to two).
	// +kubebuilder:default=0
	Replicas int32 `json:"replicas,omitempty"`

	// Image is the OCI ref of the runner Tart image, digest-pinned.
	Image string `json:"image"`

	// FleetSelector is the value of `tuist.dev/fleet=<name>` Pods
	// in this pool pin to via nodeSelector. Multiple RunnerPools
	// can share a node fleet (bin-pack different images on the
	// same Mac mini hosts) or split (dedicated capacity per image).
	FleetSelector string `json:"fleetSelector"`

	// DispatchLabel is the GitHub Actions runner label customers
	// put in `runs-on` to target this fleet. The webhook handler
	// matches `workflow_job.labels` against every pool's
	// DispatchLabel; the dispatch endpoint includes it in the JIT
	// mint so the resulting runner registers with the label and
	// GitHub binds the workflow_job to it.
	//
	// One-per-fleet is enforced by the server-side webhook (two
	// pools with the same label would non-deterministically route).
	DispatchLabel string `json:"dispatchLabel"`

	// RunnerLabels are stamped on the GitHub Actions runner at
	// JIT-mint time, in addition to DispatchLabel which is always
	// appended. Conventionally `["self-hosted", "<os>", "<arch>"]`
	// (e.g. macOS pool: `["self-hosted", "macOS", "ARM64"]`; Linux
	// pool: `["self-hosted", "Linux", "X64"]`). Empty falls back
	// to the macOS triple on the server for backward compat with
	// v1 macOS-only pools.
	// +optional
	RunnerLabels []string `json:"runnerLabels,omitempty"`

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
// +kubebuilder:printcolumn:name="Replicas",type=integer,JSONPath=".spec.replicas"
// +kubebuilder:printcolumn:name="Observed",type=integer,JSONPath=".status.observedReplicas"
// +kubebuilder:printcolumn:name="DispatchLabel",type=string,JSONPath=".spec.dispatchLabel"
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
