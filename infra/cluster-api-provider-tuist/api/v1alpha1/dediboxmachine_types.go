package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// DediboxMachineSpec is the desired state of one Scaleway Dedibox dedicated
// server. Structurally it mirrors the OVH kind — a customer-facing public box
// that adopts a pre-ordered server, installs on claim, self-joins over its
// public IP, and (monthly contract) is not terminated on delete. It is driven
// through the Scaleway Dedibox API with a default-project IAM key (every Dedibox
// in the org shares the default project — a Dedibox cannot be assigned to
// another one — so the project can't isolate environments; a per-fleet tag
// does). The private network is RPN rather than a Scaleway VPC PN (unused at
// Qty-1).
type DediboxMachineSpec struct {
	// ProviderID, set by the controller after the self-join completes, takes the
	// shape `dedibox://<datacenter>/<server-id>` — a foreign providerID host so
	// the Hetzner CCM never reaps the node, the same guard the other kinds use.
	// +optional
	ProviderID *string `json:"providerID,omitempty"`

	// Datacenter is the online.net datacenter the server lives in (e.g. `dc3`
	// for Paris, `ams1` for Amsterdam). Scopes adoption and composes the
	// providerID.
	// +kubebuilder:default=dc3
	Datacenter string `json:"datacenter,omitempty"`

	// Offer is the Dedibox commercial offer the fleet's pool is made of (e.g.
	// `Start-1-M-SSD`). It narrows adoption within the tag-scoped pool; empty
	// matches any offer carrying the fleet tag.
	// +optional
	Offer string `json:"offer,omitempty"`

	// OS is the online.net install template label, resolved to an os-id at
	// install time (e.g. `ubuntu_24.04`).
	// +kubebuilder:default=ubuntu_24.04
	OS string `json:"os,omitempty"`

	// AdoptTag is the per-fleet tag the operator stamps on each pre-ordered box
	// (e.g. `tuist-kura-staging`) and the marker the controller scans to claim a
	// server. It is the ENVIRONMENT BOUNDARY: every Dedibox in the org shares the
	// default Scaleway project, so the project can't isolate environments — this
	// tag does (the Dedibox analog of the Apple Silicon / OVH name prefix).
	// Enforced as required by the fleet helm template, not the CRD: a required CRD
	// field breaks helm rollbacks to revisions predating it (the rollback patch
	// strips it, the apiserver rejects).
	// +optional
	AdoptTag string `json:"adoptTag,omitempty"`

	// FleetName groups Machines that share one SSH key, like the Apple Silicon
	// kind. Set by the MachineTemplate so every Machine the MachineDeployment
	// clones derives the SAME fleet key the operator authorizes on the
	// pre-ordered pool boxes; without it the per-Machine-name key would not match
	// a pre-ordered box, so the bootstrap SSH would fail.
	// +optional
	FleetName string `json:"fleetName,omitempty"`

	// NodeTaints are passed to the kubelet's `--register-with-taints` in the
	// generated self-join.
	// +optional
	NodeTaints []corev1.Taint `json:"nodeTaints,omitempty"`

	// RPNGroup is the online.net RPN (private network) group the server joins for
	// the private intra-region mesh. Unused at Qty-1 (a single public box needs
	// no private fabric); wired in the multi-box follow-up.
	// +optional
	RPNGroup string `json:"rpnGroup,omitempty"`

	// EgressBudgetMbps is the throughput, in Mbps, this box may assign across the
	// Kura pods it hosts — its NIC ceiling minus headroom. When set, the
	// controller advertises it as the Node's `tuist.dev/egress-mbps` extended
	// resource (the multi-box distribution follow-up). Zero leaves it unset.
	// +optional
	EgressBudgetMbps int32 `json:"egressBudgetMbps,omitempty"`
}

// DediboxMachineStatus is the observed state of the Machine.
type DediboxMachineStatus struct {
	// Ready is true once the server has joined the cluster and its Node reports
	// Ready=True. CAPI core reads this to mark the parent Machine Ready.
	// +optional
	Ready bool `json:"ready,omitempty"`

	// ServerID is the Scaleway Dedibox numeric server id, used for install polling
	// and status. Zero until a server is claimed.
	// +optional
	ServerID int `json:"serverID,omitempty"`

	// Zone is the Scaleway zone the adopted server lives in (e.g. fr-par-1),
	// recorded at adoption and used for every follow-up Dedibox API call and the
	// providerID. Empty until a server is claimed.
	// +optional
	Zone string `json:"zone,omitempty"`

	// Addresses surfaces the server's public address for kubectl describe.
	// +optional
	Addresses []clusterv1.MachineAddress `json:"addresses,omitempty"`

	// Phase tracks lifecycle: Pending | Adopting | Installing | Provisioning |
	// Bootstrapping | Ready | Deleting | Failed.
	// +optional
	Phase string `json:"phase,omitempty"`

	// FailureReason / FailureMessage are set on terminal failures.
	// +optional
	FailureReason *string `json:"failureReason,omitempty"`
	// +optional
	FailureMessage *string `json:"failureMessage,omitempty"`

	// Conditions are CAPI-style condition entries (Provisioned, NodeReady).
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`

	// BootstrapAttempts counts consecutive bootstrap failures on the current
	// server, reset on success or whenever the ServerID changes.
	// +optional
	BootstrapAttempts int32 `json:"bootstrapAttempts,omitempty"`

	// BootstrapRebootIssued records that a recovery reboot has already fired for
	// the current server. Cleared when the ServerID changes or on success.
	// +optional
	BootstrapRebootIssued bool `json:"bootstrapRebootIssued,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=dediboxmachines,scope=Namespaced,categories=cluster-api,shortName=dbm
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="ProviderID",type=string,JSONPath=".spec.providerID"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.ready"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// DediboxMachine is one Scaleway Dedibox (online.net) dedicated server in the
// cluster.
type DediboxMachine struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   DediboxMachineSpec   `json:"spec,omitempty"`
	Status DediboxMachineStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// DediboxMachineList is a list of DediboxMachine.
type DediboxMachineList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []DediboxMachine `json:"items"`
}

func init() {
	SchemeBuilder.Register(&DediboxMachine{}, &DediboxMachineList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter interface.
func (m *DediboxMachine) GetConditions() clusterv1.Conditions {
	return m.Status.Conditions
}

func (m *DediboxMachine) SetConditions(c clusterv1.Conditions) {
	m.Status.Conditions = c
}
