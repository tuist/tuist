package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// HostAgentStatus is the status block every macOS machine kind shares: the
// operator-facing phase, the terminal-failure fields CAPI core surfaces on the
// parent Machine, and the bookkeeping the host-config push loop keeps.
//
// It is embedded (and therefore inlined on the wire: `.status.phase`,
// `.status.hostConfigHash`, ... are unchanged) rather than duplicated per kind
// because the machinery that reads and writes it is subtle and shared:
// terminal-failure pinning, the FailedHostConfigHash vs last-applied
// distinction, and the retry cooldown are each one bug away from a fleet that
// silently stops taking config. This provider has already paid for that class
// of mistake twice: a Config field wired into the bootstrap path but not the
// drift path, and a phase overwritten by the reconcile tail, and both times
// the cost was hosts that read as converged while running stale config. One
// definition, one set of helpers operating on it (see controllers/macos), is
// what keeps a second macOS kind from re-acquiring those bugs by copy.
type HostAgentStatus struct {
	// Phase tracks lifecycle for operators: Pending | Adopting |
	// Bootstrapping | Ready | Deleting | Failed. CAPI core drives off Ready +
	// Conditions instead; this is the human-readable summary and the series
	// the stuck-Failed alert keys on.
	// +optional
	Phase string `json:"phase,omitempty"`

	// FailureReason / FailureMessage are set on terminal failures. CAPI core
	// surfaces them on the Machine object and stops auto-driving it.
	// +optional
	FailureReason *string `json:"failureReason,omitempty"`
	// +optional
	FailureMessage *string `json:"failureMessage,omitempty"`

	// TartKubeletBinarySHA is the SHA-256 of the tart-kubelet binary currently
	// installed on the host, stamped after each successful push. It is a
	// record, not the drift trigger: HostConfigHash is, and it covers this
	// binary among everything else.
	// +optional
	TartKubeletBinarySHA string `json:"tartKubeletBinarySHA,omitempty"`

	// HostConfigHash is the fleet-wide canonical hash of every host config the
	// operator pushes: the rendered install scripts plus the embedded
	// binaries (bootstrap.HostConfigHash). Drift between this and the
	// operator's own computed hash re-pushes on the next reconcile, so a
	// change to ANY pushed config (a script tweak, a fleet CIDR, a re-baked
	// binary) rolls to existing hosts rather than only a binary change.
	// +optional
	HostConfigHash string `json:"hostConfigHash,omitempty"`

	// FailedHostConfigHash records the desired hash that exhausted its
	// update-retry budget and drove the CR terminal. A broken config can never
	// be applied, so HostConfigHash never advances to it and a
	// desired-vs-last-applied comparison would see drift forever, resetting
	// the retry cap on every reconcile. Comparing desired-vs-failed keeps the
	// cap for an unchanged broken config while still retrying a new one.
	// +optional
	FailedHostConfigHash string `json:"failedHostConfigHash,omitempty"`

	// TartKubeletUpdateAttempts counts consecutive failures of the drift
	// loop's host-config push. Reset to zero on success. Once it crosses the
	// operator's max-attempts threshold the CR transitions to a terminal
	// Failed state with FailureReason "TartKubeletUpdateExceededRetries";
	// CAPI core surfaces that on the parent Machine and stops auto-driving
	// it. Recovery is automatic on a new config or an elapsed cooldown (see
	// FailedHostConfigHash and LastUpdateFailureTime), and operator-driven
	// before then: clear failureReason and zero this counter. Without the cap
	// a persistently-broken host (binary corruption, a full disk, a network
	// partition) gets SSH-hammered every 60s forever with no terminal signal
	// for ops to alert on.
	// +optional
	TartKubeletUpdateAttempts int32 `json:"tartKubeletUpdateAttempts,omitempty"`

	// LastUpdateFailureTime is when the drift loop last recorded a failure for
	// this host. It exists so the terminal state can expire on a timer:
	// FailedHostConfigHash alone only lifts it when a NEW config ships, which
	// is right for a config the host rejected and wrong for the far more
	// common verdict: the host was simply unreachable (`dial tcp ...:22: i/o
	// timeout`). Those hosts otherwise stay terminal indefinitely while
	// remaining Ready, schedulable, and running jobs against a host config
	// frozen at whatever the operator last managed to push, so a fleet-wide
	// fix rolls out and silently misses them. Re-arming after a cooldown lets
	// a host that has since come back take the current config on its own,
	// while a genuinely broken config still backs off to one attempt budget
	// per cooldown rather than per reconcile.
	// +optional
	LastUpdateFailureTime *metav1.Time `json:"lastUpdateFailureTime,omitempty"`

	// BootstrapAttempts counts consecutive bootstrap failures on the currently
	// held host. Reset to zero on a successful bootstrap, and whenever the
	// underlying host changes (a mini swapped out), since the count describes
	// a host rather than a Machine. It drives each kind's tiered recovery
	// escalation: at the reboot threshold the controller clears volatile host
	// state (PAM lockouts, sshd throttling, half-open connections), and at the
	// give-up threshold it stops retrying the same box: the Scaleway kind by
	// releasing it so a different mini gets claimed, the static kind by
	// quarantining it, since releasing hardware we own would hand back the
	// same broken host.
	// +optional
	BootstrapAttempts int32 `json:"bootstrapAttempts,omitempty"`

	// BootstrapRebootIssued records that a recovery reboot has already been
	// triggered for the current host, so a long retry tail doesn't re-reboot
	// it on every attempt past the threshold. Cleared when the host changes or
	// on a successful bootstrap. What "reboot" means is kind-specific: the
	// Scaleway kind calls the provider API, the static kind cycles the host's
	// PDU outlet, which is a reboot because Apple silicon powers on when mains
	// is applied.
	// +optional
	BootstrapRebootIssued bool `json:"bootstrapRebootIssued,omitempty"`
}

// HostAgent returns a pointer into the CR's own status so the shared macOS
// helpers mutate the object the caller is about to patch, not a copy.
func (m *ScalewayAppleSiliconMachine) HostAgent() *HostAgentStatus {
	return &m.Status.HostAgentStatus
}

// HostAgent returns a pointer into the CR's own status so the shared macOS
// helpers mutate the object the caller is about to patch, not a copy.
func (m *StaticAppleSiliconMachine) HostAgent() *HostAgentStatus {
	return &m.Status.HostAgentStatus
}
