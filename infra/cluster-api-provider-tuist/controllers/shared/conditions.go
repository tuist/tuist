// Package shared holds the cross-cutting pieces both the macos and linux
// machine reconcilers depend on, plus the externally-managed-control-plane
// TuistCluster stub every kind's MachineDeployment attaches to.
package shared

import clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"

// ProvisionedCondition is set by every machine kind's reconciler (macOS and
// Linux) once the underlying host is provisioned. It lives here because both
// the macos and linux subpackages mark it; the kind-specific conditions
// (Bootstrapped on macOS, NodeReady on Linux) stay in their own packages.
const ProvisionedCondition clusterv1.ConditionType = "Provisioned"
