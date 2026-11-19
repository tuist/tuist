# ingress-nginx images

Our build of the ingress-nginx controller from the
[Rancher fork](https://github.com/rancher/ingress-nginx), which keeps nginx
1.27.1 and backports nginx CVE fixes as patches
(`images/nginx/rootfs/patches/`). Upstream `kubernetes/ingress-nginx` is
archived and its last release (v1.15.1) has none of the 2026 nginx fixes.
Rancher publishes its own images (`rancher/nginx-ingress-controller`) only to
its Prime registry for `-prime` tags, so we build them here, the way its
release workflow (`.github/workflows/release.yml`) does.

`.github/workflows/ingress-nginx-image.yml` builds three amd64 images:

| Image | From the fork | Replaces |
| --- | --- | --- |
| `ghcr.io/tuist/ingress-nginx-rancher-nginx` | `images/nginx/rootfs` (nginx compiled with the patch stack, on SUSE BCI 16.0) | `rancher/nginx` |
| `ghcr.io/tuist/ingress-nginx-rancher-controller` | `rootfs/`, `FROM` our nginx image | `rancher/nginx-ingress-controller` |
| `ghcr.io/tuist/ingress-nginx-rancher-kube-webhook-certgen` | `images/kube-webhook-certgen` | `rancher/kube-webhook-certgen` |

`controller-chroot` is not built: we do not run the chroot variant. Only amd64
is built: our clusters and the runner fleet are amd64.

The fork's `NGINX_BASE` file names the unpatched upstream
`registry.k8s.io/ingress-nginx/nginx:v2.2.8`, which a plain `make image` would
build on. Rancher's release builds the base from `images/nginx/rootfs` and
passes it as `BASE_IMAGE`; so does `build.sh`, and `verify.sh` fails unless the
controller's nginx is byte-identical to the one in our nginx image and carries
messages only the fork's CVE backports add.

## Package names

These publish under new package names, not `ghcr.io/tuist/ingress-nginx-*`
where the Chainguard-fork build (`v1.15.16-tuist.1`) lives and production pulls
from. The images are not interchangeable: different base OS (glibc on SUSE
instead of musl on Alpine), init (`catatonit` instead of `dumb-init`), group
(gid 101 instead of 82) and file layout (see "Contract"). Under the same name,
changing only a tag in chart values would swap in an image the chart's
`securityContext` and probes were not set up for. Separate packages keep that a
deliberate change, keep the old package's tags untouched, and make the image
name say which fork it came from. Tags are also distinct by construction
(`v1.15.2-prime5-tuist.1`), so they could not collide either way.

## Tags

Tags are `<fork tag>-tuist.<TUIST_BUILD>`, for example
`v1.15.2-prime5-tuist.1`, and are never overwritten: publishing fails if the
tag already exists. Pin by digest in charts.

## Contract

These are **not** drop-in replacements for the official chart 4.15.1 images or
for `v1.15.16-tuist.1`. `verify.sh` reports the differences against both on
every build (in the job summary) without failing on them. Against both, they
are:

- **Entrypoint:** `["/usr/bin/catatonit", "--"]` instead of
  `["/usr/bin/dumb-init", "--"]`; `/usr/bin/dumb-init` does not exist. The
  chart sets only `args`, so it works unchanged.
- **User and group:** `www-data` is uid 101, **gid 101** (official: gid 82),
  and every file the controller owns is 101:101. The chart's security context
  sets `runAsGroup` from `controller.image.runAsGroup` (default 82). The
  controller would still run as gid 82, as file owner, but set it to 101.
- **File capabilities:** `cap_net_bind_service` on `/nginx-ingress-controller`,
  `/usr/local/nginx/sbin/nginx` and `/usr/bin/catatonit` (official: on
  `dumb-init` instead of `catatonit`). The chart's `NET_BIND_SERVICE` works
  unchanged.
- **Paths:** nginx, `/etc/nginx`, `/etc/ingress-controller`, `/var/lib/nginx`,
  `/var/log/nginx`, `/tmp/nginx` and the Lua paths are where the chart expects
  them. `/sbin` is a symlink to `/usr/sbin` (usr-merged SUSE), so `/sbin/nginx`
  resolves through it. Libraries are glibc, in `/usr/lib64` and
  `/usr/local/lib64`; `/etc/ld-musl-x86_64.path` is written but unused, and
  anything mounted through `controller.extraModules` must be a glibc build.
- **`/etc/nginx/template`:** byte-identical. **`/etc/nginx/lua`:** only
  `configuration.lua` (and its test) differ, from Rancher's validation of the
  dynamic-configuration payload (rancher/ingress-nginx#242).
- **kube-webhook-certgen:** same image configuration (distroless, uid 65532).

To run it, in the shared `&ingressNginxControllerImage` anchor of
`infra/helm/platform/values.yaml` (which rack-cache-gateways also renders):
`image: tuist/ingress-nginx-rancher-controller`, the new `tag` and `digest`,
and `runAsGroup: 101`; and point `admissionWebhooks.patch.image` at
`tuist/ingress-nginx-rancher-kube-webhook-certgen`.

## Changing what is built

Everything is pinned in [`fork.env`](fork.env) and
[`sources.sha256`](sources.sha256):

- **New fork release:** set `FORK_TAG` and `FORK_COMMIT` (`git ls-remote
  https://github.com/rancher/ingress-nginx refs/tags/<tag>`), reset
  `TUIST_BUILD` to 1. The build fails if the tag does not resolve to the commit.
  Check the fork's new patches against our [`patches/`](patches/).
- **Tarballs:** the fork's `download.sh` fetches its sources with `get_src`,
  but its sha256 sums are stale and the check is commented out. `source.sh`
  replaces them with the sums in `sources.sha256` (keyed by the URL as written
  in `download.sh`) and turns the check on, and fails if a `get_src` line has
  no entry or an entry is unused. When a fork release changes `version.sh`,
  download the new tarball and update its line.
- **Sources fetched by git or tag:** ModSecurity (`MODSECURITY_COMMIT`), the
  OWASP CRS (`CRS_COMMIT`) and ssdeep (`SSDEEP_COMMIT`; the fork takes its
  default branch tip) are held to commits, and the certgen distroless base to
  `DISTROLESS_IMAGE`. `ngx_brotli` and `opentelemetry-cpp-contrib` are pinned
  by the fork itself.
- **Base images:** `BCI_BUILD_IMAGE`, `BCI_RUNTIME_IMAGE`, `GO_BUILD_IMAGE` and
  `GO_IMAGE_DEBIAN_TAG` are pinned by digest. SUSE runtime packages
  (`packages.txt`) install at their latest signed versions; `source.sh` makes
  the extra openSUSE Leap repository the fork adds use HTTPS.
- **Any other change to the images** (patches, toolchains, a rebuild for SUSE
  package fixes): bump `TUIST_BUILD`.

Pull requests build, verify and test without publishing. Merging to `main`
publishes, and so does a manual dispatch on `main`.

## Our nginx patches

Put extra nginx patches, such as CVE backports the fork has not shipped yet or
fixes to its backports, in [`patches/`](patches/) as `NNNN-description.patch`
(`git diff` format against the patched nginx 1.27.1 tree, applied with
`patch -p1`). `source.sh` copies them into the fork's patch directory as
`zz-tuist-NNNN-description.patch`, so the fork's `build.sh` applies them after
its own, in name order. Each patch must apply cleanly on top of the fork's
stack: the build fails otherwise, and also fails if the build log does not
show every patch applied. Drop a patch once the fork ships the same fix.

## nginx tests

The Rancher fork has no nginx test suite of its own (its CI runs Go and Lua
unit tests and Kubernetes e2e tests). [`tests/`](tests/) carries the harness
from the Chainguard fork's `images/nginx/tests`, adapted to the Rancher layout:
the pinned upstream [nginx-tests](https://github.com/nginx/nginx-tests) suite
against nginx built with AddressSanitizer from the fork's version, configure
flags and patch stack, ours included. Add a regression test for a backport as
a Test::Nginx script in `tests/` (`*.t`); `tests/run.sh t/<name>.t` runs one.

## Local build

Needs Docker with buildx:

```console
infra/ingress-nginx-image/build.sh /tmp/ingress-nginx
infra/ingress-nginx-image/verify.sh /tmp/ingress-nginx
infra/ingress-nginx-image/nginx-tests.sh /tmp/ingress-nginx-tests
```
