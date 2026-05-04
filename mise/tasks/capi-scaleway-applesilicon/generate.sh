#!/usr/bin/env bash
#MISE description="Regenerate CAPI provider DeepCopy + CRDs from API types"

# Single source of truth for the CAPI provider's CRDs is the
# annotated Go types in
# infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1/.
# This task runs controller-gen to regenerate
#   - api/v1alpha1/zz_generated.deepcopy.go
#   - infra/helm/tuist/crds/scalewayapplesilicon*.yaml
# from those types' `+kubebuilder:` markers.
#
# Run it whenever you touch a *_types.go file. Generated artefacts
# are committed; CI re-runs the same task to detect drift.
#
# controller-gen is invoked via `go run @<version>`: no install
# step, version pinned by string. Go's module cache makes the
# second-and-later runs fast.

set -euo pipefail

CONTROLLER_GEN_VERSION="v0.16.5"
PROVIDER_DIR="infra/cluster-api-provider-scaleway-applesilicon"
CRD_OUT_DIR="infra/helm/tuist/crds"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

echo "→ Generating DeepCopy methods (${PROVIDER_DIR}/api/v1alpha1/zz_generated.deepcopy.go)"
(
  cd "${PROVIDER_DIR}"
  go run "sigs.k8s.io/controller-tools/cmd/controller-gen@${CONTROLLER_GEN_VERSION}" \
    object paths=./api/...
)

echo "→ Generating CRD manifests (${CRD_OUT_DIR}/)"
(
  cd "${PROVIDER_DIR}"
  go run "sigs.k8s.io/controller-tools/cmd/controller-gen@${CONTROLLER_GEN_VERSION}" \
    crd paths=./api/... output:crd:dir="${REPO_ROOT}/${CRD_OUT_DIR}"
)

# CAPI core looks up infrastructure-provider CRDs by the
# `cluster.x-k8s.io/v1beta1=<api-version>` label. controller-gen
# doesn't emit that on its own; patch it in here so CAPI core
# discovers our CRDs.
echo "→ Adding CAPI provider label to generated CRDs"
for f in "${REPO_ROOT}/${CRD_OUT_DIR}"/infrastructure.cluster.x-k8s.io_scalewayapplesilicon*.yaml; do
  yq -i '.metadata.labels."cluster.x-k8s.io/v1beta1" = "v1alpha1"' "$f"
done

echo "✓ Done"
