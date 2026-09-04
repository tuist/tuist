package v1alpha1

import (
	"encoding/json"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// CloudflareZoneSettingSpec sets one of a zone's tunable settings
// (e.g. `challenge_ttl`, `ssl`, `security_level`, `always_use_https`)
// to a specific value. The value is passed as raw JSON so a single CRD
// covers every setting whose shape varies between plans and product
// updates.
type CloudflareZoneSettingSpec struct {
	// ZoneID is the Cloudflare zone the setting applies to.
	ZoneID string `json:"zoneId"`

	// SettingID is Cloudflare's identifier for the setting (see
	// https://developers.cloudflare.com/api/operations/zone-settings-get-all-zone-settings
	// for the full list). Examples: "challenge_ttl", "ssl",
	// "always_use_https", "browser_check", "security_level".
	SettingID string `json:"settingId"`

	// Value is the raw JSON the setting takes. For numeric settings
	// (challenge_ttl -> seconds), pass `1800`. For enumerated ones
	// (ssl -> "flexible" | "full" | "strict"), pass a quoted string.
	// For object-shaped ones (min_tls_version), see the API docs.
	//
	// +kubebuilder:validation:Schemaless
	// +kubebuilder:pruning:PreserveUnknownFields
	Value RawJSON `json:"value"`
}

// RawJSON accepts arbitrary JSON so a Value or Config field can carry
// anything Cloudflare accepts without the CRD schema needing to know.
// Marshal/Unmarshal are wired to pass the payload through verbatim.
type RawJSON struct {
	Raw []byte `json:"-"`
}

// NewRawJSON builds a RawJSON from a byte slice, copying it so the
// caller can reuse or free the original independently.
func NewRawJSON(b []byte) RawJSON {
	if len(b) == 0 {
		return RawJSON{}
	}
	return RawJSON{Raw: append([]byte(nil), b...)}
}

// UnmarshalJSON captures the whole payload.
func (a *RawJSON) UnmarshalJSON(b []byte) error {
	a.Raw = append(a.Raw[:0], b...)
	return nil
}

// MarshalJSON returns the captured payload; empty means "null".
func (a RawJSON) MarshalJSON() ([]byte, error) {
	if len(a.Raw) == 0 {
		return []byte("null"), nil
	}
	return a.Raw, nil
}

// DeepCopyInto copies the JSON payload byte-for-byte.
func (in *RawJSON) DeepCopyInto(out *RawJSON) {
	if in.Raw != nil {
		out.Raw = append([]byte(nil), in.Raw...)
	}
}

// DeepCopy returns a copy of the payload.
func (in *RawJSON) DeepCopy() *RawJSON {
	if in == nil {
		return nil
	}
	o := new(RawJSON)
	in.DeepCopyInto(o)
	return o
}

// CloudflareZoneSettingStatus reports the last reconcile outcome.
type CloudflareZoneSettingStatus struct {
	// ObservedValue is the last value Cloudflare returned. Useful for
	// diagnosing "why is my zone still on the old value" without
	// leaving the cluster.
	ObservedValue RawJSON `json:"observedValue,omitempty"`

	ObservedGeneration int64        `json:"observedGeneration,omitempty"`
	Message            string       `json:"message,omitempty"`
	LastReconciledAt   *metav1.Time `json:"lastReconciledAt,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=cfzs
// +kubebuilder:printcolumn:name="Zone",type="string",JSONPath=".spec.zoneId"
// +kubebuilder:printcolumn:name="Setting",type="string",JSONPath=".spec.settingId"
// +kubebuilder:printcolumn:name="Message",type="string",JSONPath=".status.message"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// CloudflareZoneSetting pins one zone-level setting to a value.
type CloudflareZoneSetting struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   CloudflareZoneSettingSpec   `json:"spec,omitempty"`
	Status CloudflareZoneSettingStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// CloudflareZoneSettingList is a list of CloudflareZoneSetting.
type CloudflareZoneSettingList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []CloudflareZoneSetting `json:"items"`
}

func init() {
	SchemeBuilder.Register(&CloudflareZoneSetting{}, &CloudflareZoneSettingList{})
}

// SetSettingsStatus implements controllers.SettingsStatusWriter.
func (s *CloudflareZoneSettingStatus) SetSettingsStatus(observed json.RawMessage, message string, generation int64, now *metav1.Time) {
	s.ObservedValue = NewRawJSON(observed)
	s.Message = message
	s.ObservedGeneration = generation
	s.LastReconciledAt = now
}

func (in *CloudflareZoneSettingSpec) DeepCopyInto(out *CloudflareZoneSettingSpec) {
	*out = *in
	in.Value.DeepCopyInto(&out.Value)
}

func (in *CloudflareZoneSettingSpec) DeepCopy() *CloudflareZoneSettingSpec {
	if in == nil {
		return nil
	}
	o := new(CloudflareZoneSettingSpec)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareZoneSettingStatus) DeepCopyInto(out *CloudflareZoneSettingStatus) {
	*out = *in
	in.ObservedValue.DeepCopyInto(&out.ObservedValue)
	if in.LastReconciledAt != nil {
		out.LastReconciledAt = (*in.LastReconciledAt).DeepCopy()
	}
}

func (in *CloudflareZoneSettingStatus) DeepCopy() *CloudflareZoneSettingStatus {
	if in == nil {
		return nil
	}
	o := new(CloudflareZoneSettingStatus)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareZoneSetting) DeepCopyInto(out *CloudflareZoneSetting) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ObjectMeta.DeepCopyInto(&out.ObjectMeta)
	in.Spec.DeepCopyInto(&out.Spec)
	in.Status.DeepCopyInto(&out.Status)
}

func (in *CloudflareZoneSetting) DeepCopy() *CloudflareZoneSetting {
	if in == nil {
		return nil
	}
	o := new(CloudflareZoneSetting)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareZoneSetting) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

func (in *CloudflareZoneSettingList) DeepCopyInto(out *CloudflareZoneSettingList) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ListMeta.DeepCopyInto(&out.ListMeta)
	if in.Items != nil {
		out.Items = make([]CloudflareZoneSetting, len(in.Items))
		for i := range in.Items {
			in.Items[i].DeepCopyInto(&out.Items[i])
		}
	}
}

func (in *CloudflareZoneSettingList) DeepCopy() *CloudflareZoneSettingList {
	if in == nil {
		return nil
	}
	o := new(CloudflareZoneSettingList)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareZoneSettingList) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}
