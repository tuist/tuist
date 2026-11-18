// Package conditions keeps the v1beta1 condition helpers this provider already
// uses. Cluster API 1.14 moved those helpers onto v1beta2 condition types and
// renamed the accessor methods; the stored condition schema is unchanged.
package conditions

import (
	"sigs.k8s.io/controller-runtime/pkg/client"

	clusterv1 "sigs.k8s.io/cluster-api/api/core/v1beta1"
	v1beta2 "sigs.k8s.io/cluster-api/api/core/v1beta2"
	deprecated "sigs.k8s.io/cluster-api/util/conditions/deprecated/v1beta1"
)

// Getter is the v1beta1 condition read surface implemented by this provider's
// objects and by Cluster API's v1beta1 types.
type Getter interface {
	client.Object
	GetConditions() clusterv1.Conditions
}

// Setter is the v1beta1 condition surface implemented by this provider's
// objects and by Cluster API's v1beta1 types.
type Setter interface {
	Getter
	SetConditions(clusterv1.Conditions)
}

type readAdapter struct{ Getter }

func (a readAdapter) GetV1Beta1Conditions() v1beta2.Conditions {
	return toV2(a.GetConditions())
}

type adapter struct{ Setter }

func (a adapter) GetV1Beta1Conditions() v1beta2.Conditions {
	return toV2(a.GetConditions())
}

func (a adapter) SetV1Beta1Conditions(in v1beta2.Conditions) {
	a.SetConditions(toV1(in))
}

func wrap(to Setter) deprecated.Setter {
	if to == nil {
		return nil
	}
	return adapter{to}
}

func MarkTrue(to Setter, t clusterv1.ConditionType) {
	deprecated.MarkTrue(wrap(to), v1beta2.ConditionType(t))
}

func MarkFalse(to Setter, t clusterv1.ConditionType, reason string, severity clusterv1.ConditionSeverity, messageFormat string, messageArgs ...interface{}) {
	deprecated.MarkFalse(wrap(to), v1beta2.ConditionType(t), reason, v1beta2.ConditionSeverity(severity), messageFormat, messageArgs...)
}

func MarkUnknown(to Setter, t clusterv1.ConditionType, reason, messageFormat string, messageArgs ...interface{}) {
	deprecated.MarkUnknown(wrap(to), v1beta2.ConditionType(t), reason, messageFormat, messageArgs...)
}

func Set(to Setter, condition *clusterv1.Condition) {
	if condition == nil {
		deprecated.Set(wrap(to), nil)
		return
	}
	converted := toV2Cond(*condition)
	deprecated.Set(wrap(to), &converted)
}

func Delete(to Setter, t clusterv1.ConditionType) {
	deprecated.Delete(wrap(to), v1beta2.ConditionType(t))
}

func Get(from Getter, t clusterv1.ConditionType) *clusterv1.Condition {
	got := deprecated.Get(readAdapter{from}, v1beta2.ConditionType(t))
	if got == nil {
		return nil
	}
	converted := toV1Cond(*got)
	return &converted
}

func Has(from Getter, t clusterv1.ConditionType) bool {
	return deprecated.Has(readAdapter{from}, v1beta2.ConditionType(t))
}

func IsTrue(from Getter, t clusterv1.ConditionType) bool {
	return deprecated.IsTrue(readAdapter{from}, v1beta2.ConditionType(t))
}

func IsFalse(from Getter, t clusterv1.ConditionType) bool {
	return deprecated.IsFalse(readAdapter{from}, v1beta2.ConditionType(t))
}

func GetReason(from Getter, t clusterv1.ConditionType) string {
	return deprecated.GetReason(readAdapter{from}, v1beta2.ConditionType(t))
}

func GetMessage(from Getter, t clusterv1.ConditionType) string {
	return deprecated.GetMessage(readAdapter{from}, v1beta2.ConditionType(t))
}

func toV2(in clusterv1.Conditions) v1beta2.Conditions {
	if in == nil {
		return nil
	}
	out := make(v1beta2.Conditions, len(in))
	for i, condition := range in {
		out[i] = toV2Cond(condition)
	}
	return out
}

func toV1(in v1beta2.Conditions) clusterv1.Conditions {
	if in == nil {
		return nil
	}
	out := make(clusterv1.Conditions, len(in))
	for i, condition := range in {
		out[i] = toV1Cond(condition)
	}
	return out
}

func toV2Cond(condition clusterv1.Condition) v1beta2.Condition {
	return v1beta2.Condition{
		Type:               v1beta2.ConditionType(condition.Type),
		Status:             condition.Status,
		Severity:           v1beta2.ConditionSeverity(condition.Severity),
		LastTransitionTime: condition.LastTransitionTime,
		Reason:             condition.Reason,
		Message:            condition.Message,
	}
}

func toV1Cond(condition v1beta2.Condition) clusterv1.Condition {
	return clusterv1.Condition{
		Type:               clusterv1.ConditionType(condition.Type),
		Status:             condition.Status,
		Severity:           clusterv1.ConditionSeverity(condition.Severity),
		LastTransitionTime: condition.LastTransitionTime,
		Reason:             condition.Reason,
		Message:            condition.Message,
	}
}
