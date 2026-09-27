package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// RackPDUSpec is one switched PDU, rendered from the rack's site definition
// (infra/rack-switch-fleet).
type RackPDUSpec struct {
	// Site is the rack site (e.g. `ber1`).
	Site string `json:"site"`

	// Model is the PDU's hardware model. Only the Eaton Rack PDU G4 is driven.
	// +kubebuilder:validation:Enum=evmafc20a
	Model string `json:"model"`

	// MAC is the management card's MAC, against which the rack's edge reserves
	// Address. Empty until someone has read it off the unit: the controller
	// still adopts a card already at Address, and reports that a factory card
	// would not get there.
	// +kubebuilder:validation:Pattern=`^$|^([0-9a-f]{2}:){5}[0-9a-f]{2}$`
	// +optional
	MAC string `json:"mac,omitempty"`

	// Address is the card's fixed address on the rack's management LAN.
	// +kubebuilder:validation:Pattern=`^([0-9]{1,3}\.){3}[0-9]{1,3}$`
	Address string `json:"address"`

	// Chain is the transfer switch the PDU hangs off.
	// +optional
	Chain string `json:"chain,omitempty"`

	// ManagedBy gates every write: only `controller` is adopted and
	// configured. `standalone` is never contacted.
	// +kubebuilder:default=standalone
	ManagedBy RackCardManagedBy `json:"managedBy,omitempty"`

	// OutletStateOnStartup is every outlet's state when the PDU powers up.
	// `on`, so a Mac comes back after a power loss without anyone switching
	// its outlet.
	// +kubebuilder:validation:Enum=on;off;last known state
	// +kubebuilder:default=on
	OutletStateOnStartup string `json:"outletStateOnStartup,omitempty"`
}

// RackPDUStatus is what the controller observed.
type RackPDUStatus struct {
	RackCardStatus `json:",inline"`

	// OutletCount is how many outlets the card reports.
	// +optional
	OutletCount int `json:"outletCount,omitempty"`

	// Conditions: Adopted, Converged, Ready, CertificateChanged,
	// AddressReserved.
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=rackpdus,scope=Namespaced,shortName=rpdu
// +kubebuilder:printcolumn:name="Site",type=string,JSONPath=".spec.site"
// +kubebuilder:printcolumn:name="Address",type=string,JSONPath=".spec.address"
// +kubebuilder:printcolumn:name="Managed By",type=string,JSONPath=".spec.managedBy"
// +kubebuilder:printcolumn:name="Adopted",type=boolean,JSONPath=".status.adopted"
// +kubebuilder:printcolumn:name="Drift",type=string,JSONPath=".status.drift"
// +kubebuilder:printcolumn:name="Verified",type=date,JSONPath=".status.lastVerified"
// +kubebuilder:printcolumn:name="Serial",type=string,priority=1,JSONPath=".status.serialNumber"
// +kubebuilder:printcolumn:name="Firmware",type=string,priority=1,JSONPath=".status.firmwareVersion"

// RackPDU is one switched PDU in a rack we operate, adopted and kept
// configured by the RackPDU controller.
type RackPDU struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RackPDUSpec   `json:"spec,omitempty"`
	Status RackPDUStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RackPDUList is a list of RackPDU.
type RackPDUList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackPDU `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackPDU{}, &RackPDUList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter interface.
func (p *RackPDU) GetConditions() clusterv1.Conditions {
	return p.Status.Conditions
}

func (p *RackPDU) SetConditions(c clusterv1.Conditions) {
	p.Status.Conditions = c
}

// CardStatus is the part of the status every rack power device shares.
func (p *RackPDU) CardStatus() *RackCardStatus {
	return &p.Status.RackCardStatus
}
