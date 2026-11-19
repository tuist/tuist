package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// CloudflareCacheRuleSpec describes one rule in a zone's
// http_request_cache_settings entry-point ruleset, a Cloudflare Cache
// Rule (action `set_cache_settings`). See
// https://developers.cloudflare.com/cache/how-to/cache-rules/settings/.
//
// +kubebuilder:validation:XValidation:rule="self.zoneId == oldSelf.zoneId",message="zoneId is immutable"
// +kubebuilder:validation:XValidation:rule="has(self.adopt) || self.createNewRule == true",message="either adopt.ruleId or createNewRule=true must be set"
type CloudflareCacheRuleSpec struct {
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="zoneId is immutable"
	ZoneID string `json:"zoneId"`

	Description string `json:"description"`
	Expression  string `json:"expression"`

	// Cache sets whether matched requests are eligible for cache.
	// Cloudflare caches only its default file extensions otherwise.
	Cache bool `json:"cache"`

	// EdgeTTL controls how long Cloudflare's edge keeps a response.
	EdgeTTL *CacheTTL `json:"edgeTtl,omitempty"`

	// BrowserTTL controls the Cache-Control Cloudflare sends browsers.
	BrowserTTL *CacheTTL `json:"browserTtl,omitempty"`

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

// CacheTTL is an edge or browser TTL setting. `respect_origin` follows
// the origin's Cache-Control; `override_origin` uses Default seconds;
// `bypass_by_default` (edge) and `bypass` (browser) disable caching
// when the origin sends no cache headers.
// +kubebuilder:validation:XValidation:rule="self.mode != 'override_origin' || has(self.default)",message="default is required when mode is override_origin"
type CacheTTL struct {
	// +kubebuilder:validation:Enum=respect_origin;override_origin;bypass_by_default;bypass
	Mode string `json:"mode"`

	// Default is the TTL in seconds for `override_origin`.
	Default *int64 `json:"default,omitempty"`
}

func (s *CloudflareCacheRuleSpec) IsEnabled() bool {
	return s.Enabled == nil || *s.Enabled
}

func (s *CloudflareCacheRuleSpec) EffectiveMode() ReconcileMode {
	if s.Mode == "" {
		return ReconcileModeReadOnly
	}
	return s.Mode
}

type CloudflareCacheRuleStatus = CloudflareCustomRuleStatus

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=cfcache
// +kubebuilder:printcolumn:name="Zone",type="string",JSONPath=".spec.zoneId"
// +kubebuilder:printcolumn:name="Mode",type="string",JSONPath=".spec.mode"
// +kubebuilder:printcolumn:name="Message",type="string",JSONPath=".status.message"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"
type CloudflareCacheRule struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   CloudflareCacheRuleSpec   `json:"spec,omitempty"`
	Status CloudflareCacheRuleStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type CloudflareCacheRuleList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []CloudflareCacheRule `json:"items"`
}

func init() {
	SchemeBuilder.Register(&CloudflareCacheRule{}, &CloudflareCacheRuleList{})
}

func (in *CacheTTL) DeepCopy() *CacheTTL {
	if in == nil {
		return nil
	}
	out := *in
	if in.Default != nil {
		v := *in.Default
		out.Default = &v
	}
	return &out
}

func (in *CloudflareCacheRuleSpec) DeepCopyInto(out *CloudflareCacheRuleSpec) {
	*out = *in
	if in.Enabled != nil {
		v := *in.Enabled
		out.Enabled = &v
	}
	if in.Adopt != nil {
		v := *in.Adopt
		out.Adopt = &v
	}
	out.EdgeTTL = in.EdgeTTL.DeepCopy()
	out.BrowserTTL = in.BrowserTTL.DeepCopy()
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
	out := new(CloudflareCacheRule)
	in.DeepCopyInto(out)
	return out
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
	out := new(CloudflareCacheRuleList)
	in.DeepCopyInto(out)
	return out
}

func (in *CloudflareCacheRuleList) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}
