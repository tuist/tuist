# Changelog

All notable changes to this project will be documented in this file.
## What's Changed in cache@0.32.7<!-- RELEASE NOTES START -->

### ⛰️  Features

* credo — flag directives inside ExUnit block macros ([#10895](https://github.com/tuist/tuist/pull/10895))
### 🐛 Bug Fixes

* preserve prerelease dots in registry versions ([#11136](https://github.com/tuist/tuist/pull/11136))
* support private CAs for cache-to-server auth ([#10903](https://github.com/tuist/tuist/pull/10903))
* stop requiring unused S3 CA secret ([#10861](https://github.com/tuist/tuist/pull/10861))
* honor custom S3 CA bundles for virtual-hosted endpoints ([#10855](https://github.com/tuist/tuist/pull/10855))
* support custom S3 CA certificates ([#10839](https://github.com/tuist/tuist/pull/10839))
* preserve registry Link header in host nginx ([#10538](https://github.com/tuist/tuist/pull/10538))
* tighten disk eviction watermarks to 75/60 ([#10486](https://github.com/tuist/tuist/pull/10486))
* filter stale non-semantic registry versions ([#10406](https://github.com/tuist/tuist/pull/10406))
* self-heal missing registry manifests metadata on read ([#10397](https://github.com/tuist/tuist/pull/10397))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.32.0...cache@0.32.7

## What's Changed in cache@0.32.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add analytics circuit breaker and webhook hardening ([#10378](https://github.com/tuist/tuist/pull/10378))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.31.0...cache@0.32.0

## What's Changed in cache@0.31.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support HEAD requests for Registry endpoints ([#10324](https://github.com/tuist/tuist/pull/10324))
### 🐛 Bug Fixes

* persist skipped registry releases ([#10369](https://github.com/tuist/tuist/pull/10369))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.30.0...cache@0.31.0

## What's Changed in cache@0.30.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Fix cache read atomicity and treat corrupt Gradle entries as misses ([#10353](https://github.com/tuist/tuist/pull/10353))
### 🐛 Bug Fixes

* rotate cache SSH access keys ([#10340](https://github.com/tuist/tuist/pull/10340))
* harden sqlite maintenance contention handling ([#10316](https://github.com/tuist/tuist/pull/10316))
* handle inaccessible submodules during registry sync ([#10256](https://github.com/tuist/tuist/pull/10256))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.29.2...cache@0.30.0

## What's Changed in cache@0.29.2<!-- RELEASE NOTES START -->

### ⛰️  Features

* add unix-socket health checks for Kamal deploys ([#10192](https://github.com/tuist/tuist/pull/10192))
* add purge-cache task ([#10158](https://github.com/tuist/tuist/pull/10158))
### 🐛 Bug Fixes

* return 408 for parser body read timeouts ([#10219](https://github.com/tuist/tuist/pull/10219))
* strip registry symlinks outside package root ([#10251](https://github.com/tuist/tuist/pull/10251))
* report discarded Oban jobs to Sentry ([#10245](https://github.com/tuist/tuist/pull/10245))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.27.0...cache@0.29.2

## What's Changed in cache@0.27.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add k6 load testing suite with load-test PR label ([#10106](https://github.com/tuist/tuist/pull/10106))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.26.2...cache@0.27.0

## What's Changed in cache@0.26.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* avoid queueing uploads that already exist in S3 ([#10069](https://github.com/tuist/tuist/pull/10069))
* reduce upload memory pressure ([#10050](https://github.com/tuist/tuist/pull/10050))
* ignore unexpected SQLiteBuffer messages ([#10045](https://github.com/tuist/tuist/pull/10045))
### 🚜 Refactor

* Jason -> JSON ([#10052](https://github.com/tuist/tuist/pull/10052))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.26.0...cache@0.26.2

## What's Changed in cache@0.26.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* enable registry on canary cache nodes ([#9988](https://github.com/tuist/tuist/pull/9988))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.25.0...cache@0.26.0

## What's Changed in cache@0.25.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* distributed KV ([#9842](https://github.com/tuist/tuist/pull/9842))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.24.3...cache@0.25.0

## What's Changed in cache@0.24.3<!-- RELEASE NOTES START -->

### 🚜 Refactor

* naming consistency ([#9811](https://github.com/tuist/tuist/pull/9811))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.24.2...cache@0.24.3

## What's Changed in cache@0.24.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix alloy regex ([#9828](https://github.com/tuist/tuist/pull/9828))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.24.1...cache@0.24.2

## What's Changed in cache@0.24.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add optional Xcode cache bucket and size-based KV eviction ([#9751](https://github.com/tuist/tuist/pull/9751))
### 🐛 Bug Fixes

* reduce metrics cardinality ([#9818](https://github.com/tuist/tuist/pull/9818))
* limit Cachex entries ([#9792](https://github.com/tuist/tuist/pull/9792))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.23.1...cache@0.24.1

## What's Changed in cache@0.23.1<!-- RELEASE NOTES START -->

### ⚡ Performance

* adjust nginx settings ([#9761](https://github.com/tuist/tuist/pull/9761))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.23.0...cache@0.23.1

## What's Changed in cache@0.23.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track cache endpoint in analytics events ([#9696](https://github.com/tuist/tuist/pull/9696))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.22.4...cache@0.23.0

## What's Changed in cache@0.22.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve symlinks in two passes to handle broken symlinks in target dirs ([#9711](https://github.com/tuist/tuist/pull/9711))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.22.3...cache@0.22.4

## What's Changed in cache@0.22.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve directory symlinks in registry archives ([#9702](https://github.com/tuist/tuist/pull/9702))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.22.2...cache@0.22.3

## What's Changed in cache@0.22.2<!-- RELEASE NOTES START -->

### ⛰️  Features

* raise Gradle upload size limit to 100MB ([#9662](https://github.com/tuist/tuist/pull/9662))
### 🐛 Bug Fixes

* zero-downtime deploys via unique socket paths ([#9694](https://github.com/tuist/tuist/pull/9694))
* preserve directory symlinks to prevent infinite recursion during zip ([#9661](https://github.com/tuist/tuist/pull/9661))
### ⚡ Performance

* write upload temp files to storage filesystem for atomic renames ([#9686](https://github.com/tuist/tuist/pull/9686))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.21.1...cache@0.22.2

## What's Changed in cache@0.21.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add OrphanCleanupWorker for incremental disk orphan detection ([#9549](https://github.com/tuist/tuist/pull/9549))
* add CAS artifact cleanup on key-value eviction ([#9548](https://github.com/tuist/tuist/pull/9548))
### 🐛 Bug Fixes

* resolve symlinks when syncing registry packages ([#9625](https://github.com/tuist/tuist/pull/9625))
* strip leading zeros from version components in registry KeyNormalizer ([#9606](https://github.com/tuist/tuist/pull/9606))
* add configparser_ex dependency for awscli auth ([#9598](https://github.com/tuist/tuist/pull/9598))
### 🚜 Refactor

* make all tests async ([#9580](https://github.com/tuist/tuist/pull/9580))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.20.0...cache@0.21.1

## What's Changed in cache@0.20.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* report registry download events to server ([#9546](https://github.com/tuist/tuist/pull/9546))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.19.0...cache@0.20.0

## What's Changed in cache@0.19.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* reduce worst-case registry sync latency ([#9551](https://github.com/tuist/tuist/pull/9551))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.18.3...cache@0.19.0

## What's Changed in cache@0.18.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix incorrect S3 url composition when S3_ENDPOINT is set ([#9550](https://github.com/tuist/tuist/pull/9550))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.18.2...cache@0.18.3

## What's Changed in cache@0.18.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle null last_accessed_at in eviction and cap batch size ([#9539](https://github.com/tuist/tuist/pull/9539))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.18.1...cache@0.18.2

## What's Changed in cache@0.18.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix migration and catch error class in CI ([#9534](https://github.com/tuist/tuist/pull/9534))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.18.0...cache@0.18.1

## What's Changed in cache@0.18.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add LRU eviction for key_value_entries ([#9499](https://github.com/tuist/tuist/pull/9499))
### 🐛 Bug Fixes

* resolve S3 connect_options crash for self-hosted cache ([#9528](https://github.com/tuist/tuist/pull/9528))
* use git index to discover submodule paths in registry release worker ([#9494](https://github.com/tuist/tuist/pull/9494))
* re-inject Content-Version header for registry requests served via nginx ([#9492](https://github.com/tuist/tuist/pull/9492))
* use non-recursive tmpfiles rule for /cas mount point ([#9460](https://github.com/tuist/tuist/pull/9460))
* route Loki and OTLP traffic to host instead of container loopback ([#9452](https://github.com/tuist/tuist/pull/9452))
### 🚜 Refactor

* rename cas_artifacts table to cache_artifacts ([#9500](https://github.com/tuist/tuist/pull/9500))
### ⚡ Performance

* tune SQLite and nginx for throughput ([#9495](https://github.com/tuist/tuist/pull/9495))
* optimize upload paths ([#9433](https://github.com/tuist/tuist/pull/9433))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.17.1...cache@0.18.0

## What's Changed in cache@0.17.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* enable logs and traces from cache nodes to Grafana ([#9439](https://github.com/tuist/tuist/pull/9439))
* add service_namespace label to Loki log handler ([#9438](https://github.com/tuist/tuist/pull/9438))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.17.0...cache@0.17.1

## What's Changed in cache@0.17.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support IAM role and IRSA for S3 authentication ([#9416](https://github.com/tuist/tuist/pull/9416))
### 🐛 Bug Fixes

* fix missing traces and scope Alloy log labels ([#9411](https://github.com/tuist/tuist/pull/9411))
### 🚜 Refactor

* make nginx configuration more consistent ([#9418](https://github.com/tuist/tuist/pull/9418))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.16.1...cache@0.17.0

## What's Changed in cache@0.16.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix incorrect application/zip mime type detection ([#9401](https://github.com/tuist/tuist/pull/9401))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.16.0...cache@0.16.1

## What's Changed in cache@0.16.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add request ID to traces and logs ([#9409](https://github.com/tuist/tuist/pull/9409))
* add log forwarding to Loki and additional OTEL traces ([#9358](https://github.com/tuist/tuist/pull/9358))
### 🐛 Bug Fixes

* fix Loki logger handler crash from incorrect structured_metadata format ([#9408](https://github.com/tuist/tuist/pull/9408))
* fix Grafana telemetry connectivity and log-trace correlation ([#9404](https://github.com/tuist/tuist/pull/9404))
* remove S3.exists? from module download hot path ([#9387](https://github.com/tuist/tuist/pull/9387))
### 🚜 Refactor

* split monolithic Cache.Disk into domain-specific modules ([#9393](https://github.com/tuist/tuist/pull/9393))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.14.0...cache@0.16.0

## What's Changed in cache@0.14.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* registry ([#9086](https://github.com/tuist/tuist/pull/9086))
* add S3 operation observability metrics ([#9386](https://github.com/tuist/tuist/pull/9386))
### 🐛 Bug Fixes

* keep registry secrets in base deploy config with empty de… ([#9390](https://github.com/tuist/tuist/pull/9390))
* move registry secrets to production-only deploy config ([#9389](https://github.com/tuist/tuist/pull/9389))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.13.3...cache@0.14.0

## What's Changed in cache@0.13.3<!-- RELEASE NOTES START -->

### 🚜 Refactor

* performance improvements ([#9297](https://github.com/tuist/tuist/pull/9297))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.13.2...cache@0.13.3

## What's Changed in cache@0.13.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* force octet-stream for proxied downloads ([#9316](https://github.com/tuist/tuist/pull/9316))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.13.1...cache@0.13.2

## What's Changed in cache@0.13.1<!-- RELEASE NOTES START -->

### 🚜 Refactor

* use ETS to buffer ([#9300](https://github.com/tuist/tuist/pull/9300))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.13.0...cache@0.13.1

## What's Changed in cache@0.13.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* buffer and batch SQLite writes ([#9207](https://github.com/tuist/tuist/pull/9207))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.12.2...cache@0.13.0

## What's Changed in cache@0.12.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* scale nginx workers to avoid 502s ([#9293](https://github.com/tuist/tuist/pull/9293))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.12.1...cache@0.12.2

## What's Changed in cache@0.12.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* track releases in Sentry using commit SHA ([#9263](https://github.com/tuist/tuist/pull/9263))
### 🐛 Bug Fixes

* use correct cache ttl for server auth failures ([#9279](https://github.com/tuist/tuist/pull/9279))
* fix Sentry event filter signature ([#9255](https://github.com/tuist/tuist/pull/9255))
### 🚜 Refactor

* enable FQDN longnames ([#9260](https://github.com/tuist/tuist/pull/9260))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.11.0...cache@0.12.1

## What's Changed in cache@0.11.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* replace AppSignal with Sentry for error tracking ([#9249](https://github.com/tuist/tuist/pull/9249))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.10.5...cache@0.11.0

## What's Changed in cache@0.10.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* send runtime errors in correct format ([#9246](https://github.com/tuist/tuist/pull/9246))
* detect client disconnect in Bandit ensure_completed ([#9244](https://github.com/tuist/tuist/pull/9244))
* improve body read timeout handling and client disconnect detection ([#9202](https://github.com/tuist/tuist/pull/9202))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.10.2...cache@0.10.5

## What's Changed in cache@0.10.2<!-- RELEASE NOTES START -->

### 🚜 Refactor

* adjust timeouts and pools ([#9214](https://github.com/tuist/tuist/pull/9214))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.10.1...cache@0.10.2

## What's Changed in cache@0.10.1<!-- RELEASE NOTES START -->

### 🚜 Refactor

* move custom credo checks to TuistCommon ([#9211](https://github.com/tuist/tuist/pull/9211))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.10.0...cache@0.10.1

## What's Changed in cache@0.10.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* file descriptor metrics ([#9204](https://github.com/tuist/tuist/pull/9204))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.9.0...cache@0.10.0

## What's Changed in cache@0.9.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add metrics for authentication ([#9198](https://github.com/tuist/tuist/pull/9198))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.8.6...cache@0.9.0

## What's Changed in cache@0.8.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* tune sqlite config for bursty writes ([#9206](https://github.com/tuist/tuist/pull/9206))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.8.5...cache@0.8.6

## What's Changed in cache@0.8.5<!-- RELEASE NOTES START -->

### 🚜 Refactor

* deduplicate authentication requests to server ([#9201](https://github.com/tuist/tuist/pull/9201))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.8.4...cache@0.8.5

## What's Changed in cache@0.8.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* ensure files are closed during upload ([#9205](https://github.com/tuist/tuist/pull/9205))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.8.3...cache@0.8.4

## What's Changed in cache@0.8.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* increase open file descriptor limit ([#9197](https://github.com/tuist/tuist/pull/9197))
### 🚜 Refactor

* lower s3 transfer concurrency ([#9196](https://github.com/tuist/tuist/pull/9196))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.8.1...cache@0.8.3

## What's Changed in cache@0.8.1<!-- RELEASE NOTES START -->

### 🚜 Refactor

* use req for S3 requests ([#9186](https://github.com/tuist/tuist/pull/9186))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.8.0...cache@0.8.1

## What's Changed in cache@0.8.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* adjust pools and add metrics ([#9184](https://github.com/tuist/tuist/pull/9184))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.7.1...cache@0.8.0

## What's Changed in cache@0.7.1<!-- RELEASE NOTES START -->

### 🚜 Refactor

* add more structured fields to nginx logs ([#9178](https://github.com/tuist/tuist/pull/9178))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.7.0...cache@0.7.1

## What's Changed in cache@0.7.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add sampled nginx access logs ([#9174](https://github.com/tuist/tuist/pull/9174))
* create finch pool to server_url ([#9176](https://github.com/tuist/tuist/pull/9176))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.6.5...cache@0.7.0

## What's Changed in cache@0.6.5<!-- RELEASE NOTES START -->

### 🚜 Refactor

* data -> storage ([#9171](https://github.com/tuist/tuist/pull/9171))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.6.4...cache@0.6.5

## What's Changed in cache@0.6.4<!-- RELEASE NOTES START -->

### 🚜 Refactor

* rename CAS_STORAGE_DIR and /cas ([#9167](https://github.com/tuist/tuist/pull/9167))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.6.3...cache@0.6.4

## What's Changed in cache@0.6.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* enable credo properly ([#9149](https://github.com/tuist/tuist/pull/9149))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.6.2...cache@0.6.3

## What's Changed in cache@0.6.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix clean jobs not executing ([#9147](https://github.com/tuist/tuist/pull/9147))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.6.1...cache@0.6.2

## What's Changed in cache@0.6.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* implement remote cache cleaning ([#9124](https://github.com/tuist/tuist/pull/9124))
### 🐛 Bug Fixes

* fix test ([#9107](https://github.com/tuist/tuist/pull/9107))
### 🚜 Refactor

* move sampling plug to TuistCommon ([#9131](https://github.com/tuist/tuist/pull/9131))
### 📚 Documentation

* add documentation ([#9065](https://github.com/tuist/tuist/pull/9065))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.5.0...cache@0.6.1

## What's Changed in cache@0.5.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* manage platform with colmena ([#9091](https://github.com/tuist/tuist/pull/9091))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.4.2...cache@0.5.0

## What's Changed in cache@0.4.2<!-- RELEASE NOTES START -->

### 🚜 Refactor

* increase module cache file size limit ([#9097](https://github.com/tuist/tuist/pull/9097))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.4.1...cache@0.4.2

## What's Changed in cache@0.4.1<!-- RELEASE NOTES START -->

### 🚜 Refactor

* increase s3 batch size ([#9082](https://github.com/tuist/tuist/pull/9082))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.4.0...cache@0.4.1

## What's Changed in cache@0.4.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* module cache, s3 transfer metrics ([#9066](https://github.com/tuist/tuist/pull/9066))
* extract common code into shared library ([#9046](https://github.com/tuist/tuist/pull/9046))
### 🐛 Bug Fixes

* fix release and deploy ([#9069](https://github.com/tuist/tuist/pull/9069))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.3.0...cache@0.4.0

## What's Changed in cache@0.3.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add reference docker-compose ([#8988](https://github.com/tuist/tuist/pull/8988))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.2.1...cache@0.3.0

## What's Changed in cache@0.2.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix oban credential evaluation ([#9062](https://github.com/tuist/tuist/pull/9062))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.2.0...cache@0.2.1

## What's Changed in cache@0.2.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* sample appsignal traces ([#9058](https://github.com/tuist/tuist/pull/9058))
* prepare secret-less self hosting ([#8990](https://github.com/tuist/tuist/pull/8990))
* increase s3 transfer concurrency ([#9047](https://github.com/tuist/tuist/pull/9047))
* release docker images ([#8966](https://github.com/tuist/tuist/pull/8966))
* module cache ([#8931](https://github.com/tuist/tuist/pull/8931))
* deployment notifications ([#8910](https://github.com/tuist/tuist/pull/8910))
* add oban web ([#8891](https://github.com/tuist/tuist/pull/8891))
* API specs + CLI client ([#8852](https://github.com/tuist/tuist/pull/8852))
* local JWT authentication ([#8671](https://github.com/tuist/tuist/pull/8671))
* add sqlite package and enable Oban logging ([#8681](https://github.com/tuist/tuist/pull/8681))
* machine metrics ([#8675](https://github.com/tuist/tuist/pull/8675))
* export logs to Grafana Cloud ([#8659](https://github.com/tuist/tuist/pull/8659))
* add us-west and ap-southeast regions ([#8661](https://github.com/tuist/tuist/pull/8661))
* grafana dashboard ([#8660](https://github.com/tuist/tuist/pull/8660))
* export metrics to Grafana Cloud ([#8647](https://github.com/tuist/tuist/pull/8647))
* add ci/cd ([#8629](https://github.com/tuist/tuist/pull/8629))
* add canary node ([#8626](https://github.com/tuist/tuist/pull/8626))
* persist keyvalue entries ([#8602](https://github.com/tuist/tuist/pull/8602))
* disk eviction  ([#8601](https://github.com/tuist/tuist/pull/8601))
* download files to disk when missing ([#8600](https://github.com/tuist/tuist/pull/8600))
* add metrics ([#8595](https://github.com/tuist/tuist/pull/8595))
* add appsignal integration ([#8594](https://github.com/tuist/tuist/pull/8594))
* serve files from s3 as fallback ([#8590](https://github.com/tuist/tuist/pull/8590))
* move to x-accel-redirect ([#8588](https://github.com/tuist/tuist/pull/8588))
* upload blobs to s3 ([#8576](https://github.com/tuist/tuist/pull/8576))
* add elixir cache node and platform ([#8515](https://github.com/tuist/tuist/pull/8515))
### 🐛 Bug Fixes

* use valid AppSignal sample data key for request context ([#9051](https://github.com/tuist/tuist/pull/9051))
* don't log http timeouts ([#9040](https://github.com/tuist/tuist/pull/9040))
* fix RequestContextPlug compilation in prod environment ([#8927](https://github.com/tuist/tuist/pull/8927))
* compile ruby ([#8926](https://github.com/tuist/tuist/pull/8926))
* prune oban jobs less aggressively ([#8909](https://github.com/tuist/tuist/pull/8909))
* fix accidentally commented deploy config ([#8897](https://github.com/tuist/tuist/pull/8897))
* do not report Bandit.TransportError to AppSignal ([#8879](https://github.com/tuist/tuist/pull/8879))
* handle upload failures gracefully ([#8865](https://github.com/tuist/tuist/pull/8865))
* fix alloy config formatting ([#8667](https://github.com/tuist/tuist/pull/8667))
* use Oban.Testing properly ([#8663](https://github.com/tuist/tuist/pull/8663))
* add missing release configuration ([#8656](https://github.com/tuist/tuist/pull/8656))
* fix locale setting in container ([#8655](https://github.com/tuist/tuist/pull/8655))
* handle upload cancellations ([#8649](https://github.com/tuist/tuist/pull/8649))
* ci ([#8639](https://github.com/tuist/tuist/pull/8639))
* fix deployments ([#8622](https://github.com/tuist/tuist/pull/8622))
* fix env var names ([#8581](https://github.com/tuist/tuist/pull/8581))
### 🚜 Refactor

* use directory sharding in disk storage ([#8899](https://github.com/tuist/tuist/pull/8899))
* batch up- and downloads to S3 ([#8889](https://github.com/tuist/tuist/pull/8889))
* refactor eviction worker ([#8707](https://github.com/tuist/tuist/pull/8707))
* store blobs on network volume ([#8683](https://github.com/tuist/tuist/pull/8683))
* store sqlite outside cas volume ([#8682](https://github.com/tuist/tuist/pull/8682))
* only send nginx error logs to Grafana Cloud ([#8669](https://github.com/tuist/tuist/pull/8669))
* bump ruby ([#8641](https://github.com/tuist/tuist/pull/8641))



**Full Changelog**: https://github.com/tuist/tuist/compare/cache@0.1.0...cache@0.2.0

<!-- generated by git-cliff -->
