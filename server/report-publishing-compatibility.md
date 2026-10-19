# Report publishing compatibility

Actor attribution is additive metadata, not authentication or feature negotiation. A client claim never identifies an account, authorizes a request, or overrides the stored actor of an existing report.

## Client and transport matrix

| Client | Older server responses | Updated/future responses | Credential-free boundary |
| --- | --- | --- | --- |
| Swift CLI, native and legacy reports | Missing actor fields decode as `nil`; existing required report fields retain their types | Optional actor, unknown JSON fields, and open source/provenance strings decode without closed-enum failures | Explicit opt-in plus a self-hosted destination and genuinely absent credentials; local completed Xcode reports only, without archives or privileged references |
| Gradle | Existing minimal build/test response envelopes remain valid | Gson ignores actor fields and future properties, including configuration-cache reuse | Strict credential inspection precedes omission; build/test JSON excludes Git origins |
| Elixir/Mix | Unsigned tests omit unused runtime/custom metadata rejected by earlier strict servers; signed tests and Mix builds retain their metadata | Responses are decoded maps; callers accept additional actor fields and unfamiliar provenance | Only supported report POSTs allow absent credentials; reads, archives, shard planning, coverage and history keep ordinary authentication |
| Bazel through Kura | Native BES/protobuf and signed reporting are unchanged; a server without network publishing support denies unsigned sessions | Actor metadata does not change BES acknowledgments or become a required control-plane response property | The server explicitly authorizes bounded BES-only publication; no cache/read permission or canonical test evidence is granted |
| Cargo through the Swift CLI | Existing authenticated build response remains valid | Cargo tests use the shared test response contract and optional actor metadata | Cargo builds remain authenticated-only and do not gain actor columns or unsigned publishing through this change |

The native test endpoint retains its existing build-system support. Native Cargo tests can use that existing endpoint; that does not enable credential-free Cargo build creation.

## Rolling client/server upgrades

- Old clients need not send `x-tuist-actor-id`. Verified individuals still come only from server authentication. Shared credentials without a claim yield Unknown; historical empty provenance keeps legacy attribution.
- New clients may send the optional actor header to an older server. It does not change their JSON body or the server's authentication requirements.
- Current clients accept older responses without actor metadata, explicit null actor fields, and future actor source/provenance strings and response properties.
- New unsigned Mix clients use the common earlier test-report shape. Updated servers also accept the actual earlier formatter payload, including its explicitly typed and bounded runtime/custom metadata. That auxiliary test metadata is not persisted. This permits either side to upgrade first.
- Request compatibility is not permission to accept arbitrary unsigned fields. Undeclared fields, nested opaque objects where strings are expected, protected references and unsupported report states remain rejected before and after casting.
- A server predating credential-free publication cannot acquire that feature from a client opt-in. Denial or transport failure remains a reporting error, never a credential-removal or anonymous-retry instruction.
- Roll out clients containing the credential-inspection and origin-omission fixes before enabling unsigned publication. A server upgrade cannot repair an old client's mistaken credential-absence decision or remove a credential-bearing origin before that old client transmits/logs it. Keep unsigned publishing disabled during that rollout; ordinary authenticated older clients remain compatible.

## Credential and origin privacy

Only a genuinely absent credential path can authorize an explicitly opted-in unsigned report. Access denial, non-directory ancestors, broken links, corrupt/rejected credentials, failed refreshes, and supplied invalid/blank credentials are errors. Gradle uses strict NIO inspection rather than `File.exists()`/`listFiles()`, whose false/null results can conceal access errors. Valid directory symlinks and legacy hostname aliases remain supported.

Unsigned Swift and Gradle builds omit the Git origin **before JSON serialization**, matching unsigned test and Mix behavior. Server-side credential stripping alone is insufficient because it occurs after transit and client-side logging. Authenticated payload behavior is unchanged.

## Regression coverage

- `server/test/tuist_web/controllers/api/report_attribution_test.exs`: native/legacy credential and claim matrix, body forgery, stored actors on supported same-ID retries, matching persisted/response attribution.
- `server/test/tuist_web/controllers/api/network_trusted_reports_test.exs`: actual formatter callbacks and old wire payload, absent/future contract versions, bounded metadata, unsupported fields, unverified parent/child actors, native Cargo test compatibility.
- `cli/Tests/TuistServerTests/Models/ReportActorCompatibilityTests.swift`: old/current/future response envelopes, parent/child actors, open provenance, and an older response decoder.
- `cli/Tests/TuistKitTests/Services/UploadBuildRunServiceTests.swift`: actual serialized unsigned Xcode build JSON with a credential-bearing origin fixture; existing signed behavior.
- `gradle/.../TokenProviderTest.kt`: real permission-denied ancestors, aliases, missing paths, valid and dangling links, rejected credentials, refresh failures and destination validation.
- `gradle/.../NetworkTrustedPublishingIntegrationTest.kt`: real builds, old/future responses, configuration-cache reuse and captured unsigned JSON without origins.
- `gradle/.../ReportResponseCompatibilityTest.kt`: old/null/future actor response decoding.
- `tuist_ex/test/tuist_ex/analytics/network_trusted_publishing_test.exs`: real formatter payloads through the unsigned transport, atom/string keys, response evolution and unchanged signed/build metadata.

These are representative contract and runtime regressions, not execution of every historical binary or proof of compatibility with arbitrary future protocol changes. Clean dependency CI, deployment migrations and production ingress protection remain separate release requirements.
