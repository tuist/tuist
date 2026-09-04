package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// CloudflareWAFCustomRuleSpec describes one rule of the zone's
// `http_request_firewall_custom` ruleset — the Custom Rules screen in
// the Cloudflare dashboard's Security → Security rules view.
type CloudflareWAFCustomRuleSpec struct {
	// ZoneID is the Cloudflare zone the rule applies to.
	ZoneID string `json:"zoneId"`

	// Description is the human-readable label shown in the dashboard.
	Description string `json:"description"`

	// Expression is the request match expression in Cloudflare's
	// wireshark syntax. Matching requests receive Action.
	Expression string `json:"expression"`

	// Action is what Cloudflare does with the request.
	// +kubebuilder:validation:Enum=block;managed_challenge;js_challenge;challenge;log;skip;allow
	Action string `json:"action"`

	// Enabled controls whether the rule is active. Defaults to true.
	// +kubebuilder:default=true
	Enabled *bool `json:"enabled,omitempty"`
}

// CloudflareWAFCustomRuleStatus reports the last reconcile outcome.
type CloudflareWAFCustomRuleStatus struct {
	Ref                string       `json:"ref,omitempty"`
	RuleID             string       `json:"ruleId,omitempty"`
	RulesetID          string       `json:"rulesetId,omitempty"`
	ObservedGeneration int64        `json:"observedGeneration,omitempty"`
	Message            string       `json:"message,omitempty"`
	LastReconciledAt   *metav1.Time `json:"lastReconciledAt,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=cfwaf
// +kubebuilder:printcolumn:name="Zone",type="string",JSONPath=".spec.zoneId"
// +kubebuilder:printcolumn:name="Action",type="string",JSONPath=".spec.action"
// +kubebuilder:printcolumn:name="Message",type="string",JSONPath=".status.message"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// CloudflareWAFCustomRule is one rule in a zone's WAF custom-firewall
// ruleset.
type CloudflareWAFCustomRule struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   CloudflareWAFCustomRuleSpec   `json:"spec,omitempty"`
	Status CloudflareWAFCustomRuleStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// CloudflareWAFCustomRuleList is a list of CloudflareWAFCustomRule.
type CloudflareWAFCustomRuleList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []CloudflareWAFCustomRule `json:"items"`
}

func init() {
	SchemeBuilder.Register(&CloudflareWAFCustomRule{}, &CloudflareWAFCustomRuleList{})
}

func (s *CloudflareWAFCustomRuleSpec) IsEnabled() bool {
	return s.Enabled == nil || *s.Enabled
}

// SetRulesetStatus implements controllers.RulesetStatusWriter.
func (s *CloudflareWAFCustomRuleStatus) SetRulesetStatus(ref, rulesetID, ruleID, message string, generation int64, now *metav1.Time) {
	s.Ref = ref
	s.RulesetID = rulesetID
	s.RuleID = ruleID
	s.Message = message
	s.ObservedGeneration = generation
	s.LastReconciledAt = now
}

func (in *CloudflareWAFCustomRuleSpec) DeepCopyInto(out *CloudflareWAFCustomRuleSpec) {
	*out = *in
	if in.Enabled != nil {
		v := *in.Enabled
		out.Enabled = &v
	}
}

func (in *CloudflareWAFCustomRuleSpec) DeepCopy() *CloudflareWAFCustomRuleSpec {
	if in == nil {
		return nil
	}
	o := new(CloudflareWAFCustomRuleSpec)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareWAFCustomRuleStatus) DeepCopyInto(out *CloudflareWAFCustomRuleStatus) {
	*out = *in
	if in.LastReconciledAt != nil {
		out.LastReconciledAt = (*in.LastReconciledAt).DeepCopy()
	}
}

func (in *CloudflareWAFCustomRuleStatus) DeepCopy() *CloudflareWAFCustomRuleStatus {
	if in == nil {
		return nil
	}
	o := new(CloudflareWAFCustomRuleStatus)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareWAFCustomRule) DeepCopyInto(out *CloudflareWAFCustomRule) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ObjectMeta.DeepCopyInto(&out.ObjectMeta)
	in.Spec.DeepCopyInto(&out.Spec)
	in.Status.DeepCopyInto(&out.Status)
}

func (in *CloudflareWAFCustomRule) DeepCopy() *CloudflareWAFCustomRule {
	if in == nil {
		return nil
	}
	o := new(CloudflareWAFCustomRule)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareWAFCustomRule) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

func (in *CloudflareWAFCustomRuleList) DeepCopyInto(out *CloudflareWAFCustomRuleList) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ListMeta.DeepCopyInto(&out.ListMeta)
	if in.Items != nil {
		out.Items = make([]CloudflareWAFCustomRule, len(in.Items))
		for i := range in.Items {
			in.Items[i].DeepCopyInto(&out.Items[i])
		}
	}
}

func (in *CloudflareWAFCustomRuleList) DeepCopy() *CloudflareWAFCustomRuleList {
	if in == nil {
		return nil
	}
	o := new(CloudflareWAFCustomRuleList)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareWAFCustomRuleList) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}
