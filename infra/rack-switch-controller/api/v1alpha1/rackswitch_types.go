package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// ManagedBy names who changes a switch.
// +kubebuilder:validation:Enum=controller;standalone
type ManagedBy string

const (
	// ManagedByController is a switch adopted into the site's Omada
	// controller and converged by the rack switch controller.
	ManagedByController ManagedBy = "controller"
	// ManagedByStandalone is a switch changed over SSH by rack:fleet.
	ManagedByStandalone ManagedBy = "standalone"
)

// SpanningTreeMode is the switch-wide spanning-tree protocol.
// +kubebuilder:validation:Enum=off;stp;rstp;mstp
type SpanningTreeMode string

const (
	SpanningTreeOff  SpanningTreeMode = "off"
	SpanningTreeSTP  SpanningTreeMode = "stp"
	SpanningTreeRSTP SpanningTreeMode = "rstp"
	SpanningTreeMSTP SpanningTreeMode = "mstp"
)

// Drift is how the switch compared with its spec when last verified.
// +kubebuilder:validation:Enum=unknown;none;drifted
type Drift string

const (
	DriftUnknown Drift = "unknown"
	DriftNone    Drift = "none"
	DriftDrifted Drift = "drifted"
)

// Condition types.
const (
	// ConditionAdopted is true once the switch is adopted into the site.
	ConditionAdopted = "Adopted"
	// ConditionConverged is true once everything the spec's revision asks
	// for has been written and what the controller can read back matches.
	ConditionConverged = "Converged"
	// ConditionReady is true for an adopted, connected switch at its
	// revision with no drift. A switch later in the apply order waits for
	// it.
	ConditionReady = "Ready"
)

// PortAssignment is what is plugged into a port, as far as the site
// definition knows.
type PortAssignment struct {
	// +optional
	Port int `json:"port"`
	// +optional
	Purpose string `json:"purpose,omitempty"`
	// +optional
	Peer string `json:"peer,omitempty"`
	// +optional
	Detail string `json:"detail,omitempty"`
}

// Route is a static route on the switch's management interface.
type Route struct {
	// Destination prefix in CIDR notation.
	Destination string `json:"destination"`
	NextHop     string `json:"nextHop"`
}

// VLAN is a network the switch carries beyond management.
type VLAN struct {
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=4094
	ID   int    `json:"id"`
	Name string `json:"name"`
}

// LAG is a link aggregation group.
type LAG struct {
	// +kubebuilder:validation:Minimum=1
	ID int `json:"id"`
	// +kubebuilder:validation:MinItems=1
	Ports []int `json:"ports"`
}

// PortConfig is the desired configuration of one port.
type PortConfig struct {
	// +kubebuilder:validation:Minimum=1
	Port int `json:"port"`
	// Description the port carries. Empty means the controller's own
	// "Port<n>".
	// +optional
	Description string `json:"description,omitempty"`
	// Whether spanning tree runs on the port. Unset follows the port's
	// profile.
	// +optional
	SpanningTree *bool `json:"spanningTree,omitempty"`
	// VLAN carried untagged. Unset means the management VLAN.
	// +optional
	NativeVLAN int `json:"nativeVlan,omitempty"`
	// VLANs carried tagged.
	// +optional
	TaggedVLANs []int `json:"taggedVlans,omitempty"`
}

// SwitchConfig is the desired configuration of a switch the controller
// manages.
type SwitchConfig struct {
	// +optional
	Hostname string `json:"hostname,omitempty"`
	// +optional
	ManagementVLAN int `json:"managementVlan,omitempty"`
	// +optional
	ManagementPrefixLength int `json:"managementPrefixLength,omitempty"`
	// +optional
	Gateway string `json:"gateway,omitempty"`
	// +optional
	Routes []Route `json:"routes,omitempty"`
	// +optional
	SpanningTree SpanningTreeMode `json:"spanningTree,omitempty"`
	// Site-wide in the controller: every switch of a site has to agree.
	// +optional
	LLDP *bool `json:"lldp,omitempty"`
	// Site-wide in the controller: every switch of a site has to agree.
	// +optional
	SNMP *bool `json:"snmp,omitempty"`
	// Networks this switch carries beyond management.
	// +optional
	VLANs []VLAN `json:"vlans,omitempty"`
	// +optional
	LAGs []LAG `json:"lags,omitempty"`
	// Every port the model has.
	// +optional
	Ports []PortConfig `json:"ports,omitempty"`
}

// RackSwitchSpec is rendered from the site definition.
// +kubebuilder:validation:XValidation:rule="!has(self.managedBy) || self.managedBy != 'controller' || has(self.mac)",message="a switch the controller manages needs its mac"
type RackSwitchSpec struct {
	// The rack this switch belongs to.
	Site string `json:"site"`
	// tor or mgmt. Decides blast radius, and therefore apply order.
	Role string `json:"role"`
	// Key into infra/rack-switch-fleet/models.json.
	Model             string `json:"model"`
	ManagementAddress string `json:"managementAddress"`
	// Ascending, and strictly one switch at a time. The lowest has the
	// smallest blast radius and is the only one a change is tried on.
	ApplyOrder int `json:"applyOrder"`
	// Why this switch sits where it does in the order, in prose.
	// +optional
	ApplyNote string `json:"applyNote,omitempty"`
	// The 1Password item holding the local admin login. Named, not inlined:
	// the credential never belongs in an object or in git.
	// +optional
	CredentialItem string `json:"credentialItem,omitempty"`
	// Digest of the configuration rendered from the site definition. Status
	// is reported against this, so an observation can never be read as
	// applying to a revision it did not see.
	ConfigRevision string `json:"configRevision"`
	// What is plugged into each port, as far as the site definition knows.
	// +optional
	Ports []PortAssignment `json:"ports,omitempty"`
	// The switch's MAC address, lower case and colon separated. It is how
	// the Omada controller knows the switch.
	// +kubebuilder:validation:Pattern=`^([0-9a-f]{2}:){5}[0-9a-f]{2}$`
	// +optional
	MAC string `json:"mac,omitempty"`
	// Who changes the switch: the rack switch controller through the Omada
	// controller, or rack:fleet over SSH.
	// +kubebuilder:default=standalone
	// +optional
	ManagedBy ManagedBy `json:"managedBy,omitempty"`
	// The desired configuration of a switch the controller manages.
	// +optional
	Config *SwitchConfig `json:"config,omitempty"`
}

// RackSwitchStatus is written by the rack switch controller for a switch it
// manages, and by `rack:fleet publish` for a standalone one.
type RackSwitchStatus struct {
	// The configRevision this status was produced against.
	// +optional
	ObservedRevision string `json:"observedRevision,omitempty"`
	// The metadata.generation the controller last wrote everything for.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`
	// +optional
	Drift Drift `json:"drift,omitempty"`
	// +optional
	Reachable bool `json:"reachable"`
	// +optional
	LastVerified *metav1.Time `json:"lastVerified,omitempty"`
	// How many SSH connections this boot has spent, of roughly seven before
	// the daemon stops accepting. Visible because it is a consumable, and
	// running out looks like a healthy switch.
	// +optional
	ConnectionsUsedSinceBoot int `json:"connectionsUsedSinceBoot,omitempty"`
	// +optional
	Message string `json:"message,omitempty"`
	// Whether the switch is adopted into the site's Omada controller.
	// +optional
	Adopted bool `json:"adopted"`
	// The Omada controller's name for the device's state.
	// +optional
	ControllerStatus string `json:"controllerStatus,omitempty"`
	// Adopted, Converged and Ready.
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=rsw
// +kubebuilder:printcolumn:name="Site",type="string",JSONPath=".spec.site"
// +kubebuilder:printcolumn:name="Role",type="string",JSONPath=".spec.role"
// +kubebuilder:printcolumn:name="Address",type="string",JSONPath=".spec.managementAddress"
// +kubebuilder:printcolumn:name="Order",type="integer",JSONPath=".spec.applyOrder"
// +kubebuilder:printcolumn:name="Drift",type="string",JSONPath=".status.drift"
// +kubebuilder:printcolumn:name="Reachable",type="boolean",JSONPath=".status.reachable"
// +kubebuilder:printcolumn:name="Verified",type="date",JSONPath=".status.lastVerified"
// +kubebuilder:printcolumn:name="Managed By",type="string",JSONPath=".spec.managedBy"
// +kubebuilder:printcolumn:name="State",type="string",JSONPath=".status.controllerStatus",priority=1

// RackSwitch is one of a rack's switches, so its state is visible next to the
// RackHosts behind it rather than only in someone's terminal.
type RackSwitch struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RackSwitchSpec   `json:"spec,omitempty"`
	Status RackSwitchStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RackSwitchList is a list of RackSwitch.
type RackSwitchList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackSwitch `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackSwitch{}, &RackSwitchList{})
}
