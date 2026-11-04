package v1alpha1

import (
	clusterv1 "sigs.k8s.io/cluster-api/api/core/v1beta1"
	v1beta2 "sigs.k8s.io/cluster-api/api/core/v1beta2"
)

// Cluster API 1.14's patch helper merges conditions only for objects that
// implement the deprecated v1beta1 getter with v1beta2 condition types.
// These methods keep the stored v1beta1 conditions and satisfy that contract.

func (m *OVHDedicatedMachine) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(m.GetConditions())
}
func (m *OVHDedicatedMachine) SetV1Beta1Conditions(c v1beta2.Conditions) {
	m.SetConditions(conditionsToV1(c))
}

func (m *RackAppleSiliconMachine) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(m.GetConditions())
}
func (m *RackAppleSiliconMachine) SetV1Beta1Conditions(c v1beta2.Conditions) {
	m.SetConditions(conditionsToV1(c))
}

func (a *RackATS) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(a.GetConditions())
}
func (a *RackATS) SetV1Beta1Conditions(c v1beta2.Conditions) {
	a.SetConditions(conditionsToV1(c))
}

func (l *RackHostLease) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(l.GetConditions())
}
func (l *RackHostLease) SetV1Beta1Conditions(c v1beta2.Conditions) {
	l.SetConditions(conditionsToV1(c))
}

func (p *RackPDU) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(p.GetConditions())
}
func (p *RackPDU) SetV1Beta1Conditions(c v1beta2.Conditions) {
	p.SetConditions(conditionsToV1(c))
}

func (m *ScalewayElasticMetalMachine) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(m.GetConditions())
}
func (m *ScalewayElasticMetalMachine) SetV1Beta1Conditions(c v1beta2.Conditions) {
	m.SetConditions(conditionsToV1(c))
}

func (c *TuistCluster) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(c.GetConditions())
}
func (c *TuistCluster) SetV1Beta1Conditions(in v1beta2.Conditions) {
	c.SetConditions(conditionsToV1(in))
}

func (m *VultrMachine) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(m.GetConditions())
}
func (m *VultrMachine) SetV1Beta1Conditions(c v1beta2.Conditions) {
	m.SetConditions(conditionsToV1(c))
}

func (h *RackHost) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(h.GetConditions())
}
func (h *RackHost) SetV1Beta1Conditions(c v1beta2.Conditions) {
	h.SetConditions(conditionsToV1(c))
}

func (h *RackLinuxHost) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(h.GetConditions())
}
func (h *RackLinuxHost) SetV1Beta1Conditions(c v1beta2.Conditions) {
	h.SetConditions(conditionsToV1(c))
}

func (m *RackLinuxMachine) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(m.GetConditions())
}
func (m *RackLinuxMachine) SetV1Beta1Conditions(c v1beta2.Conditions) {
	m.SetConditions(conditionsToV1(c))
}

func (s *RackSite) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(s.GetConditions())
}
func (s *RackSite) SetV1Beta1Conditions(c v1beta2.Conditions) {
	s.SetConditions(conditionsToV1(c))
}

func (m *ScalewayAppleSiliconMachine) GetV1Beta1Conditions() v1beta2.Conditions {
	return conditionsToV2(m.GetConditions())
}
func (m *ScalewayAppleSiliconMachine) SetV1Beta1Conditions(c v1beta2.Conditions) {
	m.SetConditions(conditionsToV1(c))
}

func conditionsToV2(in clusterv1.Conditions) v1beta2.Conditions {
	if in == nil {
		return nil
	}
	out := make(v1beta2.Conditions, len(in))
	for i, condition := range in {
		out[i] = v1beta2.Condition{
			Type:               v1beta2.ConditionType(condition.Type),
			Status:             condition.Status,
			Severity:           v1beta2.ConditionSeverity(condition.Severity),
			LastTransitionTime: condition.LastTransitionTime,
			Reason:             condition.Reason,
			Message:            condition.Message,
		}
	}
	return out
}

func conditionsToV1(in v1beta2.Conditions) clusterv1.Conditions {
	if in == nil {
		return nil
	}
	out := make(clusterv1.Conditions, len(in))
	for i, condition := range in {
		out[i] = clusterv1.Condition{
			Type:               clusterv1.ConditionType(condition.Type),
			Status:             condition.Status,
			Severity:           clusterv1.ConditionSeverity(condition.Severity),
			LastTransitionTime: condition.LastTransitionTime,
			Reason:             condition.Reason,
			Message:            condition.Message,
		}
	}
	return out
}
