package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// RackATSInputState is how a transfer switch reports one of its sources.
// +kubebuilder:validation:Enum=good;derated;outOfRange;missing;unknown
type RackATSInputState string

const (
	// RackATSInputGood is a source in its normal voltage and frequency range:
	// the switch can transfer to it.
	RackATSInputGood RackATSInputState = "good"
	// RackATSInputDerated is a source in its derated voltage range.
	RackATSInputDerated RackATSInputState = "derated"
	// RackATSInputOutOfRange is a source outside the range the switch
	// accepts.
	RackATSInputOutOfRange RackATSInputState = "outOfRange"
	// RackATSInputMissing is a source with no voltage.
	RackATSInputMissing RackATSInputState = "missing"
	// RackATSInputUnknown is a source whose state the card reported in a way
	// the controller does not recognise.
	RackATSInputUnknown RackATSInputState = "unknown"
)

// RackATSSpec is one automatic transfer switch, rendered from the rack's site
// definition (infra/rack-switch-fleet).
type RackATSSpec struct {
	// Site is the rack site (e.g. `ber1`).
	Site string `json:"site"`

	// Model is the transfer switch's hardware model. Only the Eaton EATS16N
	// (ATS 16 Netpack) is driven.
	// +kubebuilder:validation:Enum=eats16n
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

	// ManagedBy gates every write: only `controller` is adopted, configured
	// and observed. `standalone` is never contacted.
	// +kubebuilder:default=standalone
	ManagedBy RackCardManagedBy `json:"managedBy,omitempty"`

	// PreferredSource is the source the switch powers the load from whenever
	// that source is good: 1 or 2, as the switch numbers its inputs.
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=2
	// +kubebuilder:default=1
	PreferredSource int32 `json:"preferredSource,omitempty"`
}

// RackATSInput is one source as the switch reported it at the last
// observation.
type RackATSInput struct {
	// Source is the input's number, 1 or 2.
	Source int32 `json:"source"`

	// State is how the switch judges the source.
	State RackATSInputState `json:"state"`

	// Voltage is the source's voltage in volts, when the card reports it.
	// +optional
	Voltage string `json:"voltage,omitempty"`

	// Frequency is the source's frequency in hertz, when the card reports it.
	// +optional
	Frequency string `json:"frequency,omitempty"`

	// Detail is what the card reported that the state was read from.
	// +optional
	Detail string `json:"detail,omitempty"`
}

// RackATSTransfer is a change of the source powering the load, as the
// controller observed it between two observations.
type RackATSTransfer struct {
	From int32 `json:"from"`
	To   int32 `json:"to"`
	// ObservedAt is the observation that first saw the load on To.
	ObservedAt metav1.Time `json:"observedAt"`
}

// RackATSStatus is what the controller observed.
type RackATSStatus struct {
	RackCardStatus `json:",inline"`

	// Card names the kind of management card the controller speaks to and
	// what it identified itself as.
	// +optional
	Card string `json:"card,omitempty"`

	// DeviceModel, DeviceSerialNumber and DeviceFirmwareVersion are the
	// transfer switch's own, behind its card.
	// +optional
	DeviceModel string `json:"deviceModel,omitempty"`
	// +optional
	DeviceSerialNumber string `json:"deviceSerialNumber,omitempty"`
	// +optional
	DeviceFirmwareVersion string `json:"deviceFirmwareVersion,omitempty"`

	// ActiveSource is the source powering the load at the last observation:
	// 1 or 2, 0 when neither does or the card did not say.
	// +optional
	ActiveSource int32 `json:"activeSource,omitempty"`

	// PreferredSource is the preferred source the card reports, 0 when it
	// reports none the controller recognises.
	// +optional
	PreferredSource int32 `json:"preferredSource,omitempty"`

	// Inputs are the switch's two sources at the last observation.
	// +optional
	Inputs []RackATSInput `json:"inputs,omitempty"`

	// LastTransfer is the last change of the active source the controller
	// observed.
	// +optional
	LastTransfer *RackATSTransfer `json:"lastTransfer,omitempty"`

	// LastObserved is when the switch's sources were last read.
	// +optional
	LastObserved *metav1.Time `json:"lastObserved,omitempty"`

	// Conditions: Adopted, Converged, Ready, Redundant, CertificateChanged,
	// AddressReserved.
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=rackatses,singular=rackats,scope=Namespaced,shortName=rats
// +kubebuilder:printcolumn:name="Site",type=string,JSONPath=".spec.site"
// +kubebuilder:printcolumn:name="Address",type=string,JSONPath=".spec.address"
// +kubebuilder:printcolumn:name="Managed By",type=string,JSONPath=".spec.managedBy"
// +kubebuilder:printcolumn:name="Adopted",type=boolean,JSONPath=".status.adopted"
// +kubebuilder:printcolumn:name="Active",type=integer,JSONPath=".status.activeSource"
// +kubebuilder:printcolumn:name="Preferred",type=integer,JSONPath=".spec.preferredSource"
// +kubebuilder:printcolumn:name="Redundant",type=string,JSONPath=".status.conditions[?(@.type==\"Redundant\")].status"
// +kubebuilder:printcolumn:name="Observed",type=date,JSONPath=".status.lastObserved"
// +kubebuilder:printcolumn:name="Card",type=string,priority=1,JSONPath=".status.card"
// +kubebuilder:printcolumn:name="Serial",type=string,priority=1,JSONPath=".status.deviceSerialNumber"

// RackATS is one automatic transfer switch in a rack we operate, adopted,
// kept configured and observed by the RackATS controller.
type RackATS struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RackATSSpec   `json:"spec,omitempty"`
	Status RackATSStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RackATSList is a list of RackATS.
type RackATSList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackATS `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackATS{}, &RackATSList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter interface.
func (a *RackATS) GetConditions() clusterv1.Conditions {
	return a.Status.Conditions
}

func (a *RackATS) SetConditions(c clusterv1.Conditions) {
	a.Status.Conditions = c
}

// CardStatus is the part of the status every rack power device shares.
func (a *RackATS) CardStatus() *RackCardStatus {
	return &a.Status.RackCardStatus
}
