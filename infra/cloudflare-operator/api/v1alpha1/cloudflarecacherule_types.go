package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// CloudflareCacheRuleSpec describes one entry of the zone's
// `http_request_cache_settings` ruleset. Cloudflare's cache rule shape
// is richer than a rate limit (edge / browser TTL, cache key
// customisation, respect origin headers, etc.); the CRD models the
// most common fields explicitly and passes the rest through as raw
// JSON so the operator does not gate on every new Cloudflare option.
type CloudflareCacheRuleSpec struct {
	// ZoneID is the Cloudflare zone the rule applies to.
	ZoneID string `json:"zoneId"`

	// Description is the human-readable label shown in the dashboard.
	Description string `json:"description"`

	// Expression is the request match expression in Cloudflare's
	// wireshark syntax. Requests that match receive the cache
	// settings below.
	Expression string `json:"expression"`

	// CacheSettings is the parameter block Cloudflare stores under
	// `action_parameters`. The action itself is always
	// `set_cache_settings` for cache rules; the CRD does not surface
	// it because there is no other valid choice.
	CacheSettings CacheSettings `json:"cacheSettings"`

	// Enabled controls whether the rule is active. Defaults to true.
	// +kubebuilder:default=true
	Enabled *bool `json:"enabled,omitempty"`
}

// CacheSettings mirrors the `action_parameters` object Cloudflare
// accepts for cache rules. Every field is optional; only the ones set
// are sent, and Cloudflare treats missing fields as "leave as-is /
// origin decides."
type CacheSettings struct {
	// Cache toggles whether the response is eligible for edge cache
	// at all. Nil means "leave to Cloudflare's default"; false means
	// bypass cache; true means eligible.
	Cache *bool `json:"cache,omitempty"`

	// EdgeTTL is Cloudflare's edge cache TTL policy.
	EdgeTTL *EdgeTTL `json:"edgeTTL,omitempty"`

	// BrowserTTL is the Cache-Control max-age Cloudflare sends to the
	// browser.
	BrowserTTL *BrowserTTL `json:"browserTTL,omitempty"`

	// RespectStrongEtags asks Cloudflare to honor strong ETags on
	// revalidation.
	RespectStrongEtags *bool `json:"respectStrongEtags,omitempty"`

	// CacheDeceptionArmor blocks path-based cache-poisoning tricks.
	CacheDeceptionArmor *bool `json:"cacheDeceptionArmor,omitempty"`

	// OriginErrorPagePassthru passes 5xx origin errors through
	// instead of showing Cloudflare's error page.
	OriginErrorPagePassthru *bool `json:"originErrorPagePassthru,omitempty"`

	// AdditionalCacheablePorts allows caching for non-standard ports.
	AdditionalCacheablePorts []int `json:"additionalCacheablePorts,omitempty"`
}

// EdgeTTL is Cloudflare's edge cache TTL configuration. Mode picks
// between honoring origin `Cache-Control`, always overriding, or
// bypassing. Default is a pointer so a caller can express `0` (no
// edge cache) distinctly from "leave to Cloudflare's default".
type EdgeTTL struct {
	// +kubebuilder:validation:Enum=respect_origin;override_origin;bypass_by_default
	Mode    string `json:"mode"`
	Default *int   `json:"default,omitempty"`
}

// BrowserTTL is the browser-side cache TTL policy. Default is a
// pointer for the same reason as EdgeTTL.
type BrowserTTL struct {
	// +kubebuilder:validation:Enum=respect_origin;override_origin;bypass;bypass_by_default
	Mode    string `json:"mode"`
	Default *int   `json:"default,omitempty"`
}

// CloudflareCacheRuleStatus reports the last reconcile outcome for
// operator visibility.
type CloudflareCacheRuleStatus struct {
	Ref                string       `json:"ref,omitempty"`
	RuleID             string       `json:"ruleId,omitempty"`
	RulesetID          string       `json:"rulesetId,omitempty"`
	ObservedGeneration int64        `json:"observedGeneration,omitempty"`
	Message            string       `json:"message,omitempty"`
	LastReconciledAt   *metav1.Time `json:"lastReconciledAt,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=cfcr
// +kubebuilder:printcolumn:name="Zone",type="string",JSONPath=".spec.zoneId"
// +kubebuilder:printcolumn:name="Message",type="string",JSONPath=".status.message"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// CloudflareCacheRule is one rule in a zone's cache-settings ruleset.
type CloudflareCacheRule struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   CloudflareCacheRuleSpec   `json:"spec,omitempty"`
	Status CloudflareCacheRuleStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// CloudflareCacheRuleList is a list of CloudflareCacheRule.
type CloudflareCacheRuleList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []CloudflareCacheRule `json:"items"`
}

func init() {
	SchemeBuilder.Register(&CloudflareCacheRule{}, &CloudflareCacheRuleList{})
}

// IsEnabled matches CloudflareRateLimitSpec.IsEnabled.
func (s *CloudflareCacheRuleSpec) IsEnabled() bool {
	return s.Enabled == nil || *s.Enabled
}

// SetRulesetStatus implements controllers.RulesetStatusWriter.
func (s *CloudflareCacheRuleStatus) SetRulesetStatus(ref, rulesetID, ruleID, message string, generation int64, now *metav1.Time) {
	s.Ref = ref
	s.RulesetID = rulesetID
	s.RuleID = ruleID
	s.Message = message
	s.ObservedGeneration = generation
	s.LastReconciledAt = now
}

// DeepCopy machinery ---------------------------------------------------

func (in *EdgeTTL) DeepCopyInto(out *EdgeTTL) {
	*out = *in
	if in.Default != nil {
		v := *in.Default
		out.Default = &v
	}
}
func (in *EdgeTTL) DeepCopy() *EdgeTTL {
	if in == nil {
		return nil
	}
	o := new(EdgeTTL)
	in.DeepCopyInto(o)
	return o
}
func (in *BrowserTTL) DeepCopyInto(out *BrowserTTL) {
	*out = *in
	if in.Default != nil {
		v := *in.Default
		out.Default = &v
	}
}
func (in *BrowserTTL) DeepCopy() *BrowserTTL {
	if in == nil {
		return nil
	}
	o := new(BrowserTTL)
	in.DeepCopyInto(o)
	return o
}

func (in *CacheSettings) DeepCopyInto(out *CacheSettings) {
	*out = *in
	if in.Cache != nil {
		v := *in.Cache
		out.Cache = &v
	}
	if in.EdgeTTL != nil {
		out.EdgeTTL = in.EdgeTTL.DeepCopy()
	}
	if in.BrowserTTL != nil {
		out.BrowserTTL = in.BrowserTTL.DeepCopy()
	}
	if in.RespectStrongEtags != nil {
		v := *in.RespectStrongEtags
		out.RespectStrongEtags = &v
	}
	if in.CacheDeceptionArmor != nil {
		v := *in.CacheDeceptionArmor
		out.CacheDeceptionArmor = &v
	}
	if in.OriginErrorPagePassthru != nil {
		v := *in.OriginErrorPagePassthru
		out.OriginErrorPagePassthru = &v
	}
	if in.AdditionalCacheablePorts != nil {
		out.AdditionalCacheablePorts = append([]int(nil), in.AdditionalCacheablePorts...)
	}
}

func (in *CacheSettings) DeepCopy() *CacheSettings {
	if in == nil {
		return nil
	}
	o := new(CacheSettings)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareCacheRuleSpec) DeepCopyInto(out *CloudflareCacheRuleSpec) {
	*out = *in
	in.CacheSettings.DeepCopyInto(&out.CacheSettings)
	if in.Enabled != nil {
		v := *in.Enabled
		out.Enabled = &v
	}
}

func (in *CloudflareCacheRuleSpec) DeepCopy() *CloudflareCacheRuleSpec {
	if in == nil {
		return nil
	}
	o := new(CloudflareCacheRuleSpec)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareCacheRuleStatus) DeepCopyInto(out *CloudflareCacheRuleStatus) {
	*out = *in
	if in.LastReconciledAt != nil {
		out.LastReconciledAt = (*in.LastReconciledAt).DeepCopy()
	}
}

func (in *CloudflareCacheRuleStatus) DeepCopy() *CloudflareCacheRuleStatus {
	if in == nil {
		return nil
	}
	o := new(CloudflareCacheRuleStatus)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareCacheRule) DeepCopyInto(out *CloudflareCacheRule) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ObjectMeta.DeepCopyInto(&out.ObjectMeta)
	in.Spec.DeepCopyInto(&out.Spec)
	in.Status.DeepCopyInto(&out.Status)
}

func (in *CloudflareCacheRule) DeepCopy() *CloudflareCacheRule {
	if in == nil {
		return nil
	}
	o := new(CloudflareCacheRule)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareCacheRule) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

func (in *CloudflareCacheRuleList) DeepCopyInto(out *CloudflareCacheRuleList) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ListMeta.DeepCopyInto(&out.ListMeta)
	if in.Items != nil {
		out.Items = make([]CloudflareCacheRule, len(in.Items))
		for i := range in.Items {
			in.Items[i].DeepCopyInto(&out.Items[i])
		}
	}
}

func (in *CloudflareCacheRuleList) DeepCopy() *CloudflareCacheRuleList {
	if in == nil {
		return nil
	}
	o := new(CloudflareCacheRuleList)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareCacheRuleList) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}
