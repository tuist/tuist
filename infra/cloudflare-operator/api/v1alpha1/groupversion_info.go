// Package v1alpha1 contains the Cloudflare operator's API types.
//
// Group: cloudflare.tuist.dev
// Version: v1alpha1
//
// The operator reconciles CRDs in this group against the Cloudflare API,
// declaratively managing zone-level configuration (rate limiting rules,
// cache rules, WAF custom rules, AI Crawl Control settings, and zone
// settings) so that git is the source of truth and no separate Terraform
// state backend is required.
//
// +kubebuilder:object:generate=true
// +groupName=cloudflare.tuist.dev
package v1alpha1

import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

var (
	GroupVersion = schema.GroupVersion{Group: "cloudflare.tuist.dev", Version: "v1alpha1"}

	SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}

	AddToScheme = SchemeBuilder.AddToScheme
)
