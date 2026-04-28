// Package v1alpha1 contains the Scaleway Apple Silicon CAPI infrastructure
// provider's API types.
//
// Group: infrastructure.cluster.x-k8s.io
// Version: v1alpha1
//
// Standard CAPI infrastructure-provider contract: ScalewayAppleSiliconMachine
// represents a single Mac mini, ScalewayAppleSiliconMachineTemplate is the
// template MachineDeployments + MachineSets clone from, and
// ScalewayAppleSiliconCluster is the (mostly stub) cluster-level resource
// CAPI core requires to exist for the Cluster object to validate.
package v1alpha1

import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

var (
	GroupVersion = schema.GroupVersion{Group: "infrastructure.cluster.x-k8s.io", Version: "v1alpha1"}

	SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}

	AddToScheme = SchemeBuilder.AddToScheme
)
