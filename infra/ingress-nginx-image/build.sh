#!/usr/bin/env bash
# Builds the ingress-nginx nginx base, controller and kube-webhook-certgen
# images from the fork pinned in fork.env, with our patches from patches/
# applied after the fork's. Builds into the local Docker image store only;
# publishing is the workflow's separate job.
#
#   build.sh WORK_DIR
#
# WORK_DIR receives the fork checkout, build logs, and images.env with the
# built image references. Needs Docker with buildx and network access.
# IMAGE_PREFIX (default ghcr.io/tuist/ingress-nginx) names the images
# <prefix>-nginx, <prefix>-controller and <prefix>-kube-webhook-certgen;
# TUIST_REVISION (default: this checkout's HEAD) is recorded in a label.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=fork.env
source "$here/fork.env"

work=${1:?usage: build.sh WORK_DIR}
mkdir -p "$work"
work=$(cd "$work" && pwd)
src="$work/src"
prefix=${IMAGE_PREFIX:-ghcr.io/tuist/ingress-nginx}
revision=${TUIST_REVISION:-$(git -C "$here" rev-parse HEAD)}
version=${FORK_TAG#controller-}
tag="${version}-tuist.${TUIST_BUILD}"

bash "$here/source.sh" "$work"

labels=(
  --label "org.opencontainers.image.source=https://github.com/tuist/tuist"
  --label "dev.tuist.ingress-nginx.fork=$FORK_REPOSITORY"
  --label "dev.tuist.ingress-nginx.fork-tag=$FORK_TAG"
  --label "dev.tuist.ingress-nginx.fork-commit=$FORK_COMMIT"
  --label "dev.tuist.ingress-nginx.tuist-revision=$revision"
  --label "dev.tuist.ingress-nginx.tag=$tag"
)
build=(docker buildx build --builder default --load --no-cache --provenance=false --sbom=false --progress=plain)

nginx_image="$prefix-nginx:$tag"
controller_image="$prefix-controller:$tag"
certgen_image="$prefix-kube-webhook-certgen:$tag"

echo "::group::Build $nginx_image"
"${build[@]}" --pull "${labels[@]}" \
  --label "dev.tuist.ingress-nginx.nginx-image-tag=$(cat "$src/images/nginx/TAG")" \
  --tag "$nginx_image" "$src/images/nginx/rootfs" 2>&1 | tee "$work/nginx-build.log"
echo "::endgroup::"

# Every patch in the stack must show up in the build's patch loop, in order.
sed -n 's/^#[0-9]* [0-9.]* Patch: //p' "$work/nginx-build.log" > "$work/patches-applied.txt"
if ! diff -u "$work/patches.txt" "$work/patches-applied.txt"; then
  echo "error: the nginx build did not apply the patch stack above" >&2
  exit 1
fi

# The controller binaries, built the way the fork's `make build` does
# (build/build.sh in a golang Alpine container), without its Docker socket mount.
echo "::group::Build controller binaries"
docker run --rm --pull always \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e GOCACHE=/tmp/go-cache -e GOMODCACHE=/tmp/go-mod -e GOTOOLCHAIN=local \
  -e PKG=k8s.io/ingress-nginx -e ARCH=amd64 \
  -e COMMIT_SHA="$FORK_COMMIT" -e REPO_INFO="$FORK_REPOSITORY" -e TAG="$version" \
  -v "$src:/go/src/k8s.io/ingress-nginx" -w /go/src/k8s.io/ingress-nginx \
  "$GO_IMAGE_ALPINE" build/build.sh
echo "::endgroup::"

# No --pull: BASE_IMAGE is the nginx image just built, which exists only locally.
echo "::group::Build $controller_image"
"${build[@]}" "${labels[@]}" \
  --build-arg BASE_IMAGE="$nginx_image" \
  --build-arg VERSION="$version" \
  --build-arg TARGETARCH=amd64 \
  --build-arg COMMIT_SHA="$FORK_COMMIT" \
  --build-arg BUILD_ID="$tag" \
  --tag "$controller_image" "$src/rootfs" 2>&1 | tee "$work/controller-build.log"
echo "::endgroup::"

echo "::group::Build $certgen_image"
"${build[@]}" --pull "${labels[@]}" \
  --label "dev.tuist.ingress-nginx.certgen-version=$(cat "$src/images/kube-webhook-certgen/TAG")" \
  --build-arg GOLANG_VERSION="$GO_IMAGE_DEBIAN_TAG" \
  --tag "$certgen_image" "$src/images/kube-webhook-certgen/rootfs" 2>&1 | tee "$work/certgen-build.log"
echo "::endgroup::"

cat > "$work/images.env" <<EOF
IMAGE_TAG=$tag
NGINX_IMAGE=$nginx_image
CONTROLLER_IMAGE=$controller_image
CERTGEN_IMAGE=$certgen_image
EOF
cat "$work/images.env"
