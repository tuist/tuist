package v1alpha1

import (
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
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

	// PowerBudget is the draw at which the site's Mac minis stop taking new
	// runner VMs. Unset, nothing is held back.
	// +optional
	PowerBudget *RackSitePowerBudget `json:"powerBudget,omitempty"`
}

// RackSitePowerBudget is the draw at which a chain's, or the whole site's,
// Mac minis stop taking new runner VMs, so a chain stays under its breaker and
// the site under its contracted power. Running jobs finish.
type RackSitePowerBudget struct {
	// ChainAmps is the output current at which a transfer switch's chain stops
	// taking new runner VMs on the minis its PDUs power.
	ChainAmps resource.Quantity `json:"chainAmps"`

	// OtherWatts is what the site draws outside its transfer switches, which
	// nothing meters: dual-PSU gear on the colocation's own strips. The
	// switches together may draw the contracted power in effect less this.
	// +kubebuilder:validation:Minimum=0
	// +optional
	OtherWatts int64 `json:"otherWatts,omitempty"`
}

// RackSiteChain is one transfer switch's chain as the controller last
// judged it.
type RackSiteChain struct {
	// Name is the transfer switch, or the PDU for one that hangs off none.
	Name string `json:"name"`

	// CurrentAmps is the chain's output current, unset without a recent
	// reading.
	// +optional
	CurrentAmps *resource.Quantity `json:"currentAmps,omitempty"`

	// Watts is the chain's draw, unset without a recent reading.
	// +optional
	Watts *resource.Quantity `json:"watts,omitempty"`

	// Hosts is how many Mac minis the chain's PDUs power.
	// +optional
	Hosts int `json:"hosts,omitempty"`

	// Held is true while the chain's minis take no new runner VMs.
	// +optional
	Held bool `json:"held,omitempty"`

	// HeldSince is when the chain was last held.
	// +optional
	HeldSince *metav1.Time `json:"heldSince,omitempty"`
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

	// PowerBudgetWatts is what the site's transfer switches may draw together
	// at the contracted step in effect: its watts less spec.powerBudget's
	// otherWatts. 0 without a budget or a step.
	// +optional
	PowerBudgetWatts int64 `json:"powerBudgetWatts,omitempty"`

	// MeteredWatts is what the site's transfer switches drew together at the
	// last judgement, unset when a switch had no recent reading.
	// +optional
	MeteredWatts *resource.Quantity `json:"meteredWatts,omitempty"`

	// SiteHeld is true while every Mac mini at the site takes no new runner
	// VMs because the site is over its budget.
	// +optional
	SiteHeld bool `json:"siteHeld,omitempty"`

	// SiteHeldSince is when the site was last held.
	// +optional
	SiteHeldSince *metav1.Time `json:"siteHeldSince,omitempty"`

	// Chains is each transfer switch's chain, by name.
	// +optional
	// +listType=map
	// +listMapKey=name
	Chains []RackSiteChain `json:"chains,omitempty"`

	// Conditions: PowerAdmission.
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// GetConditions returns the site's conditions.
func (s *RackSite) GetConditions() clusterv1.Conditions { return s.Status.Conditions }

// SetConditions sets the site's conditions.
func (s *RackSite) SetConditions(c clusterv1.Conditions) { s.Status.Conditions = c }

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=racksites,scope=Namespaced,shortName=rsite
// +kubebuilder:printcolumn:name="Contracted W",type=integer,JSONPath=".status.contractedPowerWatts"
// +kubebuilder:printcolumn:name="Since",type=string,JSONPath=".status.contractedPowerSince"
// +kubebuilder:printcolumn:name="Next Change",type=string,JSONPath=".status.nextContractedPowerChange"
// +kubebuilder:printcolumn:name="Budget W",type=integer,JSONPath=".status.powerBudgetWatts"
// +kubebuilder:printcolumn:name="Metered W",type=string,JSONPath=".status.meteredWatts"
// +kubebuilder:printcolumn:name="Admission",type=string,JSONPath=".status.conditions[?(@.type=='PowerAdmission')].status"

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
