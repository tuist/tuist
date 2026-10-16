// Package v1alpha1 contains the RackSwitch CRD.
//
// A RackSwitch is one of a rack's switches as an object. Its spec is rendered
// from infra/rack-switch-fleet/sites/<site>.json by `mise run rack:fleet
// render`, so it follows git. A switch with managedBy: controller is adopted
// and converged by this module through the Omada controller's Open API; a
// standalone one is changed over SSH by `rack:fleet` and only its status
// message is written here.
//
// The CRD manifest in infra/helm/tuist/crds/ is generated from these types by
// `mise run rack-switch-controller:generate`.
//
// +kubebuilder:object:generate=true
// +groupName=tuist.dev
package v1alpha1

import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

var (
	GroupVersion  = schema.GroupVersion{Group: "tuist.dev", Version: "v1alpha1"}
	SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}
	AddToScheme   = SchemeBuilder.AddToScheme
)
