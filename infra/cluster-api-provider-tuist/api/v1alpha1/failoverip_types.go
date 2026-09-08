package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// FailoverIPSpec keeps a provider failover/additional IP routed to a healthy box
// of a Kura bare-metal pool, so the region's host-network public peer plane
// survives a box loss (and a demux roll) without a cloud LoadBalancer.
type FailoverIPSpec struct {
	// IP is the failover/additional IP (or CIDR) kept routed to a healthy box.
	IP string `json:"ip"`

	// Vendor is the provider whose API moves the IP.
	// +kubebuilder:validation:Enum=ovh;dedibox
	Vendor string `json:"vendor"`

	// Region is the Kura region this IP fronts (informational; matches the pool
	// and the peer demux).
	Region string `json:"region,omitempty"`

	// NodePoolSelector selects the candidate boxes the IP may route to (the pool
	// label).
	NodePoolSelector map[string]string `json:"nodePoolSelector"`

	// DemuxSelector selects the peer-demux pods whose readiness additionally
	// gates a box's eligibility, so the IP drains off a box whose demux is
	// rolling. When empty, node Readiness alone gates eligibility.
	DemuxSelector map[string]string `json:"demuxSelector,omitempty"`

	// DemuxNamespace is the namespace the demux pods run in (default "kura").
	DemuxNamespace string `json:"demuxNamespace,omitempty"`
}

// FailoverIPStatus reports where the IP is currently routed.
type FailoverIPStatus struct {
	// ActiveNode is the node the IP is currently routed to.
	ActiveNode string `json:"activeNode,omitempty"`
	// Target is the vendor-opaque destination (OVH service name, or Dedibox
	// "zone/server-id") the IP routes to.
	Target string `json:"target,omitempty"`
	// Message surfaces the last reconcile outcome (e.g. "no eligible box").
	Message string `json:"message,omitempty"`

	LastReconciledAt *metav1.Time `json:"lastReconciledAt,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster

// FailoverIP is the placement of one provider failover IP onto a healthy box of
// a Kura bare-metal pool.
type FailoverIP struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   FailoverIPSpec   `json:"spec,omitempty"`
	Status FailoverIPStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// FailoverIPList is a list of FailoverIP.
type FailoverIPList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []FailoverIP `json:"items"`
}

func init() {
	SchemeBuilder.Register(&FailoverIP{}, &FailoverIPList{})
}
