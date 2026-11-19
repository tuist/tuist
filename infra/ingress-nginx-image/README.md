# ingress-nginx images

Our build of the ingress-nginx controller from the
[Chainguard fork](https://github.com/chainguard-forks/ingress-nginx), which
keeps nginx 1.27.1 but backports nginx CVE fixes as patches
(`images/nginx/rootfs/patches/`). Upstream `kubernetes/ingress-nginx` is
archived and its last release (v1.15.1) has none of the 2026 nginx fixes, and
the fork publishes no free versioned images, so we build them here.

`.github/workflows/ingress-nginx-image.yml` builds three amd64 images:

| Image | From the fork | Replaces |
| --- | --- | --- |
| `ghcr.io/tuist/ingress-nginx-nginx` | `images/nginx` (nginx compiled with the patch stack) | `registry.k8s.io/ingress-nginx/nginx` |
| `ghcr.io/tuist/ingress-nginx-controller` | `rootfs/`, `FROM` our nginx image | `registry.k8s.io/ingress-nginx/controller:v1.15.1` |
| `ghcr.io/tuist/ingress-nginx-kube-webhook-certgen` | `images/kube-webhook-certgen` | `registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9` |

The controller and certgen images are drop-in replacements for the official
chart 4.15.1 images: same entrypoint, user (uid 101, gid 82), paths and file
capabilities. `verify.sh` checks that on every build against the official
images pinned in `fork.env`. To use them, point the chart's `controller.image`
(and `controller.admissionWebhooks.patch.image`) at the published tag and digest
from the publishing run's summary. Set `registry` to `ghcr.io` and `image` to
`tuist/ingress-nginx-controller`, or `tuist/ingress-nginx-kube-webhook-certgen`
for the certgen image.

`controller-chroot` is not built: we do not run the chroot variant.
Only amd64 is built. Our clusters run amd64 and the runner fleet is amd64-only,
so arm64 would mean compiling nginx, OpenTelemetry and ModSecurity under QEMU.

## Tags

Tags are `<fork version>-tuist.<TUIST_BUILD>`, for example `v1.15.16-tuist.1`,
and are never overwritten: publishing fails if the tag already exists. Pin by
digest in charts.

## Changing what is built

Everything is pinned in [`fork.env`](fork.env):

- **New fork release:** set `FORK_TAG` and `FORK_COMMIT` (`git ls-remote
  https://github.com/chainguard-forks/ingress-nginx refs/tags/<tag>^{}`), reset
  `TUIST_BUILD` to 1. The build fails if the tag does not resolve to the commit.
- **Sources the fork fetches by tag:** the fork's nginx build clones ModSecurity
  (`MODSECURITY_LIB_VERSION`) and the OWASP CRS (`OWASP_MODSECURITY_CRS_VERSION`)
  by git tag, and its certgen image starts `FROM gcr.io/distroless/static:nonroot`.
  `source.sh` makes the build fail unless the tags resolve to `MODSECURITY_COMMIT`
  and `CRS_COMMIT`, and pins distroless to `DISTROLESS_IMAGE`. When a fork release
  bumps one, update its pin (`git ls-remote <repository> refs/tags/<tag>^{}`).
- **Any other change to the images** (patches, Go toolchain, a rebuild for
  Alpine package fixes): bump `TUIST_BUILD`.

Pull requests build, verify and test without publishing. Merging to `main`
publishes, and so does a manual dispatch on `main`.

## Our nginx patches

Put extra nginx patches, such as CVE backports the fork has not shipped yet, in
[`patches/`](patches/) as `NNNN-description.patch` (`git diff` format against
the patched nginx 1.27.1 tree, applied with `patch -p1`). `source.sh` copies
them into the fork's patch directory as `zz-tuist-NNNN-description.patch`, so
the fork's `build.sh` applies them after its own, in name order. Each patch
must apply cleanly on top of the fork's stack: the build fails otherwise, and
also fails if the build log does not show every patch applied.

The fork's nginx test suite (`images/nginx/tests`: nginx-tests plus the fork's
own tests, against nginx built with AddressSanitizer) runs with our patches
included. Add a regression test for a backport as a Test::Nginx script in
[`tests/`](tests/); `source.sh` copies it into the fork's `tests/t/` as
`tuist-<name>.t`. The fork's `images/nginx/tests/t/harness.t` is a minimal
example, and its `images/nginx/README.md` shows how to run one file.

Drop a patch once the fork ships the same fix, or the stack will fail to apply.

## Local build

Needs Docker with buildx:

```console
infra/ingress-nginx-image/build.sh /tmp/ingress-nginx
infra/ingress-nginx-image/verify.sh /tmp/ingress-nginx
make -C /tmp/ingress-nginx/src/images/nginx test
```
