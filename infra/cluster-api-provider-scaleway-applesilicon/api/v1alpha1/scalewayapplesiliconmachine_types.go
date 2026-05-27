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

	// Type is Scaleway's Mac mini SKU (M1-M, M2-L, M4-S, M4-M, etc.).
	// Defaults to M2-L: despite its name, Scaleway's M2-L is M2 Pro
	// 10-core / 16 GB RAM (not the 12-core/32 GB variant). Most
	// reliable inventory in fr-par-1; fr-par-3 has M1-M only and it's
	// been unstocked.
	// +kubebuilder:default=M2-L
	Type string `json:"type,omitempty"`

	// GHActionsRunner, when set, installs a GitHub Actions self-hosted
	// runner agent on the host as the last step of bootstrap, alongside
	// the usual tart-kubelet install. Used for the bare-metal
	// vm-image-builder fleet: hosts register as Nodes (with a
	// `tuist.dev/role=builder:NoSchedule` taint so no Pods land on
	// them) and serve image-bake workflow jobs that run Packer
	// directly against the host's Tart daemon. Independent of
	// tart-kubelet; both can run on the same host without
	// interference because no Pods are ever scheduled.
	// +optional
	GHActionsRunner *GHActionsRunnerConfig `json:"ghActionsRunner,omitempty"`

	// Zone is the Scaleway zone (fr-par-1, fr-par-3, etc.).
	// +kubebuilder:default=fr-par-1
	Zone string `json:"zone,omitempty"`

	// OS is the Scaleway-provided macOS image name. The controller
	// resolves this to an OS UUID via `scw apple-silicon os list`.
	// +kubebuilder:default=macos-tahoe-26.3
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

	// HostCPU is the CPU-core count the Mac mini's host advertises
	// on the Node it registers (Node.Status.Capacity). Sets
	// tart-kubelet's `--host-cpu` flag at bootstrap. Should match
	// the Scaleway SKU — heterogeneous fleets (M2-M=8 / M2-L=12 /
	// M4-S=8 etc.) need per-Machine values so kube-scheduler sees
	// the real capacity. Falls back to the operator's
	// `--tartkubelet-host-cpu` global default (8) when unset.
	// +optional
	HostCPU int `json:"hostCPU,omitempty"`

	// HostMemoryMB is the memory advertised on the Node. Mirrors
	// the Scaleway SKU's RAM minus the ~2 GB Apple
	// Virtualization.framework reserves for the host (otherwise
	// the VM's `tart run` fails with `memorySize >
	// maximumAllowedMemorySize`). Falls back to the operator's
	// `--tartkubelet-host-memory-mb` global default (16384) when
	// unset.
	// +optional
	HostMemoryMB int `json:"hostMemoryMB,omitempty"`

	// AdoptPoolPrefix is the Scaleway-side name prefix the controller
	// scans when claiming a Mac mini for this Machine. Required:
	// the controller has no auto-order path. Operators pre-order
	// capacity in the Scaleway console because Mac mini inventory is
	// frequently out of stock and Apple's 24h licensing floor makes
	// speculative ordering expensive.
	//
	// Operator workflow:
	//
	//   1. Pre-order Mac minis in the Scaleway console with names
	//      starting with this prefix (e.g. `tuist-pool-001`,
	//      `tuist-pool-fr-par-1-a`). The exact suffix doesn't
	//      matter — only the prefix is matched.
	//   2. When CAPI creates a ScalewayAppleSiliconMachine, the
	//      controller picks the first server matching `(Type, Zone,
	//      OS)` whose name has this prefix, renames it to the
	//      Machine's name via `UpdateServer`, and adopts it. The
	//      rename IS the claim: the prefix is gone, so the next
	//      reconcile won't double-claim.
	//
	// When no compatible pre-ordered host is available, reconcile
	// requeues with a `NoAvailableHost` event.
	//
	// Delete semantics: on Machine deletion the controller renames
	// the host back into the pool namespace (with a fresh UUID
	// suffix) and triggers a Scaleway OS reinstall, then drops the
	// k8s-side state. The host stays alive, is reset to factory-
	// default state, and becomes eligible for the next AdoptFromPool
	// scan once Scaleway flips it back to `Delivered + Ready`.
	// Physical destruction is operator-owned via the Scaleway
	// console so the 24h billing floor doesn't leak into deploy flows.
	// +kubebuilder:validation:MinLength=1
	AdoptPoolPrefix string `json:"adoptPoolPrefix"`
}

// GHActionsRunnerConfig tells the reconciler what GitHub Actions
// self-hosted runner agent to install on the host. The agent runs
// as a launchd LaunchAgent under the host's SSH user (m1), picks up
// queued jobs from GitHub, and shells out to whatever tooling the
// job needs — typically Packer driving the host's Tart daemon.
//
// Registration tokens are minted by the reconciler from a GitHub
// App credential set; see GHAppSecretName.
type GHActionsRunnerConfig struct {
	// GHOrg is the GitHub organization to register the Actions
	// runner against. Org-scope so any repo in the org can use the
	// runner without per-repo registration.
	// +kubebuilder:default=tuist
	GHOrg string `json:"ghOrg,omitempty"`

	// GHRunnerLabels is the comma-separated label set the runner
	// advertises to GitHub. Must include every label the workflows
	// that schedule onto this fleet pin in `runs-on:` (today
	// runner-image.yml and xcresult-processor-image.yml both pin
	// `[self-hosted, macos, bare-metal, vm-image-builder]`). Drift
	// here makes the host invisible to the GitHub scheduler.
	// +kubebuilder:default="self-hosted,macos,bare-metal,vm-image-builder"
	GHRunnerLabels string `json:"ghRunnerLabels,omitempty"`

	// GHRunnerVersion pins the actions/runner release the
	// reconciler downloads onto the host. Keep in sync with
	// `runner_version` in infra/runner-image/runner.pkr.hcl so the
	// runner agent baked into the runner-image guest matches the
	// agent running on the host that bakes that image.
	// +kubebuilder:default="2.334.0"
	GHRunnerVersion string `json:"ghRunnerVersion,omitempty"`

	// GHAppSecretName is the name of a Secret in the same namespace
	// carrying the GitHub App credentials the reconciler uses to
	// mint a fresh runner-registration token at every bootstrap.
	// The Secret has three fields:
	//
	//   - `app-id`           — GitHub App ID
	//   - `installation-id`  — Installation ID for the target org
	//   - `private-key`      — PEM-encoded RSA private key
	//
	// None of the three expire on a timer; the operator sets the
	// item once at env bring-up and never rotates it manually. The
	// chart syncs the trio from a single 1Password item via ESO.
	// Once a host has registered, its agent stores its own long-
	// lived auth token locally and the Secret isn't consulted
	// again for that host.
	GHAppSecretName string `json:"ghAppSecretName,omitempty"`
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
