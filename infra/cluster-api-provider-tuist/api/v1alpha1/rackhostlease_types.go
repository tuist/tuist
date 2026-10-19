package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// The phases the lending operator asks for in spec.phase.
const (
	// LeaseOffered: the lender offers the host. The borrower publishes the key
	// it will dial with; nothing changes on the host yet.
	LeaseOffered = "Offered"
	// LeaseLent: the lender handed the runtime over and authorized the key in
	// grantedKeyFingerprint. The borrower pushes its runtime to the host.
	LeaseLent = "Lent"
	// LeaseReturning: the lender wants the host back. The borrower drains its
	// Node, revokes the host's identity and stops pushing.
	LeaseReturning = "Returning"
)

// The states the borrowing operator reports in status.state.
const (
	// LeaseAccepted: the borrower runs this host and published its key.
	LeaseAccepted = "Accepted"
	// LeaseRefused: the borrower does not run this host (it is not in its
	// `--rack-lease-host` list) and holds nothing on it.
	LeaseRefused = "Refused"
	// LeaseActive: the borrower's runtime is on the host.
	LeaseActive = "Active"
	// LeaseDraining: the borrower cordoned its Node and waits for its jobs.
	LeaseDraining = "Draining"
	// LeaseReleased: the borrower holds nothing on the host any more: no Node,
	// no identity, no pushes. The lender may take the runtime back.
	LeaseReleased = "Released"
)

// RackHostLeaseSpec is written by the operator of the env that owns the
// host's site. It lives in the borrowing cluster, named after the host.
type RackHostLeaseSpec struct {
	// Lender is the env that owns the host's site and lends its runtime.
	// +kubebuilder:validation:MinLength=1
	Lender string `json:"lender"`

	// Phase is what the lender asks for: Offered, Lent or Returning.
	// +kubebuilder:validation:Enum=Offered;Lent;Returning
	Phase string `json:"phase"`

	// Host is what the borrower needs to reach the host and size its Node.
	Host RackHostLeaseHost `json:"host"`

	// GrantedKeyFingerprint is the SHA-256 fingerprint of the key the lender
	// authorized on the host for this lease. The borrower dials with its key
	// only once it matches, so a rotated key waits for its grant.
	// +optional
	GrantedKeyFingerprint string `json:"grantedKeyFingerprint,omitempty"`

	// PreviousNodeName is a Node the host registered in the borrowing cluster
	// before this lease, under the lender's name for it: a host lent by hand
	// with a kubeconfig. The borrower drains it before taking the host over and
	// deletes it after.
	// +optional
	PreviousNodeName string `json:"previousNodeName,omitempty"`
}

// RackHostLeaseHost carries the physical facts of a lent host. None of it is a
// credential.
type RackHostLeaseHost struct {
	// Serial is the Mac's hardware serial.
	// +optional
	Serial string `json:"serial,omitempty"`

	// Address is the host's address on the rack's machines segment, which the
	// rack's edges route to from the tailnet.
	// +kubebuilder:validation:MinLength=1
	Address string `json:"address"`

	// SSHUser is the account the lease key is authorized for.
	// +optional
	SSHUser string `json:"sshUser,omitempty"`

	// SSHIngressAllowCIDRs are the subnet routers a dial to Address arrives
	// from, which the host's SSH ingress guard admits.
	// +optional
	SSHIngressAllowCIDRs []string `json:"sshIngressAllowCIDRs,omitempty"`

	// Site composes the host's providerID.
	// +kubebuilder:validation:MinLength=1
	Site string `json:"site"`

	// HostKeyFingerprint is the host key the lender pinned. The borrower
	// verifies it on every dial instead of trusting the first key it sees.
	// +optional
	HostKeyFingerprint string `json:"hostKeyFingerprint,omitempty"`

	// Machine is the host's sizing with the lender's defaults applied: what
	// the hardware is, not how either env runs it.
	// +optional
	Machine RackHostMachine `json:"machine,omitempty"`
}

// RackHostLeaseStatus is written by the borrowing operator.
type RackHostLeaseStatus struct {
	// HostAgentStatus is the drift bookkeeping for the borrower's runtime on
	// the host, shared with the machine kinds.
	HostAgentStatus `json:",inline"`

	// State is one of Accepted, Refused, Active, Draining or Released.
	// +optional
	State string `json:"state,omitempty"`

	// SSHPublicKey is the key the borrower dials the host with, one
	// authorized_keys line. The lender authorizes it.
	// +optional
	SSHPublicKey string `json:"sshPublicKey,omitempty"`

	// Node is the Node the host registers in the borrowing cluster.
	// +optional
	Node string `json:"node,omitempty"`

	// NodeReady mirrors that Node's Ready condition.
	// +optional
	NodeReady bool `json:"nodeReady,omitempty"`

	// Conditions are CAPI-style condition entries (Bootstrapped).
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=rackhostleases,scope=Namespaced,categories=cluster-api,shortName=rhl
// +kubebuilder:printcolumn:name="Lender",type=string,JSONPath=".spec.lender"
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".spec.phase"
// +kubebuilder:printcolumn:name="State",type=string,JSONPath=".status.state"
// +kubebuilder:printcolumn:name="Node",type=string,JSONPath=".status.node"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.nodeReady"
// +kubebuilder:printcolumn:name="Runtime",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="Address",type=string,priority=1,JSONPath=".spec.host.address"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// RackHostLease is a rack host another env lends this cluster: the handshake
// between the operator that owns the host's site, which writes the spec, and
// this cluster's operator, which runs the host's runner runtime and writes the
// status.
type RackHostLease struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RackHostLeaseSpec   `json:"spec,omitempty"`
	Status RackHostLeaseStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RackHostLeaseList is a list of RackHostLease.
type RackHostLeaseList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackHostLease `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackHostLease{}, &RackHostLeaseList{})
}

// HostAgent gives the lease the drift bookkeeping the machine kinds share.
func (l *RackHostLease) HostAgent() *HostAgentStatus {
	return &l.Status.HostAgentStatus
}

// GetConditions / SetConditions implement the CAPI conditions.Setter interface.
func (l *RackHostLease) GetConditions() clusterv1.Conditions {
	return l.Status.Conditions
}

func (l *RackHostLease) SetConditions(c clusterv1.Conditions) {
	l.Status.Conditions = c
}
