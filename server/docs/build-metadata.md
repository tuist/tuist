# Build infrastructure metadata

Build infrastructure and runtime observations use the existing `custom_metadata` contract:

```json
{
  "custom_metadata": {
    "tags": ["nightly"],
    "values": {
      "team": "mobile",
      "tuist.cpu.available_processors": "28",
      "tuist.gradle.max_workers": "8",
      "tuist.jvm.max_heap_bytes": "8589934592"
    }
  }
}
```

Values remain strings. The server stores them in each build's `custom_values` map and tags in `custom_tags`. No environment document, new reserved-key allowance, or required field is introduced. Existing version, model and CI fields remain first-class fields; collectors do not manufacture copies of them in a second response object.

## Semantics and display

`Tuist.Builds.Metadata` recognizes the following optional keys for display. Recognition is not ingestion validation: unknown keys and malformed recognized values remain visible as ordinary custom metadata and survive REST/MCP reads.

| Keys | Meaning |
| --- | --- |
| `tuist.os.type`, `tuist.os.version` | OS family (`darwin`, `linux`, `windows`, etc.) and product OS version when known, without localized prose. Omit product versions that cannot be determined soundly. |
| `tuist.os.kernel_version` | Kernel release, not a product OS version. Used by BEAM on Unix and the JVM on Linux. |
| `tuist.host.arch` | Build-process architecture, not the compilation target. Architecture spellings remain source-native. |
| `tuist.host.model` | Optional reported machine model. Existing Xcode model fields are not duplicated by automatic collection. |
| `tuist.cpu.available_processors` | Positive logical-processor availability reported by the runtime, not configured workers or measured concurrency. |
| `tuist.memory.total_bytes` | Positive OS/runtime-reported memory capacity in bytes. This is not a heap size or a guaranteed container limit. |
| `tuist.process.locale`, `tuist.process.charset` | Build-process locale and default charset when observable. |
| `tuist.jvm.vendor`, `tuist.jvm.runtime_name`, `tuist.jvm.runtime_version`, `tuist.jvm.vm_name`, `tuist.jvm.vm_version` | JVM runtime and VM descriptions, distinct from the existing Java language/version field. |
| `tuist.jvm.max_heap_bytes` | Positive maximum heap of the reporting JVM, in bytes, not host RAM. |
| `tuist.gradle.max_workers` | Positive effective worker limit of this Gradle invocation. |
| `tuist.ci.provider`, `tuist.ci.job`, `tuist.ci.runner_environment` | Allowlisted CI context when available and not already represented by the producer's first-class fields. |
| `tuist.ci.runner_name` | Identifying runner name, collected only with `TUIST_BUILD_METADATA_RUNNER_NAME=1`. |

The shared build-detail components group existing toolchain/runtime/host fields and recognized observations in a separate **Build environment** Noora card immediately below Build Details, collapsed by default across Xcode, Gradle, Bazel, Mix, Cargo and Once. Environment fields use a compact key/value grid with labels above values, matching Build Details and adapting from four columns to two and then one on narrow screens. This includes Xcode/macOS versions and Mac model, Gradle/Java versions, Bazel version, Elixir/OTP versions, Rust version, and the already-recorded Once version/host class. These existing fields retain their API/storage contracts; the presentation does not copy them into the metadata map or collect new Once observations. Legacy reports with only version fields still show the card; missing fields are omitted, and the card is omitted only when no environment fields or recognized observations exist. Build Details keeps invocation, result, attribution, source and configuration information (including Xcode configuration and Mix environment). Remaining map entries stay under **Custom metadata** inside Build Details, once per entry. Numeric formatting requires a positive integer no larger than `9007199254740991`; other values stay raw. Every value is an untrusted client claim, never a verified runner identity or authorization input.

## Producers and origin

- **Gradle** collects allowlisted OS/JVM/runtime/CI properties at report time. `WorkerLeaseService.maxWorkerCount` is read at execution time, including restored configuration-cache builds; setup-time/configuration-time worker values are not reused. Failed probes are omitted.
- **Mix** enriches compile reports only. It observes the current BEAM runtime's OS/kernel version, process architecture, available logical processors, locale and allowlisted CI context. Scheduler counts are not relabeled as CPUs. The shared test metadata collector and transport do not acquire these probes or larger budgets.
- **Cargo** collects the live decorating CLI's OS/process/memory/locale and allowlisted CI observations. It also accepts the existing `TUIST_BUILD_TAGS` and `TUIST_BUILD_VALUE_*` conventions, with explicit values winning. Cargo metadata is sent only after expanded support is advertised, because older Cargo endpoints did not have a metadata field at all. Invalid new Cargo explicit metadata is omitted as a whole with a warning, rather than truncating customer entries or rejecting a previously publishable build report.
- **Xcode** collects a snapshot only when the live `tuist xcodebuild build` wrapper creates its upload service. Inspecting/importing an activity log uses no new automatic host observations, so it cannot label the uploader as the build host. The wrapper omits `tuist.os.version` because Xcode already has a first-class macOS version. Other Xcode entry points retain existing metadata behavior.
- **Bazel** keeps source-origin custom build metadata forwarded through Kura. Kura's host is not the build machine and is never probed for these values. Its existing producer cap remains 20; this change does not add fresh Bazel machine probes or relabel the setup-time `TUIST_CPU_COUNT` snapshot.
- **Once** needs a coordinated change to the authoritative external `tuist/once` protocol/client before adding this map. This change intentionally leaves the vendored protocol and generated protobuf code untouched. Existing `effective_limits` are protocol limits, not machine resources.

Automatic collection never dumps environment variables, usernames, hostnames, IP addresses, JVM arguments, or compiler arguments. Missing observations stay absent. Explicit customer values override probes; automatic additions only fill free slots and never evict explicit metadata. Existing producer-side handling of oversized explicit metadata is unchanged.

## Compatibility and rollout

The updated server accepts **64 total values**, including both customer and recognized keys. Existing tag, key, value and body limits remain in force. Existing clients may keep their legacy 20-value producer limits. New collectors use 20 unless the configured destination explicitly advertises a larger allowance.

`GET /api/metadata/limits` is credential-free and returns an integer `max_values` plus `x-tuist-custom-metadata-max-values`, with `cache-control: no-store`. Advertisement defaults to **20** independently of server acceptance. Set `TUIST_EXPANDED_BUILD_METADATA_ENABLED=true` to advertise **64** only after a complete receiver rollout. Gradle and Swift read the header; Mix reads the JSON integer. Missing endpoints, unexpected responses, redirects, timeouts and invalid/out-of-range limits fall back to 20. Discovery strips URL credentials/query parameters, sends no build data or authentication, has two-second connection/read timeouts, and has no persistent capability cache or metadata-related POST retry. Existing-contract collectors only discover when candidate metadata exceeds 20; Cargo always discovers before introducing its new field.

Roll out in this order:

1. Apply the Cargo ClickHouse migration and deploy all receiving web/ingestion and `TUIST_MODE=processor` replicas with advertisement disabled. Acceptance is already 64, but clients still send legacy-size maps.
2. Complete the rollout across every replica that may receive or process the subsequent report. Xcode processors revalidate stored metadata when replacing processing placeholders, so old processor pods cannot safely process expanded maps. One capable replica does not establish cluster-wide support.
3. After compatibility validation, enable advertisement consistently across the destination. Only then allow expanded reports and Cargo metadata.
4. Before downgrading, disable advertisement everywhere and drain discovery/report in-flight windows, queued producer submissions, and queued/in-flight `:process_build` jobs carrying expanded metadata before restoring smaller-limit/older web or processor pods. There is no persistent client capability cache, but a process can still be between discovery and submission. Never replay an accepted Kura batch or retry a build POST to recover metadata.

Unknown future keys remain ordinary strings through storage, REST, MCP and Kura forwarding within each producer's structural limits. This does not promise unbounded payloads or that older producers gain a larger budget. Released-reader fixtures and a genuinely mixed-version deployment/downgrade exercise are still required before enabling advertisement; same-tree generated-client tests are not proof of released-client compatibility.

## Storage and scope

Xcode, Gradle, Mix and Bazel reuse their existing metadata columns. Cargo adds empty-default `custom_tags Array(String)` and `custom_values Map(String, String)` columns to `cargo_builds`. Metadata follows the parent build's retention and project-scoped export, with no new blob category. See `server/data-export.md`.

Resource time series, metadata filtering/materialization, automatic identity, and additional Once/Bazel instrumentation are outside this change.
