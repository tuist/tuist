package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
)

type KuraGatewaySpec struct {
	Region                  string            `json:"region"`
	IngressClassName        string            `json:"ingressClassName"`
	ControllerClassName     string            `json:"controllerClassName,omitempty"`
	ControllerImage         string            `json:"controllerImage,omitempty"`
	Replicas                *int32            `json:"replicas,omitempty"`
	NodeSelector            map[string]string `json:"nodeSelector,omitempty"`
	LoadBalancerAnnotations map[string]string `json:"loadBalancerAnnotations,omitempty"`
}

type KuraGatewayStatus struct {
	Phase            string       `json:"phase,omitempty"`
	IngressClassName string       `json:"ingressClassName,omitempty"`
	ServiceName      string       `json:"serviceName,omitempty"`
	ReadyReplicas    int32        `json:"readyReplicas,omitempty"`
	LoadBalancer     string       `json:"loadBalancer,omitempty"`
	Message          string       `json:"message,omitempty"`
	LastReconciledAt *metav1.Time `json:"lastReconciledAt,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=kuragateways,scope=Namespaced,shortName=kuragw
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="IngressClass",type=string,JSONPath=".spec.ingressClassName"
// +kubebuilder:printcolumn:name="Ready",type=integer,JSONPath=".status.readyReplicas"
// +kubebuilder:printcolumn:name="LoadBalancer",type=string,JSONPath=".status.loadBalancer"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"
type KuraGateway struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   KuraGatewaySpec   `json:"spec,omitempty"`
	Status KuraGatewayStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type KuraGatewayList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []KuraGateway `json:"items"`
}

func init() {
	SchemeBuilder.Register(&KuraGateway{}, &KuraGatewayList{})
}

func (in *KuraGatewaySpec) PodNodeSelector() map[string]string {
	if len(in.NodeSelector) == 0 {
		return nil
	}
	selector := make(map[string]string, len(in.NodeSelector))
	for key, value := range in.NodeSelector {
		selector[key] = value
	}
	return selector
}

func (in *KuraGatewaySpec) ServiceAnnotations() map[string]string {
	annotations := map[string]string{}
	for key, value := range in.LoadBalancerAnnotations {
		annotations[key] = value
	}
	if _, ok := annotations["load-balancer.hetzner.cloud/node-selector"]; !ok && len(in.NodeSelector) > 0 {
		annotations["load-balancer.hetzner.cloud/node-selector"] = labels.SelectorFromSet(labels.Set(in.NodeSelector)).String()
	}
	return annotations
}

func (in *KuraGatewaySpec) Environment() []corev1.EnvVar {
	return []corev1.EnvVar{{
		Name: "POD_NAME",
		ValueFrom: &corev1.EnvVarSource{FieldRef: &corev1.ObjectFieldSelector{
			FieldPath: "metadata.name",
		}},
	}, {
		Name: "POD_NAMESPACE",
		ValueFrom: &corev1.EnvVarSource{FieldRef: &corev1.ObjectFieldSelector{
			FieldPath: "metadata.namespace",
		}},
	}}
}
