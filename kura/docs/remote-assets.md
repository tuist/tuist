# Bazel dependency downloads

Kura implements the Remote Asset API's `build.bazel.remote.asset.v1.Fetch/FetchBlob` on the same gRPC endpoint as its CAS. Bazel asks Kura to fetch a dependency archive, then reads the verified bytes from CAS. Later builds can reuse the archive without contacting its origin, including from ephemeral runners with empty repository caches.

This follows the Remote Asset/CAS architecture used by [BuildBuddy](https://www.buildbuddy.io/docs/remote-asset-api/) and [Buildbarn](https://github.com/buildbarn/bb-remote-asset). It separates availability of dependency bytes from the action cache while keeping the dependency's declared integrity check.

## Client configuration

`tuist bazel setup` configures both services and local fallback. For standalone Kura:

```bazelrc
build --remote_cache=grpcs://cache.example.com
build --experimental_remote_downloader=grpcs://cache.example.com
build --experimental_remote_downloader_local_fallback=true
build --remote_instance_name=my-project
```

Use the same remote headers or scoped credential helper as the cache. Local fallback is explicitly enabled because Bazel 9.1.1 defaults it to false. It allows builds to use their usual downloader when an older Kura node returns `UNIMPLEMENTED`, an origin is unsupported, or fetching fails. Remove fallback for validation that requires every download to pass through Kura. Our CI uses `.github/scripts/enable-bazel-remote-downloader.sh` to bridge its pinned CLI until the CLI release includes these defaults.

Origin credentials are separate from Kura credentials. Setup does not enable `--experimental_remote_downloader_propagate_credentials`; private downloads can use Bazel's local fallback. Users explicitly enabling propagation can send the supported HTTP-header qualifiers. Kura credentials are never forwarded to an origin.

## Identity and persistence

The service understands `checksum.sri` (SHA-256, SHA-384 and SHA-512), `bazel.canonical_id`, `http_header:Name`, and `http_header_url:N:Name`. Unsupported or duplicate qualifier names are rejected. CAS digests use SHA-256. Downloads without integrity qualifiers are supported, but pinning integrity is necessary for reproducible dependency identity.

Each project namespace stores ordinary Reapi CAS blobs plus `remote-asset/v1/` lookup records. Lookup keys hash the requested URI, integrity, canonical ID and effective origin headers; records contain only the CAS digest, size and original fetch start time. Raw URIs and credentials are not stored in these records or logged. Only a successful URI receives a mapping, so one mirror's credentials never authorize reuse under another mirror's identity. `oldest_content_accepted` can force a refetch.

Both records and bodies use existing asynchronous peer replication, retention, eviction and namespace cleanup. Existing peers can replicate them without understanding Remote Asset. A hit requires the CAS body to be present; missing bodies trigger refetch. This is a cache with no expiry lease, not a permanent archive: a completely cold mesh still needs an available upstream, and eviction or incomplete peer replication can require another origin download.

## Limits and failure handling

There are at most 32 admitted fetches per node, with same-key requests coalesced within a namespace. Each request supports 16 URIs and 64 qualifiers within 64 KiB. Downloads are streamed through Kura's existing memory and temporary-disk budgets, with a 2 GiB limit. Nothing is published before length and integrity verification. Critical memory pressure or a saturated replication outbox rejects new misses.

Fetches default to a 10-minute total timeout, clamped to 10 minutes when the client requests longer. Connection and body-read timeouts are 10 and 30 seconds. A transient origin failure gets up to three attempts per URI with bounded backoff, then proceeds to the next mirror. Disconnects and timeouts cancel work and release staging resources.

Only public HTTP(S) destinations are supported. DNS results are validated and pinned before connection; every redirect is checked again. Private, loopback, link-local, reserved, mapped private IPv6 and metadata-service addresses are blocked. Proxy environment variables are ignored. Redirects are limited to ten, HTTPS downgrades are rejected, and supplied origin headers are removed on cross-origin redirects. FetchDirectory and Push return `UNIMPLEMENTED`/are not registered.

## Rollout and verification

Deploy Kura and the Kura controller ingress update first, then enable clients. The managed gateway must route `/build.bazel.remote.asset.v1.` using `grpc_pass`, alongside the existing REAPI and ByteStream prefixes. Explicit local fallback permits mixed old/new nodes and rollback. The CAS and lookup storage formats need no migration. To opt out, set `build --experimental_remote_downloader=`; setup refresh preserves explicit custom endpoints and fallback preferences.

Focused tests run with `bazel test //:kura_lib_test --test_arg=reapi::asset --test_output=errors`. The ShellSpec check in `spec/e2e/bazel_remote_asset_spec.sh` runs real Bazel repository downloads against an isolated local Kura process with local fallback disabled and separate local caches. Set `KURA_REMOTE_ASSET_BINARY` to the absolute path of the built Kura binary, then run `shellspec spec/e2e/bazel_remote_asset_spec.sh`; Bazel 9.1.1, Python 3 and public origin access are required.
