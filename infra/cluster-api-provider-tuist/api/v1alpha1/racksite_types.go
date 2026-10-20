package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// RackSiteContractedPower is one step of a site's contracted power.
type RackSiteContractedPower struct {
	// From is the first day, in UTC, the step applies.
	// +kubebuilder:validation:Format=date
	From string `json:"from"`

	// Watts is the contracted power from that day.
	// +kubebuilder:validation:Minimum=1
	Watts int64 `json:"watts"`
}

// RackSiteSpec is one rack site, rendered from its site definition
// (infra/rack-switch-fleet). The object's name is the site (e.g. `ber1`).
type RackSiteSpec struct {
	// ContractedPower is the power the site's colocation contract allows, as
	// steps. Each applies from its day until the next step's; the last one
	// stays in effect.
	// +optional
	// +listType=map
	// +listMapKey=from
	ContractedPower []RackSiteContractedPower `json:"contractedPower,omitempty"`
}

// RackSiteStatus is what the controller derived from the spec.
type RackSiteStatus struct {
	// ContractedPowerWatts is the step in effect, 0 when none is yet.
	// +optional
	ContractedPowerWatts int64 `json:"contractedPowerWatts,omitempty"`

	// ContractedPowerSince is the first day of the step in effect.
	// +optional
	ContractedPowerSince string `json:"contractedPowerSince,omitempty"`

	// NextContractedPowerChange is the first day of the next step.
	// +optional
	NextContractedPowerChange string `json:"nextContractedPowerChange,omitempty"`

	// Message says why the spec could not be read, empty when it could.
	// +optional
	Message string `json:"message,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=racksites,scope=Namespaced,shortName=rsite
// +kubebuilder:printcolumn:name="Contracted W",type=integer,JSONPath=".status.contractedPowerWatts"
// +kubebuilder:printcolumn:name="Since",type=string,JSONPath=".status.contractedPowerSince"
// +kubebuilder:printcolumn:name="Next Change",type=string,JSONPath=".status.nextContractedPowerChange"

// RackSite is a rack site we operate, as a whole: what belongs to the site
// rather than to one device in it.
type RackSite struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RackSiteSpec   `json:"spec,omitempty"`
	Status RackSiteStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RackSiteList is a list of RackSite.
type RackSiteList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackSite `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackSite{}, &RackSiteList{})
}
