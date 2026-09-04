package v1alpha1

import (
	"encoding/json"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// CloudflareAICrawlControlSpec captures the zone-level AI Crawl
// Control configuration. The product is newer than the Rulesets API
// and its wire format has iterated a few times, so the CRD keeps the
// payload as raw JSON that the operator PUTs verbatim. That way the
// operator doesn't gate on schema drift; when Cloudflare adds a new
// knob it becomes available immediately by editing the CR.
type CloudflareAICrawlControlSpec struct {
	// ZoneID is the Cloudflare zone the configuration applies to.
	ZoneID string `json:"zoneId"`

	// Config is the raw JSON body Cloudflare's AI Crawl Control
	// endpoint accepts. See the Cloudflare API docs for the current
	// shape; the operator does not interpret it.
	//
	// +kubebuilder:validation:Schemaless
	// +kubebuilder:pruning:PreserveUnknownFields
	Config RawJSON `json:"config"`
}

// CloudflareAICrawlControlStatus reports the last reconcile outcome.
type CloudflareAICrawlControlStatus struct {
	// ObservedConfig is the raw JSON Cloudflare returned. Useful for
	// diagnosing shape drift without a dashboard trip.
	ObservedConfig RawJSON `json:"observedConfig,omitempty"`

	ObservedGeneration int64        `json:"observedGeneration,omitempty"`
	Message            string       `json:"message,omitempty"`
	LastReconciledAt   *metav1.Time `json:"lastReconciledAt,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=cfaicc
// +kubebuilder:printcolumn:name="Zone",type="string",JSONPath=".spec.zoneId"
// +kubebuilder:printcolumn:name="Message",type="string",JSONPath=".status.message"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// CloudflareAICrawlControl is the zone-level AI Crawl Control config.
// One CR per zone; second CR for the same zone is a config split and
// the reconciler will treat whichever it sees last as authoritative.
type CloudflareAICrawlControl struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   CloudflareAICrawlControlSpec   `json:"spec,omitempty"`
	Status CloudflareAICrawlControlStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// CloudflareAICrawlControlList is a list of CloudflareAICrawlControl.
type CloudflareAICrawlControlList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []CloudflareAICrawlControl `json:"items"`
}

func init() {
	SchemeBuilder.Register(&CloudflareAICrawlControl{}, &CloudflareAICrawlControlList{})
}

// SetSettingsStatus implements controllers.SettingsStatusWriter.
func (s *CloudflareAICrawlControlStatus) SetSettingsStatus(observed json.RawMessage, message string, generation int64, now *metav1.Time) {
	s.ObservedConfig = NewRawJSON(observed)
	s.Message = message
	s.ObservedGeneration = generation
	s.LastReconciledAt = now
}

func (in *CloudflareAICrawlControlSpec) DeepCopyInto(out *CloudflareAICrawlControlSpec) {
	*out = *in
	in.Config.DeepCopyInto(&out.Config)
}

func (in *CloudflareAICrawlControlSpec) DeepCopy() *CloudflareAICrawlControlSpec {
	if in == nil {
		return nil
	}
	o := new(CloudflareAICrawlControlSpec)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareAICrawlControlStatus) DeepCopyInto(out *CloudflareAICrawlControlStatus) {
	*out = *in
	in.ObservedConfig.DeepCopyInto(&out.ObservedConfig)
	if in.LastReconciledAt != nil {
		out.LastReconciledAt = (*in.LastReconciledAt).DeepCopy()
	}
}

func (in *CloudflareAICrawlControlStatus) DeepCopy() *CloudflareAICrawlControlStatus {
	if in == nil {
		return nil
	}
	o := new(CloudflareAICrawlControlStatus)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareAICrawlControl) DeepCopyInto(out *CloudflareAICrawlControl) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ObjectMeta.DeepCopyInto(&out.ObjectMeta)
	in.Spec.DeepCopyInto(&out.Spec)
	in.Status.DeepCopyInto(&out.Status)
}

func (in *CloudflareAICrawlControl) DeepCopy() *CloudflareAICrawlControl {
	if in == nil {
		return nil
	}
	o := new(CloudflareAICrawlControl)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareAICrawlControl) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

func (in *CloudflareAICrawlControlList) DeepCopyInto(out *CloudflareAICrawlControlList) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ListMeta.DeepCopyInto(&out.ListMeta)
	if in.Items != nil {
		out.Items = make([]CloudflareAICrawlControl, len(in.Items))
		for i := range in.Items {
			in.Items[i].DeepCopyInto(&out.Items[i])
		}
	}
}

func (in *CloudflareAICrawlControlList) DeepCopy() *CloudflareAICrawlControlList {
	if in == nil {
		return nil
	}
	o := new(CloudflareAICrawlControlList)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareAICrawlControlList) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}
