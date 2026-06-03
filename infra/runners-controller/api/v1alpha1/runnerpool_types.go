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
	// pool: `["self-hosted", "Linux", "X64"]`). The chart renders
	// this field for every pool (per-OS defaults applied in the
	// helm template), so the server treats absent/empty as a chart
	// bug rather than substituting a default.
	RunnerLabels []string `json:"runnerLabels"`

	// OS is the host OS for this pool's Pods. Drives nodeSelector
	// and tolerations on the controller side. `darwin` (default,
	// for backward compat with v1 macOS pools) targets Mac mini
	// nodes running tart-kubelet; `linux` targets standard Linux
	// nodes on the Hetzner Cloud fleet.
	// +kubebuilder:default=darwin
	// +optional
	OS string `json:"os,omitempty"`

	// PodCPUMilli + PodMemoryMB shape the runner Pod's
	// resources.requests. For macOS pools the values are tied to
	// Mac mini host capacity minus VZ overhead so tart-kubelet's
	// `tart set` lines up with the host budget. For Linux pools
	// the values are standard cgroup requests against the bare-metal
	// host's vCPU/RAM (or per-microVM allocations when running
	// behind a Kata + Firecracker `RuntimeClass`).
	// +kubebuilder:default=8000
	PodCPUMilli int32 `json:"podCPUMilli,omitempty"`
	// +kubebuilder:default=14336
	PodMemoryMB int32 `json:"podMemoryMB,omitempty"`

	// RuntimeClass, when set, is stamped on the runner Pod's
	// `spec.runtimeClassName`. The chart's `kata-qemu` RuntimeClass
	// wraps each Pod in a microVM with its own kernel — required on
	// Linux pools because the controller attaches a privileged
	// docker:dind sidecar to every Linux runner Pod. The microVM
	// keeps the sidecar's privileged surface off the bare-metal
	// host.
	// +optional
	RuntimeClass string `json:"runtimeClass,omitempty"`

	// Autoscaling is the optional queue-depth-driven autoscaling
	// config for this pool. When `Enabled` is true the
	// runners-controller patches `spec.replicas` on a 5 s cadence
	// using the Tuist server's desired-replicas endpoint. Disabled
	// pools stay at a static `Replicas` value (the v1 macOS shape).
	// +optional
	Autoscaling *RunnerPoolAutoscaling `json:"autoscaling,omitempty"`
}

// RunnerPoolAutoscaling carries the autoscaling knobs. Lives in
// its own struct so an absent block (the v1 default) keeps
// `RunnerPoolSpec` byte-identical to its pre-autoscaling shape on
// the wire — no `autoscaling: null` noise on every macOS pool.
type RunnerPoolAutoscaling struct {
	// Enabled flips the autoscaling reconciler on for this pool.
	// When false, the controller leaves `spec.replicas` alone.
	// +optional
	Enabled bool `json:"enabled,omitempty"`

	// MinWarmPoolFloor is the lower bound for the desired warm
	// pool size. The server's rolling p95 of concurrent claims
	// can lift the effective floor higher; this value only floors
	// the floor.
	// +optional
	MinWarmPoolFloor int32 `json:"minWarmPoolFloor,omitempty"`

	// MaxReplicas is the hard ceiling on the autoscaler-driven
	// `spec.replicas` value. 0 disables autoscaling-driven scale
	// changes (the static `spec.replicas` still applies).
	// +optional
	MaxReplicas int32 `json:"maxReplicas,omitempty"`

	// ScaleDownCooldownSeconds is the minimum time the controller
	// waits between successive scale-down actions for this pool.
	// Anti-thrash guard.
	// +optional
	ScaleDownCooldownSeconds int32 `json:"scaleDownCooldownSeconds,omitempty"`
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

	// LastScaleDownAt is the timestamp of the last autoscaler
	// scale-down action. The controller's cooldown gate reads
	// this to avoid scaling down twice in quick succession.
	// +optional
	LastScaleDownAt *metav1.Time `json:"lastScaleDownAt,omitempty"`

	// ObservedImage is the `spec.image` value the controller last
	// recorded an `ImageRolledAt` for. The reconciler updates this
	// (and bumps `ImageRolledAt`) on every reconcile where it differs
	// from the live spec, including the very first reconcile of a
	// freshly-created pool.
	// +optional
	ObservedImage string `json:"observedImage,omitempty"`

	// ImageRolledAt is when the controller most recently observed
	// `spec.image` changing. The server-side dispatch endpoint reads
	// this to stagger stale-Pod drains across a rolling window —
	// without it, every idle warm Pod would receive HTTP 410 on the
	// same poll tick and the warm pool would briefly drop to zero
	// before replacements boot. Each Pod's slot is a deterministic
	// hash of its name, so the schedule is stateless across server
	// replicas and survives a restart mid-rollout.
	// +optional
	ImageRolledAt metav1.Time `json:"imageRolledAt,omitempty"`
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
