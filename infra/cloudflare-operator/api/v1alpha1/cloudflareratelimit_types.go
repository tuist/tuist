package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// ReconcileMode gates whether the operator makes Cloudflare writes.
// Default is ReadOnly so a first deployment against a live zone can
// prove out the reconcile plan without changing anything.
// +kubebuilder:validation:Enum=read_only;active
type ReconcileMode string

const (
	ReconcileModeReadOnly ReconcileMode = "read_only"
	ReconcileModeActive   ReconcileMode = "active"
)

// AdoptRule binds a CR to an existing Cloudflare rule by its
// Cloudflare-assigned id. When set, the reconciler finds that rule
// specifically (not by ref) and treats it as the baseline: fields the
// CR does not set are left untouched on Cloudflare, so a first-run
// adoption of a dashboard-created rule proposes zero changes. When
// omitted, the operator manages a fresh rule keyed by its own ref
// and will refuse to touch a rule with a different id even if the
// expression matches — new rules require this field to be null and
// spec.createNewRule to be true, so accidental writes cannot happen.
type AdoptRule struct {
	// RuleID is the Cloudflare rule id (as returned by the API) the
	// operator will manage. Set once at adoption; changing it later
	// is treated as an adoption of a different rule.
	RuleID string `json:"ruleId"`
}

// CloudflareRateLimitSpec describes one entry of the zone's
// `http_ratelimit` ruleset. Fields map directly onto Cloudflare's
// Advanced Rate Limiting rule shape so an operator reading this
// struct can render a Ruleset rule without translation.
//
// +kubebuilder:validation:XValidation:rule="self.zoneId == oldSelf.zoneId",message="zoneId is immutable"
// +kubebuilder:validation:XValidation:rule="'cf.colo.id' in self.ratelimit.characteristics",message="ratelimit.characteristics must include 'cf.colo.id' — Cloudflare's Advanced Rate Limiting API requires it for correct per-datacenter counting"
type CloudflareRateLimitSpec struct {
	// ZoneID is the Cloudflare zone the rule applies to. Immutable
	// once the CR is created; move a rule between zones by creating
	// a new CR and deleting the old one.
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="zoneId is immutable"
	ZoneID string `json:"zoneId"`

	// Description is the human-readable label shown in the Cloudflare
	// dashboard. Kept in sync on every reconcile.
	Description string `json:"description"`

	// Expression is the request-match expression in Cloudflare's
	// wireshark syntax (e.g. `http.request.method eq "GET"`).
	// Requests that match are counted for rate limiting.
	Expression string `json:"expression"`

	// Action is what Cloudflare does when the threshold trips.
	// +kubebuilder:validation:Enum=block;managed_challenge;js_challenge;log
	Action string `json:"action"`

	// RateLimit holds the counting and mitigation parameters.
	RateLimit CloudflareRateLimitParameters `json:"ratelimit"`

	// Mode controls whether the reconciler writes to Cloudflare. In
	// read_only (default), the operator computes the intended diff,
	// logs it, and updates the CR status, but issues no API writes —
	// including no ruleset creation and no rule deletion on finalizer
	// cleanup. Flip to active once a zero-change reconcile has been
	// observed against the live zone.
	// +kubebuilder:default=read_only
	Mode ReconcileMode `json:"mode,omitempty"`

	// Paused, when true, halts the reconcile loop entirely. Neither
	// diffs nor writes happen; the CR keeps its last status. Use for
	// break-glass on a suspected bad reconcile, or during a
	// coordinated Cloudflare maintenance where the operator must not
	// re-issue calls.
	// +kubebuilder:default=false
	Paused bool `json:"paused,omitempty"`

	// Enabled controls whether the rule is active in Cloudflare (i.e.
	// evaluated by the edge). Distinct from Paused, which halts the
	// operator; disabled sends the rule with enabled:false so the
	// definition stays in place but does not fire. Defaults to true.
	// +kubebuilder:default=true
	Enabled *bool `json:"enabled,omitempty"`

	// Adopt binds this CR to an existing Cloudflare rule. Required
	// when adopting a dashboard-created rule; leave null with
	// CreateNewRule=true to have the operator create a fresh rule
	// under its own ref. Immutable once set.
	// +kubebuilder:validation:XValidation:rule="!has(oldSelf) || self == oldSelf",message="adopt is immutable once set"
	Adopt *AdoptRule `json:"adopt,omitempty"`

	// CreateNewRule must be true to permit the operator to POST a
	// brand-new rule (no adoption). Together with adopt=null this is
	// the only way to create; the double-negative guard prevents an
	// accidental `kubectl apply` from silently spawning duplicate
	// rules alongside dashboard-managed ones.
	// +kubebuilder:default=false
	CreateNewRule bool `json:"createNewRule,omitempty"`

	// RetainOnDelete, when true, leaves the Cloudflare rule in place
	// on CR deletion (the operator only drops its finalizer). Safer
	// default for adopted rules — a bad `kubectl delete` will not
	// silently remove a production rule. When false, CR deletion
	// propagates to a rule delete.
	// +kubebuilder:default=true
	RetainOnDelete bool `json:"retainOnDelete,omitempty"`
}

// CloudflareRateLimitParameters mirrors the Cloudflare rule's
// `ratelimit` object: how requests are counted and how long the
// mitigation lasts.
type CloudflareRateLimitParameters struct {
	// Characteristics keys the counter. Each entry is a Cloudflare
	// characteristic name. Cloudflare's Advanced Rate Limiting API
	// requires "cf.colo.id" to be present so counting is scoped per
	// edge datacenter; the CRD-level CEL validation enforces this.
	// Add "ip.src", "http.request.headers['x-...']", etc. as
	// additional keys as needed.
	Characteristics []string `json:"characteristics"`

	// RequestsPerPeriod is the threshold; when the counter for a
	// given key crosses this within Period, Action fires.
	// +kubebuilder:validation:Minimum=1
	RequestsPerPeriod int `json:"requestsPerPeriod"`

	// Period is the window in seconds over which requests are
	// counted. Cloudflare only accepts a fixed set of values.
	// +kubebuilder:validation:Enum=10;60;600;3600
	Period int `json:"period"`

	// MitigationTimeoutSeconds is how long Action stays applied
	// after the threshold trips. -1 means "until the counter falls
	// under the threshold".
	MitigationTimeoutSeconds int `json:"mitigationTimeoutSeconds"`

	// CountingExpression narrows what is counted (as opposed to what
	// matches). When set, only requests / responses matching this
	// expression tick the counter; empty means every match ticks.
	// Cloudflare infers the phase from the fields the expression
	// references — an expression that reads http.response.headers
	// counts in the response phase automatically.
	CountingExpression string `json:"countingExpression,omitempty"`
}

// Standard condition types this CRD sets on Status.Conditions. The
// `Ready` condition is what kstatus-based gating (Flux Kustomizations,
// `kubectl wait --for=condition=Ready`) reads: True only when a
// reconcile has actually applied the desired state — i.e. the CR is
// not paused, not sitting in read_only, and the last active pass
// succeeded.
const (
	ConditionTypeReady = "Ready"
	ConditionTypeMode  = "Mode"

	// Ready condition reasons.
	ReasonReconciled     = "Reconciled"
	ReasonReadOnly       = "ReadOnly"
	ReasonPaused         = "Paused"
	ReasonReconcileError = "ReconcileError"
)

// CloudflareRateLimitStatus reports the last reconcile outcome for
// operator visibility. Cloudflare is the source of truth; this is a
// summary, not authoritative.
type CloudflareRateLimitStatus struct {
	// Conditions carries the machine-readable state — chiefly the
	// Ready condition kstatus consumers watch. Read `status.message`
	// only for human-oriented context.
	// +optional
	// +patchMergeKey=type
	// +patchStrategy=merge
	Conditions []metav1.Condition `json:"conditions,omitempty" patchStrategy:"merge" patchMergeKey:"type"`

	// Ref is the stable identifier the operator sets on the
	// Cloudflare rule so it can find and update the same rule across
	// reconciles without a state backend. Empty when the CR adopts
	// an existing rule (adopt.ruleId identifies it instead).
	Ref string `json:"ref,omitempty"`

	// RuleID is the Cloudflare-assigned id of the rule.
	RuleID string `json:"ruleId,omitempty"`

	// RulesetID is the id of the zone's http_ratelimit ruleset that
	// owns the rule.
	RulesetID string `json:"rulesetId,omitempty"`

	// ManagedZoneID is the zone the operator has been managing this
	// rule against. Written on first successful reconcile. The
	// delete path uses this rather than spec.zoneId so a rule cannot
	// be orphaned by a zoneId mutation.
	ManagedZoneID string `json:"managedZoneId,omitempty"`

	// ObservedGeneration is the last spec generation the operator
	// has successfully reconciled.
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// Mode is the reconcile mode observed on the last pass. Useful
	// when the CR has just been flipped from read_only to active and
	// the operator user wants to confirm the switch took effect.
	Mode ReconcileMode `json:"mode,omitempty"`

	// ProposedChanges, when Mode is read_only, is a human-readable
	// summary of what the operator would do if flipped to active.
	// Empty when in sync or when Mode is active.
	ProposedChanges string `json:"proposedChanges,omitempty"`

	// Message surfaces the last reconcile outcome ("reconciled",
	// "no-op", or a short error summary).
	Message string `json:"message,omitempty"`

	LastReconciledAt *metav1.Time `json:"lastReconciledAt,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=cfrl
// +kubebuilder:printcolumn:name="Zone",type="string",JSONPath=".spec.zoneId"
// +kubebuilder:printcolumn:name="Mode",type="string",JSONPath=".spec.mode"
// +kubebuilder:printcolumn:name="Paused",type="boolean",JSONPath=".spec.paused"
// +kubebuilder:printcolumn:name="Action",type="string",JSONPath=".spec.action"
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

// IsEnabled defaults to true when Enabled is nil, matching the
// +kubebuilder default; a Go reader that constructs the type without
// going through the API server also gets the intended behaviour.
func (s *CloudflareRateLimitSpec) IsEnabled() bool {
	return s.Enabled == nil || *s.Enabled
}

// EffectiveMode returns the reconcile mode after applying the
// read-only default. Callers should use this instead of reading
// Spec.Mode directly so a nil/empty value never accidentally reads
// as active.
func (s *CloudflareRateLimitSpec) EffectiveMode() ReconcileMode {
	if s.Mode == ReconcileModeActive {
		return ReconcileModeActive
	}
	return ReconcileModeReadOnly
}

// DeepCopy machinery -------------------------------------------------

func (in *AdoptRule) DeepCopyInto(out *AdoptRule) { *out = *in }
func (in *AdoptRule) DeepCopy() *AdoptRule {
	if in == nil {
		return nil
	}
	o := new(AdoptRule)
	in.DeepCopyInto(o)
	return o
}

func (in *CloudflareRateLimitSpec) DeepCopyInto(out *CloudflareRateLimitSpec) {
	*out = *in
	in.RateLimit.DeepCopyInto(&out.RateLimit)
	if in.Enabled != nil {
		v := *in.Enabled
		out.Enabled = &v
	}
	if in.Adopt != nil {
		out.Adopt = in.Adopt.DeepCopy()
	}
}

func (in *CloudflareRateLimitSpec) DeepCopy() *CloudflareRateLimitSpec {
	if in == nil {
		return nil
	}
	out := new(CloudflareRateLimitSpec)
	in.DeepCopyInto(out)
	return out
}

func (in *CloudflareRateLimitParameters) DeepCopyInto(out *CloudflareRateLimitParameters) {
	*out = *in
	if in.Characteristics != nil {
		out.Characteristics = make([]string, len(in.Characteristics))
		copy(out.Characteristics, in.Characteristics)
	}
}

func (in *CloudflareRateLimitParameters) DeepCopy() *CloudflareRateLimitParameters {
	if in == nil {
		return nil
	}
	out := new(CloudflareRateLimitParameters)
	in.DeepCopyInto(out)
	return out
}

func (in *CloudflareRateLimitStatus) DeepCopyInto(out *CloudflareRateLimitStatus) {
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

func (in *CloudflareRateLimitStatus) DeepCopy() *CloudflareRateLimitStatus {
	if in == nil {
		return nil
	}
	out := new(CloudflareRateLimitStatus)
	in.DeepCopyInto(out)
	return out
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

func (in *CloudflareRateLimit) DeepCopyInto(out *CloudflareRateLimit) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ObjectMeta.DeepCopyInto(&out.ObjectMeta)
	in.Spec.DeepCopyInto(&out.Spec)
	in.Status.DeepCopyInto(&out.Status)
}

func (in *CloudflareRateLimit) DeepCopy() *CloudflareRateLimit {
	if in == nil {
		return nil
	}
	out := new(CloudflareRateLimit)
	in.DeepCopyInto(out)
	return out
}

func (in *CloudflareRateLimit) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

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

func (in *CloudflareRateLimitList) DeepCopy() *CloudflareRateLimitList {
	if in == nil {
		return nil
	}
	out := new(CloudflareRateLimitList)
	in.DeepCopyInto(out)
	return out
}

func (in *CloudflareRateLimitList) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}
