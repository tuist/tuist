package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// SBFMAction is what Super Bot Fight Mode does to requests classified
// into a given bucket (definitely automated, likely automated, verified
// bots). Cloudflare accepts these three values on Business plans.
// +kubebuilder:validation:Enum=allow;block;managed_challenge
type SBFMAction string

const (
	SBFMActionAllow            SBFMAction = "allow"
	SBFMActionBlock            SBFMAction = "block"
	SBFMActionManagedChallenge SBFMAction = "managed_challenge"
)

// CloudflareBotManagementSpec describes the zone-scoped Bot Fight Mode
// and Super Bot Fight Mode configuration. Each CR is a singleton per
// zone (identity is spec.zoneId). Fields modeled as pointers so nil
// means "do not touch on Cloudflare" — only fields the CR explicitly
// sets are sent on the PATCH, and only those are compared for drift.
//
// AI Crawl Control lives on the same Cloudflare API endpoint but is
// deliberately not modeled here per infra/cloudflare-operator/AGENTS.md
// ("AI Crawl Control ... should remain a separate kind rather than
// overloading either ruleset shape"). Add a CloudflareAICrawlControl
// kind when we need to manage those fields.
//
// +kubebuilder:validation:XValidation:rule="self.zoneId == oldSelf.zoneId",message="zoneId is immutable"
type CloudflareBotManagementSpec struct {
	// ZoneID is the Cloudflare zone this configuration applies to.
	// Immutable once the CR is created; move a config between zones by
	// creating a new CR and deleting the old one.
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="zoneId is immutable"
	ZoneID string `json:"zoneId"`

	// Mode controls whether the reconciler writes to Cloudflare. In
	// read_only (default), the operator computes the intended diff,
	// mirrors it into status.proposedChanges, and issues no API writes.
	// Flip to active once a zero-change reconcile has been observed
	// against the live zone.
	// +kubebuilder:default=read_only
	Mode ReconcileMode `json:"mode,omitempty"`

	// Paused, when true, halts the reconcile loop entirely. Neither
	// diffs nor writes happen; the CR keeps its last status.
	// +kubebuilder:default=false
	Paused bool `json:"paused,omitempty"`

	// BotFightMode covers Cloudflare's Bot Fight Mode tier (the free
	// JS-challenge bot detection). Nil means the operator does not
	// manage any Bot Fight Mode field on this zone.
	BotFightMode *BotFightModeSpec `json:"botFightMode,omitempty"`

	// SuperBotFightMode covers Cloudflare's Super Bot Fight Mode tier
	// (Business plan and above): per-bucket actions plus static-asset
	// and WordPress optimizations. Nil means the operator does not
	// manage any Super Bot Fight Mode field on this zone.
	SuperBotFightMode *SuperBotFightModeSpec `json:"superBotFightMode,omitempty"`
}

// BotFightModeSpec models the JS-detection tier that Cloudflare enables
// via the zone's bot_management endpoint.
type BotFightModeSpec struct {
	// EnableJS toggles the JavaScript challenge Cloudflare embeds on
	// non-static paths to distinguish real browsers from headless
	// clients. Corresponds to the API field enable_js.
	EnableJS *bool `json:"enableJs,omitempty"`

	// SuppressSessionScore, when true, hides the ML session score
	// Cloudflare would otherwise attach to requests. Rarely toggled;
	// modeled so an adopted state round-trips cleanly.
	SuppressSessionScore *bool `json:"suppressSessionScore,omitempty"`

	// UsingLatestModel opts the zone into Cloudflare's latest bot
	// detection model. Reported by the API on read; can be set on
	// write to keep the zone on the current model.
	UsingLatestModel *bool `json:"usingLatestModel,omitempty"`
}

// SuperBotFightModeSpec models Super Bot Fight Mode (Business+).
type SuperBotFightModeSpec struct {
	// DefinitelyAutomated is the action for requests Cloudflare's
	// classifier calls definitely automated. Corresponds to the API
	// field sbfm_definitely_automated.
	DefinitelyAutomated SBFMAction `json:"definitelyAutomated,omitempty"`

	// LikelyAutomated is the action for requests Cloudflare's
	// classifier calls likely automated. Corresponds to
	// sbfm_likely_automated. Setting this to managed_challenge or
	// block has a higher false-positive risk than DefinitelyAutomated;
	// keep it on allow unless the false-positive rate is acceptable.
	LikelyAutomated SBFMAction `json:"likelyAutomated,omitempty"`

	// VerifiedBots is the action for Cloudflare-verified crawlers
	// (Googlebot, Bingbot, etc. that publish IP ranges and pass rDNS).
	// Corresponds to sbfm_verified_bots. Almost always allow.
	VerifiedBots SBFMAction `json:"verifiedBots,omitempty"`

	// StaticResourceProtection controls whether static-asset paths
	// (images, CSS, JS) are also subjected to the SBFM actions.
	// Corresponds to sbfm_static_resource_protection.
	StaticResourceProtection *bool `json:"staticResourceProtection,omitempty"`

	// OptimizeWordpress applies WordPress-specific bot-protection
	// tweaks. Corresponds to the API field optimize_wordpress.
	OptimizeWordpress *bool `json:"optimizeWordpress,omitempty"`
}

// CloudflareBotManagementStatus reports the last reconcile outcome.
type CloudflareBotManagementStatus struct {
	// Conditions carries the Ready condition kstatus consumers watch.
	// +optional
	// +patchMergeKey=type
	// +patchStrategy=merge
	Conditions []metav1.Condition `json:"conditions,omitempty" patchStrategy:"merge" patchMergeKey:"type"`

	// ManagedZoneID is the zone the operator has been reconciling
	// this configuration against. Written on first successful
	// reconcile; used by no code path today (there is no ref-based
	// delete), but kept for parity with the ruleset CRDs and to make
	// audit trails easier.
	ManagedZoneID string `json:"managedZoneId,omitempty"`

	// ObservedGeneration is the last spec generation the operator
	// has successfully reconciled.
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// Mode is the reconcile mode observed on the last pass.
	Mode ReconcileMode `json:"mode,omitempty"`

	// ProposedChanges, when Mode is read_only, is a human-readable
	// summary of what the operator would do if flipped to active.
	// Empty when in sync or when Mode is active.
	ProposedChanges string `json:"proposedChanges,omitempty"`

	// Message surfaces the last reconcile outcome.
	Message string `json:"message,omitempty"`

	LastReconciledAt *metav1.Time `json:"lastReconciledAt,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=cfbm
// +kubebuilder:printcolumn:name="Zone",type="string",JSONPath=".spec.zoneId"
// +kubebuilder:printcolumn:name="Mode",type="string",JSONPath=".spec.mode"
// +kubebuilder:printcolumn:name="Paused",type="boolean",JSONPath=".spec.paused"
// +kubebuilder:printcolumn:name="Message",type="string",JSONPath=".status.message"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// CloudflareBotManagement is the zone-scoped Bot Fight Mode and Super
// Bot Fight Mode configuration reconciled against
// /zones/{zoneId}/bot_management.
type CloudflareBotManagement struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   CloudflareBotManagementSpec   `json:"spec,omitempty"`
	Status CloudflareBotManagementStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// CloudflareBotManagementList is a list of CloudflareBotManagement.
type CloudflareBotManagementList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []CloudflareBotManagement `json:"items"`
}

func init() {
	SchemeBuilder.Register(&CloudflareBotManagement{}, &CloudflareBotManagementList{})
}

// EffectiveMode returns the reconcile mode after applying the
// read-only default.
func (s *CloudflareBotManagementSpec) EffectiveMode() ReconcileMode {
	if s.Mode == ReconcileModeActive {
		return ReconcileModeActive
	}
	return ReconcileModeReadOnly
}

// DeepCopy machinery -------------------------------------------------

func (in *BotFightModeSpec) DeepCopyInto(out *BotFightModeSpec) {
	*out = *in
	if in.EnableJS != nil {
		v := *in.EnableJS
		out.EnableJS = &v
	}
	if in.SuppressSessionScore != nil {
		v := *in.SuppressSessionScore
		out.SuppressSessionScore = &v
	}
	if in.UsingLatestModel != nil {
		v := *in.UsingLatestModel
		out.UsingLatestModel = &v
	}
}

func (in *BotFightModeSpec) DeepCopy() *BotFightModeSpec {
	if in == nil {
		return nil
	}
	o := new(BotFightModeSpec)
	in.DeepCopyInto(o)
	return o
}

func (in *SuperBotFightModeSpec) DeepCopyInto(out *SuperBotFightModeSpec) {
	*out = *in
	if in.StaticResourceProtection != nil {
		v := *in.StaticResourceProtection
		out.StaticResourceProtection = &v
	}
	if in.OptimizeWordpress != nil {
		v := *in.OptimizeWordpress
		out.OptimizeWordpress = &v
	}
}

func (in *SuperBotFightModeSpec) DeepCopy() *SuperBotFightModeSpec {
	if in == nil {
		return nil
	}
	o := new(SuperBotFightModeSpec)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareBotManagementSpec) DeepCopyInto(out *CloudflareBotManagementSpec) {
	*out = *in
	if in.BotFightMode != nil {
		out.BotFightMode = in.BotFightMode.DeepCopy()
	}
	if in.SuperBotFightMode != nil {
		out.SuperBotFightMode = in.SuperBotFightMode.DeepCopy()
	}
}

func (in *CloudflareBotManagementSpec) DeepCopy() *CloudflareBotManagementSpec {
	if in == nil {
		return nil
	}
	out := new(CloudflareBotManagementSpec)
	in.DeepCopyInto(out)
	return out
}

func (in *CloudflareBotManagementStatus) DeepCopyInto(out *CloudflareBotManagementStatus) {
	*out = *in
	if in.Conditions != nil {
		out.Conditions = make([]metav1.Condition, len(in.Conditions))
		for i := range in.Conditions {
			in.Conditions[i].DeepCopyInto(&out.Conditions[i])
		}
	}
	if in.LastReconciledAt != nil {
		out.LastReconciledAt = (*in.LastReconciledAt).DeepCopy()
	}
}

func (in *CloudflareBotManagementStatus) DeepCopy() *CloudflareBotManagementStatus {
	if in == nil {
		return nil
	}
	out := new(CloudflareBotManagementStatus)
	in.DeepCopyInto(out)
	return out
}

func (in *CloudflareBotManagement) DeepCopyInto(out *CloudflareBotManagement) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ObjectMeta.DeepCopyInto(&out.ObjectMeta)
	in.Spec.DeepCopyInto(&out.Spec)
	in.Status.DeepCopyInto(&out.Status)
}

func (in *CloudflareBotManagement) DeepCopy() *CloudflareBotManagement {
	if in == nil {
		return nil
	}
	out := new(CloudflareBotManagement)
	in.DeepCopyInto(out)
	return out
}

func (in *CloudflareBotManagement) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

func (in *CloudflareBotManagementList) DeepCopyInto(out *CloudflareBotManagementList) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ListMeta.DeepCopyInto(&out.ListMeta)
	if in.Items != nil {
		out.Items = make([]CloudflareBotManagement, len(in.Items))
		for i := range in.Items {
			in.Items[i].DeepCopyInto(&out.Items[i])
		}
	}
}

func (in *CloudflareBotManagementList) DeepCopy() *CloudflareBotManagementList {
	if in == nil {
		return nil
	}
	out := new(CloudflareBotManagementList)
	in.DeepCopyInto(out)
	return out
}

func (in *CloudflareBotManagementList) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}
