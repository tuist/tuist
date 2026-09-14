package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// CloudflareCustomRuleSpec describes one rule in a zone's
// http_request_firewall_custom entry-point ruleset.
//
// +kubebuilder:validation:XValidation:rule="self.zoneId == oldSelf.zoneId",message="zoneId is immutable"
// +kubebuilder:validation:XValidation:rule="has(self.adopt) || self.createNewRule == true",message="either adopt.ruleId or createNewRule=true must be set"
type CloudflareCustomRuleSpec struct {
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="zoneId is immutable"
	ZoneID string `json:"zoneId"`

	Description string `json:"description"`
	Expression  string `json:"expression"`

	// +kubebuilder:validation:Enum=block;managed_challenge;js_challenge;log
	Action string `json:"action"`

	// +kubebuilder:default=read_only
	Mode ReconcileMode `json:"mode,omitempty"`

	// +kubebuilder:default=false
	Paused bool `json:"paused,omitempty"`

	// +kubebuilder:default=true
	Enabled *bool `json:"enabled,omitempty"`

	// +kubebuilder:validation:XValidation:rule="!has(oldSelf) || self == oldSelf",message="adopt is immutable once set"
	Adopt *AdoptRule `json:"adopt,omitempty"`

	// +kubebuilder:default=false
	CreateNewRule bool `json:"createNewRule,omitempty"`

	// +kubebuilder:default=true
	RetainOnDelete bool `json:"retainOnDelete,omitempty"`
}

func (s *CloudflareCustomRuleSpec) IsEnabled() bool {
	return s.Enabled == nil || *s.Enabled
}

func (s *CloudflareCustomRuleSpec) EffectiveMode() ReconcileMode {
	if s.Mode == "" {
		return ReconcileModeReadOnly
	}
	return s.Mode
}

type CloudflareCustomRuleStatus struct {
	Conditions         []metav1.Condition `json:"conditions,omitempty" patchStrategy:"merge" patchMergeKey:"type"`
	Ref                string             `json:"ref,omitempty"`
	RuleID             string             `json:"ruleId,omitempty"`
	RulesetID          string             `json:"rulesetId,omitempty"`
	ManagedZoneID      string             `json:"managedZoneId,omitempty"`
	ObservedGeneration int64              `json:"observedGeneration,omitempty"`
	Mode               ReconcileMode      `json:"mode,omitempty"`
	ProposedChanges    string             `json:"proposedChanges,omitempty"`
	Message            string             `json:"message,omitempty"`
	LastReconciledAt   *metav1.Time       `json:"lastReconciledAt,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=cfcustom
// +kubebuilder:printcolumn:name="Zone",type="string",JSONPath=".spec.zoneId"
// +kubebuilder:printcolumn:name="Mode",type="string",JSONPath=".spec.mode"
// +kubebuilder:printcolumn:name="Action",type="string",JSONPath=".spec.action"
// +kubebuilder:printcolumn:name="Message",type="string",JSONPath=".status.message"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"
type CloudflareCustomRule struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   CloudflareCustomRuleSpec   `json:"spec,omitempty"`
	Status CloudflareCustomRuleStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type CloudflareCustomRuleList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []CloudflareCustomRule `json:"items"`
}

func init() {
	SchemeBuilder.Register(&CloudflareCustomRule{}, &CloudflareCustomRuleList{})
}

func (in *CloudflareCustomRuleSpec) DeepCopyInto(out *CloudflareCustomRuleSpec) {
	*out = *in
	if in.Enabled != nil {
		in, out := &in.Enabled, &out.Enabled
		*out = new(bool)
		**out = **in
	}
	if in.Adopt != nil {
		in, out := &in.Adopt, &out.Adopt
		*out = new(AdoptRule)
		**out = **in
	}
}

func (in *CloudflareCustomRule) DeepCopyInto(out *CloudflareCustomRule) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ObjectMeta.DeepCopyInto(&out.ObjectMeta)
	in.Spec.DeepCopyInto(&out.Spec)
	in.Status.DeepCopyInto(&out.Status)
}

func (in *CloudflareCustomRule) DeepCopy() *CloudflareCustomRule {
	if in == nil {
		return nil
	}
	out := new(CloudflareCustomRule)
	in.DeepCopyInto(out)
	return out
}

func (in *CloudflareCustomRule) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

func (in *CloudflareCustomRuleList) DeepCopyInto(out *CloudflareCustomRuleList) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ListMeta.DeepCopyInto(&out.ListMeta)
	if in.Items != nil {
		in, out := &in.Items, &out.Items
		*out = make([]CloudflareCustomRule, len(*in))
		for i := range *in {
			(*in)[i].DeepCopyInto(&(*out)[i])
		}
	}
}

func (in *CloudflareCustomRuleList) DeepCopy() *CloudflareCustomRuleList {
	if in == nil {
		return nil
	}
	out := new(CloudflareCustomRuleList)
	in.DeepCopyInto(out)
	return out
}

func (in *CloudflareCustomRuleList) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

func (in *CloudflareCustomRuleStatus) DeepCopyInto(out *CloudflareCustomRuleStatus) {
	*out = *in
	if in.Conditions != nil {
		in, out := &in.Conditions, &out.Conditions
		*out = make([]metav1.Condition, len(*in))
		copy(*out, *in)
	}
	if in.LastReconciledAt != nil {
		in, out := &in.LastReconciledAt, &out.LastReconciledAt
		*out = (*in).DeepCopy()
	}
}
