package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// RackHostSpec describes one physical Mac mini we own, sitting in a rack we
// operate: the BER1 colo programme's hardware, as opposed to capacity ordered
// from a provider API.
//
// It exists because every other machine kind in this provider gets its pool
// from somewhere else: Scaleway's server list filtered by a name prefix, OVH's
// by a displayName prefix, Dedibox's by a tag. Hardware we own has no such API,
// so the pool has to be a Kubernetes object. That is the whole of this CR's
// job: it is inventory, not a workload, and nothing here is read by anything
// running on the host.
//
// Keeping it separate from RackAppleSiliconMachine is what makes a
// MachineDeployment work at all. The alternative, address and outlet inline on
// each Machine, forces one MachineDeployment per box (a Machine is cloned from
// a template, so every clone would carry the same address), and worse, a
// MachineHealthCheck remediation would then recreate the Machine onto the SAME
// broken host forever. A pool is what lets remediation land somewhere else.
type RackHostSpec struct {
	// Pool is the claim marker: a RackAppleSiliconMachine claims a free
	// RackHost whose pool equals its own `spec.adoptPool`. It is the direct
	// analog of the Scaleway kind's name prefix, OVH's displayName prefix and
	// Dedibox's adopt tag, and like them it is the ENVIRONMENT BOUNDARY:
	// staging and production RackHosts can coexist in one inventory as long as
	// their pools differ.
	//
	// Optional in the schema, required by the controller (which refuses to
	// claim an unpooled host and says so on the Machine). A required field
	// here would break a Helm rollback to a revision predating it: the
	// rollback patch strips the field and the apiserver rejects the object.
	// +optional
	Pool string `json:"pool,omitempty"`

	// Serial is the Mac's hardware serial (e.g. `C07FC05JQ6NY`). This is the
	// host's durable identity: it survives a hostname change, a DFU restore
	// and a re-cabling, it is what Apple Business Manager and the MDM know the
	// box by, and it is what the providerID is composed from. The address can
	// change; this cannot.
	// +optional
	Serial string `json:"serial,omitempty"`

	// Address is what the operator dials for SSH: an IP or a DNS name. For a
	// rack host this is normally the in-rack LAN address, reachable from the
	// cluster over a tailnet subnet route advertised by the rack's service
	// node.
	//
	// A subnet-routed address is deliberate rather than incidental. Bootstrap
	// stops and replaces tailscaled on the host to install the operator's
	// pinned build; over a session transported by the HOST's own tailnet
	// identity that would drop the tunnel it is riding (which is exactly why
	// the drift loop's tailnet fallback sets SkipTailscaleInstall). Routed via
	// a separate subnet router, the session survives, so a rack host can be
	// fully bootstrapped over one transport.
	// +optional
	Address string `json:"address,omitempty"`

	// SSHUser is the account the operator logs in as. On rack hosts this is
	// the MDM-provisioned service account rather than a provider-issued one,
	// so it is per-host configurable instead of read back from an API.
	// +kubebuilder:default=tuist
	SSHUser string `json:"sshUser,omitempty"`

	// Location is where the box physically is. Nothing in the reconcile path
	// reads rack/shelf/positionU: they exist so that a human handed an
	// alerting node name can walk to it, but `site` IS load-bearing: it names
	// the rack site and composes the providerID, so the controller refuses to
	// claim a host without one.
	// +optional
	Location RackHostLocation `json:"location,omitempty"`

	// Power names the outlet this host is plugged into. Cycling it is the
	// fleet's remote reboot: Apple silicon minis power on when mains is
	// applied, and every fleet host runs `pmset autorestart 1`, so an outlet
	// cycle is a full reboot with no console.
	//
	// It is not decoration. The Scaleway kind recovers a host that fails
	// bootstrap by calling the provider's reboot API and, failing that, by
	// releasing the host so a DIFFERENT mini gets claimed. Neither exists for
	// hardware we own (releasing just re-claims the same box) so the outlet
	// is the only repair this kind has short of quarantining the host and
	// paging a human.
	// +optional
	Power *PowerOutletRef `json:"power,omitempty"`

	// Unclaimable takes a host out of the claim pool without deleting its
	// inventory record: bench work, an RMA, a box being re-imaged. An already
	// claimed host is NOT released by setting this: it stops the next claim,
	// it does not evict the current one, the same shape as
	// `Node.spec.unschedulable`.
	// +optional
	Unclaimable bool `json:"unclaimable,omitempty"`
}

// RackHostLocation is the physical position of a host.
type RackHostLocation struct {
	// Site is the rack site (e.g. `ber1`). Load-bearing: it composes the
	// providerID, so it must be stable for the life of the host.
	// +optional
	Site string `json:"site,omitempty"`

	// Rack identifies the rack within the site.
	// +optional
	Rack string `json:"rack,omitempty"`

	// Shelf identifies the mount within the rack (a 3-up tray, in the BER1
	// build).
	// +optional
	Shelf string `json:"shelf,omitempty"`

	// PositionU is the lowest rack unit the mount occupies.
	// +optional
	PositionU int `json:"positionU,omitempty"`
}

// PowerOutletRef addresses one switched outlet.
type PowerOutletRef struct {
	// Driver selects the power backend. `shelly` speaks the Shelly Gen2 RPC
	// (with a Gen1 fallback) and is for home and office prototypes only: it is
	// the BER1 prototype's PDU stand-in, not a rack driver. A colo rack's
	// switched PDUs get their own driver rather than being forced through this
	// one.
	// +kubebuilder:default=shelly
	// +kubebuilder:validation:Enum=shelly
	Driver string `json:"driver,omitempty"`

	// Host is the PDU / plug endpoint, as a host or host:port. Plain HTTP by
	// default; give it an `https://` prefix to force TLS.
	// +optional
	Host string `json:"host,omitempty"`

	// Outlet identifies the outlet on that endpoint. Driver-specific; for
	// Shelly it is the switch channel id, `"0"` on a single-channel plug.
	// +kubebuilder:default="0"
	Outlet string `json:"outlet,omitempty"`

	// CredentialsSecretRef names a Secret in the operator's namespace holding
	// `username` and `password` for the endpoint's HTTP auth. Optional: an
	// unauthenticated plug on a management VLAN needs none. Several hosts
	// normally point at the same Secret, since a PDU has one credential and
	// many outlets.
	// +optional
	CredentialsSecretRef *corev1.LocalObjectReference `json:"credentialsSecretRef,omitempty"`
}

// RackHostStatus is the observed state of one physical host.
type RackHostStatus struct {
	// ClaimedBy is the name of the RackAppleSiliconMachine currently holding
	// this host, empty when free. The claim is a status write guarded by the
	// apiserver's resourceVersion check, which makes it strictly safer than
	// the rename-is-the-claim trick the Scaleway kind uses: two reconciles
	// racing for the last free host cannot both win, and the loser sees a
	// conflict rather than a silently double-claimed box.
	// +optional
	ClaimedBy string `json:"claimedBy,omitempty"`

	// ClaimedAt is when the current claim was taken.
	// +optional
	ClaimedAt *metav1.Time `json:"claimedAt,omitempty"`

	// Power is the last observed outlet state: On, Off, or Unknown when the
	// host has no outlet configured or the driver could not reach it.
	// +optional
	Power string `json:"power,omitempty"`

	// LastPowerAction / LastPowerActionTime record the last action the
	// operator took on the outlet (`on`, `off`, `cycle`), so a host that
	// rebooted has a visible cause rather than looking like a spontaneous
	// panic.
	// +optional
	LastPowerAction string `json:"lastPowerAction,omitempty"`
	// +optional
	LastPowerActionTime *metav1.Time `json:"lastPowerActionTime,omitempty"`

	// Quarantined excludes the host from the claim pool after the machine
	// controller gave up bootstrapping it. Unlike the Scaleway kind, whose
	// bootstrap-exhaustion path releases the host so a different mini gets
	// claimed, releasing hardware we own would hand the same broken box
	// straight back to the next reconcile, and the Machine would loop on it
	// forever. Quarantine is what turns that loop into one bad host and a
	// Machine free to land elsewhere.
	//
	// Deliberately controller-set and operator-cleared (`kubectl patch
	// --subresource=status`), mirroring how a terminal Machine failure is
	// cleared: nothing recomputes it, so a box stays out until a human says
	// it was fixed.
	// +optional
	Quarantined bool `json:"quarantined,omitempty"`

	// QuarantineReason carries the failure that caused it.
	// +optional
	QuarantineReason string `json:"quarantineReason,omitempty"`

	// QuarantinedAt is when the quarantine was applied, and it is what lets the
	// quarantine expire.
	//
	// An expiry is not a convenience. Clearing this field needs write access to
	// rackhosts/status, which the operator's own ClusterRole has and a human
	// reaching the cluster through the kubectl gateway does not, so a quarantine
	// with no expiry is a physical box removed from the pool that nobody present
	// can put back. It is also usually wrong to keep: most exhaustions are a
	// verdict on the CONFIG that was being pushed, not on the hardware, and the
	// fix ships in the next operator image while the host stays excluded from
	// the fleet it was meant to rejoin.
	//
	// The shape is deliberately the same as the drift loop's terminal-failure
	// cooldown (see HostAgentStatus.LastUpdateFailureTime): a persistently bad
	// host still costs one bootstrap budget per interval rather than one per
	// reconcile, so the ladder keeps doing its job.
	// +optional
	QuarantinedAt *metav1.Time `json:"quarantinedAt,omitempty"`

	// Conditions are CAPI-style condition entries (PowerReachable).
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=rackhosts,scope=Namespaced,categories=cluster-api,shortName=rh
// +kubebuilder:printcolumn:name="Pool",type=string,JSONPath=".spec.pool"
// +kubebuilder:printcolumn:name="Address",type=string,JSONPath=".spec.address"
// +kubebuilder:printcolumn:name="ClaimedBy",type=string,JSONPath=".status.claimedBy"
// +kubebuilder:printcolumn:name="Power",type=string,JSONPath=".status.power"
// +kubebuilder:printcolumn:name="Quarantined",type=boolean,JSONPath=".status.quarantined"
// +kubebuilder:printcolumn:name="Serial",type=string,priority=1,JSONPath=".spec.serial"
// +kubebuilder:printcolumn:name="Site",type=string,priority=1,JSONPath=".spec.location.site"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// RackHost is one physical Mac mini in a rack we operate.
type RackHost struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RackHostSpec   `json:"spec,omitempty"`
	Status RackHostStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RackHostList is a list of RackHost.
type RackHostList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackHost `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackHost{}, &RackHostList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter interface.
func (h *RackHost) GetConditions() clusterv1.Conditions {
	return h.Status.Conditions
}

func (h *RackHost) SetConditions(c clusterv1.Conditions) {
	h.Status.Conditions = c
}

// Claimable reports whether this host may be claimed by the named machine.
// A host already claimed by that same machine is claimable, which is what
// makes the claim step idempotent across a reconcile that crashed between the
// RackHost status write and the Machine status write.
func (h *RackHost) Claimable(machineName string) bool {
	if h.Status.ClaimedBy != "" {
		return h.Status.ClaimedBy == machineName
	}
	return !h.Spec.Unclaimable && !h.Status.Quarantined && h.DeletionTimestamp.IsZero()
}
