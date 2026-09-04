package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// CloudflareRateLimitSpec describes one entry of the zone's
// `http_ratelimit` ruleset. Fields map directly onto Cloudflare's Advanced
// Rate Limiting rule shape so an operator reading this struct can render a
// Ruleset rule without translation.
type CloudflareRateLimitSpec struct {
	// ZoneID is the Cloudflare zone the rule applies to. The zone must live
	// in the account this operator is credentialled against.
	ZoneID string `json:"zoneId"`

	// Description is the human-readable label shown in the Cloudflare
	// dashboard. Kept in sync on every reconcile.
	Description string `json:"description"`

	// Expression is the request-match expression in Cloudflare's wireshark
	// syntax (e.g. `http.request.method eq "GET"`). Requests that match are
	// counted for rate limiting.
	Expression string `json:"expression"`

	// Action is what Cloudflare does when the threshold trips.
	// +kubebuilder:validation:Enum=block;managed_challenge;js_challenge;log
	Action string `json:"action"`

	// RateLimit holds the counting and mitigation parameters.
	RateLimit CloudflareRateLimitParameters `json:"ratelimit"`

	// Enabled controls whether the rule is active in Cloudflare. Defaults
	// to true. Setting it to false leaves the rule in place but disabled,
	// which is useful for staged rollouts and quick disable during an
	// incident without losing the definition.
	// +kubebuilder:default=true
	Enabled *bool `json:"enabled,omitempty"`
}

// CloudflareRateLimitParameters mirrors the Cloudflare rule's `ratelimit`
// object: how requests are counted and how long the mitigation lasts.
type CloudflareRateLimitParameters struct {
	// Characteristics keys the counter. Each entry is a Cloudflare
	// characteristic name (e.g. "ip.src", "cf.colo.id"). Multiple entries
	// combine as a compound key.
	Characteristics []string `json:"characteristics"`

	// RequestsPerPeriod is the threshold; when the counter for a given key
	// crosses this within Period, Action fires.
	// +kubebuilder:validation:Minimum=1
	RequestsPerPeriod int `json:"requestsPerPeriod"`

	// Period is the window in seconds over which requests are counted.
	// Cloudflare only accepts a fixed set of values: 10, 60, 600, 3600.
	// +kubebuilder:validation:Enum=10;60;600;3600
	Period int `json:"period"`

	// MitigationTimeoutSeconds is how long Action stays applied after the
	// threshold trips. -1 means "until the counter falls under the
	// threshold" (Cloudflare's "same as period" default).
	MitigationTimeoutSeconds int `json:"mitigationTimeoutSeconds"`

	// CountingExpression narrows what is counted (as opposed to what
	// matches). When set, only requests / responses matching this
	// expression tick the counter; empty means every match ticks.
	// Cloudflare infers the phase from the fields referenced in the
	// expression — an expression that reads http.response.headers
	// counts in the response phase automatically.
	CountingExpression string `json:"countingExpression,omitempty"`
}

// CloudflareRateLimitStatus reports the last reconcile outcome for
// operator visibility. Cloudflare is the source of truth; this is a
// summary, not authoritative.
type CloudflareRateLimitStatus struct {
	// Ref is the stable identifier the operator sets on the Cloudflare
	// rule so it can find and update the same rule across reconciles
	// without a state backend.
	Ref string `json:"ref,omitempty"`

	// RuleID is the Cloudflare-assigned id of the rule, useful for cross-
	// referencing dashboard URLs and API calls in troubleshooting.
	RuleID string `json:"ruleId,omitempty"`

	// RulesetID is the id of the zone's http_ratelimit ruleset that owns
	// the rule.
	RulesetID string `json:"rulesetId,omitempty"`

	// ObservedGeneration is the last spec generation the operator has
	// successfully reconciled.
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// Message surfaces the last reconcile outcome ("reconciled",
	// "no-op", or a short error summary).
	Message string `json:"message,omitempty"`

	LastReconciledAt *metav1.Time `json:"lastReconciledAt,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=cfrl
// +kubebuilder:printcolumn:name="Zone",type="string",JSONPath=".spec.zoneId"
// +kubebuilder:printcolumn:name="Action",type="string",JSONPath=".spec.action"
// +kubebuilder:printcolumn:name="Requests",type="integer",JSONPath=".spec.ratelimit.requestsPerPeriod"
// +kubebuilder:printcolumn:name="Period",type="integer",JSONPath=".spec.ratelimit.period"
// +kubebuilder:printcolumn:name="Message",type="string",JSONPath=".status.message"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// CloudflareRateLimit is one rule in a zone's http_ratelimit ruleset.
type CloudflareRateLimit struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   CloudflareRateLimitSpec   `json:"spec,omitempty"`
	Status CloudflareRateLimitStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// CloudflareRateLimitList is a list of CloudflareRateLimit.
type CloudflareRateLimitList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []CloudflareRateLimit `json:"items"`
}

func init() {
	SchemeBuilder.Register(&CloudflareRateLimit{}, &CloudflareRateLimitList{})
}

// IsEnabled defaults to true when Enabled is nil, matching the +kubebuilder
// default; a Go reader that constructs the type without going through the
// API server also gets the intended behaviour.
func (s *CloudflareRateLimitSpec) IsEnabled() bool {
	return s.Enabled == nil || *s.Enabled
}

// SetRulesetStatus stamps the shared ruleset status fields onto the
// CR's Status subresource. Implements controllers.RulesetStatusWriter
// so the operator's shared reconciler can write status without caring
// which concrete CRD it is looking at.
func (s *CloudflareRateLimitStatus) SetRulesetStatus(ref, rulesetID, ruleID, message string, generation int64, now *metav1.Time) {
	s.Ref = ref
	s.RulesetID = rulesetID
	s.RuleID = ruleID
	s.Message = message
	s.ObservedGeneration = generation
	s.LastReconciledAt = now
}

// DeepCopyInto copies the receiver into out.
func (in *CloudflareRateLimitSpec) DeepCopyInto(out *CloudflareRateLimitSpec) {
	*out = *in
	in.RateLimit.DeepCopyInto(&out.RateLimit)
	if in.Enabled != nil {
		v := *in.Enabled
		out.Enabled = &v
	}
}

// DeepCopy creates a new CloudflareRateLimitSpec.
func (in *CloudflareRateLimitSpec) DeepCopy() *CloudflareRateLimitSpec {
	if in == nil {
		return nil
	}
	out := new(CloudflareRateLimitSpec)
	in.DeepCopyInto(out)
	return out
}

// DeepCopyInto copies the receiver into out.
func (in *CloudflareRateLimitParameters) DeepCopyInto(out *CloudflareRateLimitParameters) {
	*out = *in
	if in.Characteristics != nil {
		out.Characteristics = make([]string, len(in.Characteristics))
		copy(out.Characteristics, in.Characteristics)
	}
}

// DeepCopy creates a new CloudflareRateLimitParameters.
func (in *CloudflareRateLimitParameters) DeepCopy() *CloudflareRateLimitParameters {
	if in == nil {
		return nil
	}
	out := new(CloudflareRateLimitParameters)
	in.DeepCopyInto(out)
	return out
}

// DeepCopyInto copies the receiver into out.
func (in *CloudflareRateLimitStatus) DeepCopyInto(out *CloudflareRateLimitStatus) {
	*out = *in
	if in.LastReconciledAt != nil {
		out.LastReconciledAt = (*in.LastReconciledAt).DeepCopy()
	}
}

// DeepCopy creates a new CloudflareRateLimitStatus.
func (in *CloudflareRateLimitStatus) DeepCopy() *CloudflareRateLimitStatus {
	if in == nil {
		return nil
	}
	out := new(CloudflareRateLimitStatus)
	in.DeepCopyInto(out)
	return out
}

// DeepCopyInto copies the receiver into out.
func (in *CloudflareRateLimit) DeepCopyInto(out *CloudflareRateLimit) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ObjectMeta.DeepCopyInto(&out.ObjectMeta)
	in.Spec.DeepCopyInto(&out.Spec)
	in.Status.DeepCopyInto(&out.Status)
}

// DeepCopy creates a new CloudflareRateLimit.
func (in *CloudflareRateLimit) DeepCopy() *CloudflareRateLimit {
	if in == nil {
		return nil
	}
	out := new(CloudflareRateLimit)
	in.DeepCopyInto(out)
	return out
}

// DeepCopyObject returns a runtime.Object copy of the receiver.
func (in *CloudflareRateLimit) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

// DeepCopyInto copies the receiver into out.
func (in *CloudflareRateLimitList) DeepCopyInto(out *CloudflareRateLimitList) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ListMeta.DeepCopyInto(&out.ListMeta)
	if in.Items != nil {
		out.Items = make([]CloudflareRateLimit, len(in.Items))
		for i := range in.Items {
			in.Items[i].DeepCopyInto(&out.Items[i])
		}
	}
}

// DeepCopy creates a new CloudflareRateLimitList.
func (in *CloudflareRateLimitList) DeepCopy() *CloudflareRateLimitList {
	if in == nil {
		return nil
	}
	out := new(CloudflareRateLimitList)
	in.DeepCopyInto(out)
	return out
}

// DeepCopyObject returns a runtime.Object copy of the receiver.
func (in *CloudflareRateLimitList) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}
