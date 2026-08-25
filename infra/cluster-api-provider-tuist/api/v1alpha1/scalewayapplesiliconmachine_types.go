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

	// OS is the macOS release family the fleet runs — "Tahoe",
	// "Sequoia", "Sonoma". Adoption accepts any pool host in the family
	// and release reinstalls onto the family's newest published image,
	// so the fleet tracks Scaleway's point releases instead of chasing
	// them.
	//
	// Deliberately not a point release. Scaleway retires point releases
	// without notice and reimages released hosts onto the server type's
	// current default, so an exact pin drifts out from under the fleet
	// and no pool host can satisfy it again — that is how staging lost
	// its whole runner pool in Aug 2026 while sitting on
	// macos-tahoe-26.3.
	//
	// A value naming a specific image is refused at adoption with an
	// InvalidOSPin condition rather than widened to its family —
	// silently granting any Tahoe host to someone who asked for 26.5
	// would be worse than saying no. Release is deliberately lenient:
	// Machines predating this carry exact pins in their own specs and
	// have to be able to drain.
	// +kubebuilder:default=Tahoe
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

	// GuestCapacity is how many Tart guests this host is expected to
	// run concurrently. Falls back to the operator's
	// `--tartkubelet-guest-capacity` global default (1) when unset.
	//
	// This is the SKU's INTENT, not an enforcement point. What
	// actually bounds the guest count is (a) kube-scheduler fitting
	// Pods into HostCPU/HostMemoryMB and (b) Tart refusing to start a
	// third VM per Apple's SLA. GuestCapacity exists because several
	// host-level resources are sized per guest and would otherwise
	// each need their own field:
	//
	//   * the VNC relay port range — a pinned relay port is per-host
	//     but a relay is per-Pod, so a second guest needs a second
	//     port (and the per-Mac egress Service has to declare it).
	//   * the disk-pressure goldens floor — a host running guests from
	//     two pools wants one golden per pool, or reclaiming under
	//     pressure strands a pool into a full cold image pull.
	//
	// Keep it consistent with HostCPU/HostMemoryMB: the value should be
	// what those two actually admit at the fleet's Pod shape. Setting
	// it higher does not create capacity, it only over-provisions the
	// per-guest resources above; setting it lower silently degrades the
	// second guest (no relay port, a golden it has to re-pull).
	// +optional
	GuestCapacity int `json:"guestCapacity,omitempty"`

	// MaxPods is the Pod ceiling tart-kubelet advertises on its Node
	// (`--max-pods`). Falls back to the operator's
	// `--tartkubelet-max-pods` global default (2) when unset.
	//
	// It counts EVERY Pod bound to the Node, not just Tart-VM Pods,
	// and a Pod stays bound after it finishes — a terminal Pod holds
	// its slot until GC collects it. Measured on the live fleet
	// (2026-08-25): a single-guest host was carrying its Running Pod
	// plus the previous rollout's Succeeded one. So size this as
	// guests x 2: each guest slot can transiently hold its running Pod
	// and one not-yet-collected predecessor. 3 for a single-guest host
	// (2, plus a spare), 4 for a dual-guest one.
	//
	// No allowance for host-system Pods. hcloud-csi-node, the usual
	// suspect, is kept off macOS by a `kubernetes.io/os NotIn [darwin]`
	// required nodeAffinity — not by the macOS taint, which its blanket
	// `Exists` tolerations ignore — and nothing else targets these
	// Nodes.
	//
	// This is not where Apple's 2-guest SLA is enforced and does not
	// need to be: Tart refuses to start a third VM, and
	// HostCPU/HostMemoryMB bind the guest count before MaxPods does.
	// The error costs are lopsided — too low stalls a real guest slot
	// until GC catches up, too high admits nothing extra — so it is
	// sized for the worst case.
	// +optional
	MaxPods int `json:"maxPods,omitempty"`

	// RunnerCacheVolumeGiB is the quota (GiB) of the dedicated APFS
	// volume host bootstrap provisions to hold per-account cache-volume
	// images. Unset (nil) falls back to the operator's
	// `--runner-cache-volume-gib` global default; an explicit 0
	// disables cache volumes on this host entirely (every VM boots on
	// the cold path).
	//
	// A pointer, unlike its sibling sizing fields, because 0 is a
	// meaningful value here and nonsense for them — a host with no CPU
	// or no Pod ceiling does not exist, but a host with cache volumes
	// switched off is an ordinary thing to want. With a scalar the two
	// states collapse and an operator asking a SKU to run cold gets the
	// fleet default instead, silently. That matters when bringing a new
	// SKU into a fleet whose global is already non-zero: staging the
	// host cold first and enabling the cache once it is validated is
	// how this feature was rolled out in the first place.
	//
	// Per-Machine because the right quota is a function of the SKU's
	// disk, and the SKUs differ by 4x: the 512 GB M2-L has no room
	// above ~80 GiB once the ~85 GB goldens and a job VM's transient
	// CoW growth are accounted for, while a 2 TB M4 can hold several
	// times that. Resident masters scale as
	// `gib / masterCapGib - (liveBranches + 1)`, and a dual-guest host
	// can have two live branches, so a host that runs two VMs needs a
	// LARGER quota than a single-guest host just to hold the same
	// number of accounts hot.
	//
	// The provisioning script never resizes an existing volume (see
	// renderRunnerCacheVolumeScript), so changing this on a live host
	// is inert until that host is replaced. That is why it is safe to
	// vary per Machine even though it participates in the host-config
	// hash: a drifted host re-runs an idempotent script that early-
	// returns on the already-mounted volume.
	// +optional
	RunnerCacheVolumeGiB *int `json:"runnerCacheVolumeGiB,omitempty"`

	// AdoptPoolPrefix is the Scaleway-side name prefix the controller
	// scans when claiming a Mac mini for this Machine. The controller
	// has no auto-order path, so a prefix must resolve from somewhere:
	// this field, or the operator-global `--default-adopt-pool-prefix`
	// when it is unset. Operators pre-order capacity in the Scaleway
	// console because Mac mini inventory is frequently out of stock
	// and Apple's 24h licensing floor makes speculative ordering
	// expensive.
	//
	// Optional on purpose, even though every chart-rendered
	// MachineTemplate sets it. A required field here is a schema
	// constraint on a resource CAPI *clones*, so a MachineTemplate
	// that lacks it fails `InfrastructureTemplateCloningFailed` on
	// every MachineSet scale-up — and the drift that produces such a
	// template is invisible until the next scale-up, which is
	// typically an operator recovering a host by deleting its Machine.
	// That turned a routine roll into an unrecoverable fleet: the CR
	// the MachineSet needs to create is the one the apiserver rejects,
	// and no elevation short of break-glass can repair a
	// MachineTemplate. Accepting an empty value and resolving the
	// operator default instead keeps scale-up working on a drifted
	// template and confines the blast radius to a missing default,
	// which the controller surfaces as a `NoAdoptPoolPrefix` event.
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
	// +optional
	AdoptPoolPrefix string `json:"adoptPoolPrefix,omitempty"`
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

	// GHRunnerVersion is the actions/runner release the reconciler
	// downloads the first time it bootstraps a host. The host agent
	// is configured without `--disableupdate`, so it self-updates
	// from there; changing this on an already-bootstrapped host is a
	// no-op (installActionsRunner short-circuits on a healthy runner,
	// and HostConfigHash deliberately excludes GHActionsRunner).
	//
	// Required, and deliberately without a default unlike its
	// siblings: GitHub retires runner releases on a rolling deadline,
	// so a default baked into the API would rot into a version GitHub
	// refuses. The chart is the single source of truth
	// (`buildersFleet.ghRunnerVersion`), Renovate bumps it alongside
	// `runner_version` in infra/runner-image/runner.pkr.hcl, and a CR
	// that omits it is rejected instead of silently seeding a
	// years-old agent.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	GHRunnerVersion string `json:"ghRunnerVersion"`

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

	// HostConfigHash is the fleet-wide canonical hash of every host
	// config the operator pushes — the rendered install scripts plus the
	// embedded binaries (bootstrap.HostConfigHash). Drift between this
	// and the operator's own computed hash re-pushes the host config on
	// the next reconcile, so a change to ANY pushed config (a script
	// tweak, a fleet CIDR, or a re-baked binary) rolls to existing hosts
	// instead of only a tart-kubelet binary change.
	// +optional
	HostConfigHash string `json:"hostConfigHash,omitempty"`

	// FailedHostConfigHash records the desired HostConfigHash that
	// exhausted its update-retry budget and drove the CR into the terminal
	// Failed state. A broken config can never be applied, so HostConfigHash
	// never advances to it and comparing desired-vs-last-applied would see
	// drift forever and reset the retry cap every reconcile. Comparing
	// desired-vs-FailedHostConfigHash instead keeps the cap for an unchanged
	// broken config while still retrying a genuinely new one.
	// +optional
	FailedHostConfigHash string `json:"failedHostConfigHash,omitempty"`

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

	// LastUpdateFailureTime is when the drift loop last recorded an
	// update failure for this host. It exists so the terminal Failed
	// state can expire: FailedHostConfigHash alone only lifts it when a
	// NEW config ships, which is right for a config the host rejected
	// but wrong for the far more common verdict — the host was simply
	// unreachable (`dial tcp ...:22: i/o timeout`). Those hosts stayed
	// terminal indefinitely while remaining Ready and schedulable, so
	// they kept running jobs on a host config frozen at whatever the
	// operator last managed to push. Re-arming after a cooldown lets a
	// host that has since come back take the current config on its own,
	// while a genuinely broken config still backs off to a handful of
	// attempts per cooldown instead of hammering every reconcile.
	// +optional
	LastUpdateFailureTime *metav1.Time `json:"lastUpdateFailureTime,omitempty"`

	// BootstrapAttempts counts consecutive bootstrap (Stage 2)
	// failures on the currently-adopted host. Reset to zero on a
	// successful bootstrap or whenever the underlying ServerID
	// changes (mini swapped out). Drives the tiered recovery
	// escalation in the BootstrapFailed path: at the reboot threshold
	// the controller asks Scaleway to reboot the host to clear
	// volatile state (PAM lockouts, sshd throttling, half-open
	// connections); at the release threshold it returns the host to
	// the adopt pool so the next reconcile claims a different mini.
	// +optional
	BootstrapAttempts int32 `json:"bootstrapAttempts,omitempty"`

	// BootstrapRebootIssued records that a recovery reboot has
	// already been triggered for the current host. Prevents
	// re-rebooting the same host on every retry after the threshold
	// crossing. Cleared when the underlying ServerID changes (mini
	// swapped out, e.g., via release-to-pool) or on successful
	// bootstrap.
	// +optional
	BootstrapRebootIssued bool `json:"bootstrapRebootIssued,omitempty"`
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
