# Changelog

All notable changes to this project will be documented in this file.
## What's Changed in server@1.207.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* gate production on an oldest-supported-CLI acceptance suite ([#11097](https://github.com/tuist/tuist/pull/11097))
* runner job steps + log capture (live tail, per-step) ([#10985](https://github.com/tuist/tuist/pull/10985))
* Module Cache breakdown for local Xcode builds ([#11087](https://github.com/tuist/tuist/pull/11087))
* gate runner availability solely on the :runners feature flag ([#11090](https://github.com/tuist/tuist/pull/11090))
### 🐛 Bug Fixes

* stop canary 500s from web-pool/Oban contention on create_project ([#11107](https://github.com/tuist/tuist/pull/11107))
* use a version below the floor in the lower-than-floor deprecation test ([#11121](https://github.com/tuist/tuist/pull/11121))
* lower minimum CLI version ([#11120](https://github.com/tuist/tuist/pull/11120))
* aggregate Kura usage by region ([#11092](https://github.com/tuist/tuist/pull/11092))
* configure STS region for IRSA ([#11111](https://github.com/tuist/tuist/pull/11111))
* Prefer ready Kura cache endpoints ([#11089](https://github.com/tuist/tuist/pull/11089))
* add id tiebreaker to test case runs pagination ([#11045](https://github.com/tuist/tuist/pull/11045))
* derive module name for UI test bundles in xcresult parser ([#11073](https://github.com/tuist/tuist/pull/11073))
* reap orphaned owner-stamped runner pods to prevent fleet wedge ([#11060](https://github.com/tuist/tuist/pull/11060))
### 📚 Documentation

* update self-host Docker Compose to use Kura ([#11079](https://github.com/tuist/tuist/pull/11079))
### 🧪 Testing

* run isolated test modules async to speed up the suite ([#11075](https://github.com/tuist/tuist/pull/11075))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.205.0...server@1.207.1

## What's Changed in server@1.205.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve scrollbar design ([#11051](https://github.com/tuist/tuist/pull/11051))
* move runners to the tuist-linux label and default the profile to 2 vCPU / 8 GB ([#11052](https://github.com/tuist/tuist/pull/11052))
* add account-scoped artifact retention jobs ([#10983](https://github.com/tuist/tuist/pull/10983))
* account-scoped Runner Profiles (Linux v1) ([#10970](https://github.com/tuist/tuist/pull/10970))
* exclude unvalidated test cases from flaky-test alert triggers ([#11009](https://github.com/tuist/tuist/pull/11009))
### 🐛 Bug Fixes

* retry the runner owner-label stamp so it stays reliable ([#11041](https://github.com/tuist/tuist/pull/11041))
* keep Kura cache grants compact ([#11039](https://github.com/tuist/tuist/pull/11039))
* remove min-width:100vw causing horizontal scroll with classic scrollbars ([#11018](https://github.com/tuist/tuist/pull/11018))
* fix preview install-prompt alert overlap and Download link ([#11017](https://github.com/tuist/tuist/pull/11017))
* restore cache response signatures ([#11026](https://github.com/tuist/tuist/pull/11026))
* remove Kura global endpoints ([#11014](https://github.com/tuist/tuist/pull/11014))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.203.1...server@1.205.0

## What's Changed in server@1.203.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* track Kura node usage and add Usage dashboard ([#10979](https://github.com/tuist/tuist/pull/10979))
### 🐛 Bug Fixes

* fall back from empty Kura endpoints ([#11008](https://github.com/tuist/tuist/pull/11008))
### ⚡ Performance

* speed up LiveView dashboard cold start



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.202.1...server@1.203.1

## What's Changed in server@1.202.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* look up existing test cases with a single array param ([#10976](https://github.com/tuist/tuist/pull/10976))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.202.0...server@1.202.1

## What's Changed in server@1.202.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* authorize tenant-scoped cache via OAuth introspection ([#10935](https://github.com/tuist/tuist/pull/10935))
* add auth.md agent registration ([#10964](https://github.com/tuist/tuist/pull/10964))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.201.0...server@1.202.0

## What's Changed in server@1.201.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Support self-hosted Kura endpoints ([#10965](https://github.com/tuist/tuist/pull/10965))
* Tuist Runners dashboard + billing — runners landing, workflows, jobs, settings hub ([#10848](https://github.com/tuist/tuist/pull/10848))
### 🐛 Bug Fixes

* send large test case lookups as multipart ([#10955](https://github.com/tuist/tuist/pull/10955))
* attach existing Tuist users on SCIM POST instead of returning 409 ([#10958](https://github.com/tuist/tuist/pull/10958))
* route project-only test case run listings through a slim MV ([#10952](https://github.com/tuist/tuist/pull/10952))
* guard marketing blog iframe template resolution ([#10949](https://github.com/tuist/tuist/pull/10949))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.200.2...server@1.201.0

## What's Changed in server@1.200.2<!-- RELEASE NOTES START -->

### ⛰️  Features

* rework Xcode Cache widgets with transfer/latency/throughput splits ([#10924](https://github.com/tuist/tuist/pull/10924))
* recover failed webhook deliveries via GitHub's redelivery API ([#10909](https://github.com/tuist/tuist/pull/10909))
* make the GitHub webhook hot path leave Postgres alone ([#10902](https://github.com/tuist/tuist/pull/10902))
* credo — flag directives inside ExUnit block macros ([#10895](https://github.com/tuist/tuist/pull/10895))
* update icons from 2px stroke to 1.5px stroke ([#10892](https://github.com/tuist/tuist/pull/10892))
* surface the global Kura endpoint as a clear banner ([#10867](https://github.com/tuist/tuist/pull/10867))
* instrument runners dispatch path and extend Grafana dashboard ([#10850](https://github.com/tuist/tuist/pull/10850))
* show module cache tab on the build detail page ([#10857](https://github.com/tuist/tuist/pull/10857))
* enforce stdlib JSON over Jason via credo check ([#10856](https://github.com/tuist/tuist/pull/10856))
* project Kura server status from observed cluster state ([#10851](https://github.com/tuist/tuist/pull/10851))
### 🐛 Bug Fixes

* apply shard min/max defaults when caller passes nil ([#10941](https://github.com/tuist/tuist/pull/10941))
* stabilize docs and xcresult tests ([#10900](https://github.com/tuist/tuist/pull/10900))
* disconnect active sessions after password reset ([#10896](https://github.com/tuist/tuist/pull/10896))
* harden GitHub webhook dispatch + add deliveries inspector task ([#10878](https://github.com/tuist/tuist/pull/10878))
### 📚 Documentation

* add security acknowledgments ([#10914](https://github.com/tuist/tuist/pull/10914))
### ⚡ Performance

* cut FINAL scans on ClickHouse test_case_runs and test_runs ([#10881](https://github.com/tuist/tuist/pull/10881))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.197.2...server@1.200.2

## What's Changed in server@1.197.2<!-- RELEASE NOTES START -->

### ⛰️  Features

* add outbound webhooks ([#10748](https://github.com/tuist/tuist/pull/10748))
### 🐛 Bug Fixes

* collapse webhook empty-state subtitle to fix mix format ([#10849](https://github.com/tuist/tuist/pull/10849))
* drop stale automation framing from webhook copy ([#10846](https://github.com/tuist/tuist/pull/10846))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.196.0...server@1.197.2

## What's Changed in server@1.196.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* expose is_quarantined on test case run API ([#10785](https://github.com/tuist/tuist/pull/10785))
### 🐛 Bug Fixes

* unstick orphaned running workflow_jobs end-to-end ([#10828](https://github.com/tuist/tuist/pull/10828))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.195.4...server@1.196.0

## What's Changed in server@1.195.4<!-- RELEASE NOTES START -->

### ⛰️  Features

* align self-hosted runner paths with GitHub-hosted ([#10826](https://github.com/tuist/tuist/pull/10826))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.195.3...server@1.195.4

## What's Changed in server@1.195.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* drop :finch from SSRF-pinned Req calls ([#10819](https://github.com/tuist/tuist/pull/10819))
* use request origin for MCP OAuth metadata ([#10812](https://github.com/tuist/tuist/pull/10812))
* unstick failed Kura deploys, auto-install platform ([#10811](https://github.com/tuist/tuist/pull/10811))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.195.1...server@1.195.3

## What's Changed in server@1.195.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add exact test history timestamp tooltips ([#10806](https://github.com/tuist/tuist/pull/10806))
### 🐛 Bug Fixes

* support org-owned GHES app manifests ([#10804](https://github.com/tuist/tuist/pull/10804))
* analyze every shard of a sharded test run ([#10810](https://github.com/tuist/tuist/pull/10810))
* exclude processing test runs from Recent Test Runs ([#10809](https://github.com/tuist/tuist/pull/10809))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.194.6...server@1.195.1

## What's Changed in server@1.194.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* send Content-Length on GHES manifest exchange ([#10790](https://github.com/tuist/tuist/pull/10790))
* rebackfill window_type on stale automation_alerts rows ([#10788](https://github.com/tuist/tuist/pull/10788))
* gate Guardian.DB.Sweeper on web mode ([#10789](https://github.com/tuist/tuist/pull/10789))
* avoid Kura readiness probe Req option conflict ([#10778](https://github.com/tuist/tuist/pull/10778))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.194.4...server@1.194.6

## What's Changed in server@1.194.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle expired SA tokens in TokenReview response ([#10787](https://github.com/tuist/tuist/pull/10787))
* expose Kura controls to ops ([#10769](https://github.com/tuist/tuist/pull/10769))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.194.2...server@1.194.4

## What's Changed in server@1.194.2<!-- RELEASE NOTES START -->

### ⛰️  Features

* isolate VCS comment worker on its own queue and dedupe ([#10757](https://github.com/tuist/tuist/pull/10757))
### 🐛 Bug Fixes

* gate Kura reconcile task on prod-like envs only ([#10776](https://github.com/tuist/tuist/pull/10776))
* renumber duplicate clickhouse migration version ([#10770](https://github.com/tuist/tuist/pull/10770))
* optimize clickhouse dashboard queries ([#10751](https://github.com/tuist/tuist/pull/10751))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.193.0...server@1.194.2

## What's Changed in server@1.193.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add manual-mark trigger for test case automations ([#10497](https://github.com/tuist/tuist/pull/10497))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.192.0...server@1.193.0

## What's Changed in server@1.192.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Hit filter to Selective Testing tab ([#10747](https://github.com/tuist/tuist/pull/10747))
* add docs markdown localization pilot ([#10685](https://github.com/tuist/tuist/pull/10685))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.191.4...server@1.192.0

## What's Changed in server@1.191.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* improve Kura cache server readiness ([#10744](https://github.com/tuist/tuist/pull/10744))
* build noora assets with aube ([#10752](https://github.com/tuist/tuist/pull/10752))
* prevent overlapping automation schedulers ([#10740](https://github.com/tuist/tuist/pull/10740))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.191.3...server@1.191.4

## What's Changed in server@1.191.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* raise rolling-window MV backfill memory ceiling to 12 GiB ([#10735](https://github.com/tuist/tuist/pull/10735))
* redirect to pending invitation after email confirmation ([#10734](https://github.com/tuist/tuist/pull/10734))
* minimize rolling-window MV backfill chunk size ([#10736](https://github.com/tuist/tuist/pull/10736))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.191.2...server@1.191.3

## What's Changed in server@1.191.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* reduce rolling-window MV backfill chunk size ([#10733](https://github.com/tuist/tuist/pull/10733))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.191.1...server@1.191.2

## What's Changed in server@1.191.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add rolling window option to flaky test automations ([#10674](https://github.com/tuist/tuist/pull/10674))
* show Deploying badge for Kura servers with an in-flight deployment ([#10719](https://github.com/tuist/tuist/pull/10719))
### 🐛 Bug Fixes

* chunk rolling-window MV backfill by project to fit ClickHouse memory ([#10731](https://github.com/tuist/tuist/pull/10731))
* bound ClickHouse memory for rolling-window flaky-tests MV backfill ([#10726](https://github.com/tuist/tuist/pull/10726))
* reap dead Postgres pool sockets via client-side TCP keepalive ([#10722](https://github.com/tuist/tuist/pull/10722))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.190.4...server@1.191.1

## What's Changed in server@1.190.4<!-- RELEASE NOTES START -->

### 🚜 Refactor

* hide infra details from Kura cache servers table ([#10713](https://github.com/tuist/tuist/pull/10713))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.190.3...server@1.190.4

## What's Changed in server@1.190.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* cast date to DateTime for CAS month-interval analytics ([#10711](https://github.com/tuist/tuist/pull/10711))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.190.2...server@1.190.3

## What's Changed in server@1.190.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent IRSA S3 auth cache crashes ([#10712](https://github.com/tuist/tuist/pull/10712))
* drop `installation` from GHES manifest default_events ([#10709](https://github.com/tuist/tuist/pull/10709))
* drop custom Finch from Tuist.Kubernetes.Client ([#10706](https://github.com/tuist/tuist/pull/10706))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.190.0...server@1.190.2

## What's Changed in server@1.190.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add request_kind tagging + page load Apdex dashboard ([#10701](https://github.com/tuist/tuist/pull/10701))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.189.4...server@1.190.0

## What's Changed in server@1.189.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bump fast-uri to 3.1.2 to address CVE-2026-6321/6322 ([#10707](https://github.com/tuist/tuist/pull/10707))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.189.3...server@1.189.4

## What's Changed in server@1.189.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* retry slow xcresult attachment uploads per chunk ([#10694](https://github.com/tuist/tuist/pull/10694))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.189.2...server@1.189.3

## What's Changed in server@1.189.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* log temp dir contents when xcresult extraction yields no bundle ([#10698](https://github.com/tuist/tuist/pull/10698))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.189.1...server@1.189.2

## What's Changed in server@1.189.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip CSRF cross-origin check for FunWithFlags UI assets ([#10691](https://github.com/tuist/tuist/pull/10691))
* retry transient ClickHouse transport errors marking flaky runs ([#10686](https://github.com/tuist/tuist/pull/10686))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.189.0...server@1.189.1

## What's Changed in server@1.189.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add Georgian locale support ([#10684](https://github.com/tuist/tuist/pull/10684))
### 🐛 Bug Fixes

* drop unprocessable xcresult uploads instead of retrying ([#10688](https://github.com/tuist/tuist/pull/10688))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.188.0...server@1.189.0

## What's Changed in server@1.188.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* manage multi-region Kura servers ([#10489](https://github.com/tuist/tuist/pull/10489))
### 🐛 Bug Fixes

* collapse per-project authorization N+1 in dashboard layout ([#10683](https://github.com/tuist/tuist/pull/10683))
### ⚡ Performance

* cut ClickHouse CPU on hot build/test/event lookups ([#10678](https://github.com/tuist/tuist/pull/10678))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.187.1...server@1.188.0

## What's Changed in server@1.187.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* make all non-web pods leader-ineligible in Oban ([#10679](https://github.com/tuist/tuist/pull/10679))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.187.0...server@1.187.1

## What's Changed in server@1.187.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* support GitHub Enterprise Server installations ([#10471](https://github.com/tuist/tuist/pull/10471))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.186.4...server@1.187.0

## What's Changed in server@1.186.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* accept text/plain on OpenAI Apps challenge endpoint ([#10676](https://github.com/tuist/tuist/pull/10676))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.186.3...server@1.186.4

## What's Changed in server@1.186.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* align Slack integration with marketplace requirements ([#10666](https://github.com/tuist/tuist/pull/10666))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.186.2...server@1.186.3

## What's Changed in server@1.186.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* split quarantine dashboard chart into muted and skipped series ([#10660](https://github.com/tuist/tuist/pull/10660))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.186.1...server@1.186.2

## What's Changed in server@1.186.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add tuist test case update command ([#10450](https://github.com/tuist/tuist/pull/10450))
* add MCP setup tools ([#10642](https://github.com/tuist/tuist/pull/10642))
* surface selective testing subhashes ([#10644](https://github.com/tuist/tuist/pull/10644))
* manage xcresult processor as a k8s Deployment via tart-cri (Mac minis as real k8s nodes) ([#10499](https://github.com/tuist/tuist/pull/10499))
* comparison-based automations with baseline establishment ([#10599](https://github.com/tuist/tuist/pull/10599))
* cut bundles over to ClickHouse (phase 3+4) ([#10615](https://github.com/tuist/tuist/pull/10615))
### 🐛 Bug Fixes

* remove former team member from about page ([#10630](https://github.com/tuist/tuist/pull/10630))
* restore main CI checks ([#10651](https://github.com/tuist/tuist/pull/10651))
* add required title to update_test_case MCP tool ([#10664](https://github.com/tuist/tuist/pull/10664))
* truncate bundle timestamps to second precision in API responses ([#10646](https://github.com/tuist/tuist/pull/10646))
* pass command_event to selective_testing_analytics in MCP tool ([#10647](https://github.com/tuist/tuist/pull/10647))
* align Quarantined and Flaky Tests counts with their lists ([#10601](https://github.com/tuist/tuist/pull/10601))
* build createBundle response without round-tripping through ClickHouse ([#10638](https://github.com/tuist/tuist/pull/10638))
* humanize scatter chart truncation date ([#10634](https://github.com/tuist/tuist/pull/10634))
* bump axios override to 1.15.2 to clear CVEs ([#10635](https://github.com/tuist/tuist/pull/10635))
* add explicit MCP tool review hints ([#10626](https://github.com/tuist/tuist/pull/10626))
* add favicon head links ([#10624](https://github.com/tuist/tuist/pull/10624))
* remove duplicate use TuistWeb, :verified_routes in plugs ([#10627](https://github.com/tuist/tuist/pull/10627))
### ⚡ Performance

* add project_id to flaky test_case_runs queries ([#10658](https://github.com/tuist/tuist/pull/10658))
* drop test_case_runs scans from Test Cases listing ([#10640](https://github.com/tuist/tuist/pull/10640))
* use full leading sort key in cross-run flakiness lookup ([#10608](https://github.com/tuist/tuist/pull/10608))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.185.0...server@1.186.1

## What's Changed in server@1.185.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* expose MCP tool titles and readOnlyHint annotations ([#10619](https://github.com/tuist/tuist/pull/10619))
### 📚 Documentation

* recommend best practices for worktrees and agentic coding ([#10609](https://github.com/tuist/tuist/pull/10609))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.184.2...server@1.185.0

## What's Changed in server@1.184.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* render English iframe template on localized blog routes ([#10610](https://github.com/tuist/tuist/pull/10610))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.184.1...server@1.184.2

## What's Changed in server@1.184.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* surface failed_processing status on test run pages ([#10600](https://github.com/tuist/tuist/pull/10600))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.184.0...server@1.184.1

## What's Changed in server@1.184.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* backfill bundles from PostgreSQL to ClickHouse (phase 2) ([#10597](https://github.com/tuist/tuist/pull/10597))
### 🐛 Bug Fixes

* re-populate tab data after refreshing a test run ([#10606](https://github.com/tuist/tuist/pull/10606))
### 📚 Documentation

* clarify module cache and Xcode cache can be combined ([#10605](https://github.com/tuist/tuist/pull/10605))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.183.0...server@1.184.0

## What's Changed in server@1.183.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* SCIM 2.0 provisioning + Authentication settings page ([#10544](https://github.com/tuist/tuist/pull/10544))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.182.0...server@1.183.0

## What's Changed in server@1.182.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* migrate bundles table from PostgreSQL to ClickHouse (phase 1) ([#10595](https://github.com/tuist/tuist/pull/10595))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.181.2...server@1.182.0

## What's Changed in server@1.181.2<!-- RELEASE NOTES START -->

### ⚡ Performance

* drop ClickHouse FINAL on hot ReplacingMergeTree id lookups ([#10579](https://github.com/tuist/tuist/pull/10579))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.181.1...server@1.181.2

## What's Changed in server@1.181.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* partition cross-run flakiness detection by scheme ([#10581](https://github.com/tuist/tuist/pull/10581))
* speed up xcactivitylog parse and surface real NIF errors ([#10594](https://github.com/tuist/tuist/pull/10594))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.181.0...server@1.181.1

## What's Changed in server@1.181.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* cut bundle artifacts over to ClickHouse (phase 3+4) ([#10580](https://github.com/tuist/tuist/pull/10580))
### 🐛 Bug Fixes

* Make GitHub app setup idempotent ([#10592](https://github.com/tuist/tuist/pull/10592))
* handle HTML comments in markdown conversion ([#10588](https://github.com/tuist/tuist/pull/10588))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.180.10...server@1.181.0

## What's Changed in server@1.180.10<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* coalesce automation actions to avoid stale-read race ([#10587](https://github.com/tuist/tuist/pull/10587))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.180.9...server@1.180.10

## What's Changed in server@1.180.9<!-- RELEASE NOTES START -->

### ⛰️  Features

* update radius to numerical values ([#10574](https://github.com/tuist/tuist/pull/10574))
### 🐛 Bug Fixes

* add max-height to org and projects dropdown ([#10572](https://github.com/tuist/tuist/pull/10572))
* linearize xcactivitylog determineCategory loop ([#10569](https://github.com/tuist/tuist/pull/10569))
### ⚡ Performance

* cut ClickHouse CPU from active test cases analytics chart ([#10564](https://github.com/tuist/tuist/pull/10564))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.180.5...server@1.180.9

## What's Changed in server@1.180.5<!-- RELEASE NOTES START -->

### 📚 Documentation

* expand flaky-tests pages with tracking, quarantine semantics, and API/CLI reference ([#10560](https://github.com/tuist/tuist/pull/10560))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.180.4...server@1.180.5

## What's Changed in server@1.180.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* allow test_case_id filter on test-case runs by test_run_id ([#10559](https://github.com/tuist/tuist/pull/10559))
* populate inserted_at when buffering build issues and files ([#10563](https://github.com/tuist/tuist/pull/10563))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.180.3...server@1.180.4

## What's Changed in server@1.180.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unblock processor pods crashlooping under concurrent xcactivitylog parses ([#10556](https://github.com/tuist/tuist/pull/10556))
* stream artifact backfill to bound migration memory ([#10558](https://github.com/tuist/tuist/pull/10558))
* emit Prometheus metrics on processor pods ([#10557](https://github.com/tuist/tuist/pull/10557))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.180.2...server@1.180.3

## What's Changed in server@1.180.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle :email_taken in OAuth choose-username flow ([#10546](https://github.com/tuist/tuist/pull/10546))
### ⚡ Performance

* speed up dev content compilation ([#10548](https://github.com/tuist/tuist/pull/10548))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.180.0...server@1.180.2

## What's Changed in server@1.180.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add service.version to OpenTelemetry resource ([#10543](https://github.com/tuist/tuist/pull/10543))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.179.1...server@1.180.0

## What's Changed in server@1.179.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bound artifact backfill memory and give migration job a memory request ([#10541](https://github.com/tuist/tuist/pull/10541))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.179.0...server@1.179.1

## What's Changed in server@1.179.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* backfill artifacts from PostgreSQL to ClickHouse (phase 2) ([#10509](https://github.com/tuist/tuist/pull/10509))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.178.1...server@1.179.0

## What's Changed in server@1.178.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* forward exceptions to OpenTelemetry via Tower ([#10520](https://github.com/tuist/tuist/pull/10520))
* split flaky widgets into three granularities ([#10521](https://github.com/tuist/tuist/pull/10521))
### 🐛 Bug Fixes

* make processor pods leader-ineligible in Oban ([#10530](https://github.com/tuist/tuist/pull/10530))
* bound xcactivitylog parser, dedupe ProcessBuildWorker, cap dirty NIF wall time ([#10525](https://github.com/tuist/tuist/pull/10525))
### 📚 Documentation

* add blog post on LLM-based localization with L10N.md ([#10514](https://github.com/tuist/tuist/pull/10514))
### ⚡ Performance

* cut ClickHouse CPU on three test-cases hot paths ([#10534](https://github.com/tuist/tuist/pull/10534))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.177.2...server@1.178.1

## What's Changed in server@1.177.2<!-- RELEASE NOTES START -->

### ⛰️  Features

* add "Skip" quarantine mode for test cases ([#10429](https://github.com/tuist/tuist/pull/10429))
* run processor in-cluster via Oban queue + least-privilege role ([#10428](https://github.com/tuist/tuist/pull/10428))
* migrate artifacts table from PostgreSQL to ClickHouse (phase 1) ([#10493](https://github.com/tuist/tuist/pull/10493))
* add locale-aware case studies ([#10424](https://github.com/tuist/tuist/pull/10424))
### 🐛 Bug Fixes

* sync S3 credentials from 1Password via ESO ([#10517](https://github.com/tuist/tuist/pull/10517))
* recover half-bootstrapped dev database installs ([#10518](https://github.com/tuist/tuist/pull/10518))
* redirect SSO callback to pending invitation instead of 401 ([#10399](https://github.com/tuist/tuist/pull/10399))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.175.1...server@1.177.2

## What's Changed in server@1.175.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unflake tests pages and shorten Test job runtime ([#10496](https://github.com/tuist/tuist/pull/10496))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.175.0...server@1.175.1

## What's Changed in server@1.175.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* move filters to page level for tests related pages ([#10373](https://github.com/tuist/tuist/pull/10373))
* serve MCP Server Card at /.well-known/mcp/server-card.json ([#10487](https://github.com/tuist/tuist/pull/10487))
* publish OAuth protected resource metadata ([#10456](https://github.com/tuist/tuist/pull/10456))
### 🐛 Bug Fixes

* remove unused quarantined_count_at to unblock prod build ([#10494](https://github.com/tuist/tuist/pull/10494))
* refresh PR comment after xcresult processing finishes ([#10483](https://github.com/tuist/tuist/pull/10483))
* fix API catalog endpoint ([#10454](https://github.com/tuist/tuist/pull/10454))
### ⚡ Performance

* speed up test_case_runs slow queries with lookup MVs ([#10425](https://github.com/tuist/tuist/pull/10425))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.172.0...server@1.175.0

## What's Changed in server@1.172.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* publish agent skills discovery index ([#10457](https://github.com/tuist/tuist/pull/10457))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.171.3...server@1.172.0

## What's Changed in server@1.171.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add content signals to robots.txt ([#10452](https://github.com/tuist/tuist/pull/10452))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.171.2...server@1.171.3

## What's Changed in server@1.171.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* wire in-cluster Valkey for canary/production rate limiter ([#10464](https://github.com/tuist/tuist/pull/10464))
* include muted events and stabilize quarantined-test pagination ([#10459](https://github.com/tuist/tuist/pull/10459))
* bump postcss to 8.5.10 for CVE-2026-41305 ([#10469](https://github.com/tuist/tuist/pull/10469))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.171.1...server@1.171.2

## What's Changed in server@1.171.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* return markdown for agent requests ([#10435](https://github.com/tuist/tuist/pull/10435))
* add link headers for agent discovery ([#10422](https://github.com/tuist/tuist/pull/10422))
* build cluster image once per commit, promote across envs ([#10438](https://github.com/tuist/tuist/pull/10438))
### 🐛 Bug Fixes

* widen bundle size columns online (no exclusive table lock) ([#10465](https://github.com/tuist/tuist/pull/10465))
* drop mix _build cache mount to unblock deploys ([#10444](https://github.com/tuist/tuist/pull/10444))
* switch canary database_url to direct endpoint ([#10442](https://github.com/tuist/tuist/pull/10442))
### ⚡ Performance

* cache mix _build and hex/rebar across Docker builds ([#10439](https://github.com/tuist/tuist/pull/10439))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.170.1...server@1.171.1

## What's Changed in server@1.170.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* unblock canary migration job by scoping ClickHouseRepo compile_env ([#10437](https://github.com/tuist/tuist/pull/10437))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.170.0...server@1.170.1

## What's Changed in server@1.170.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* migrate from Render to Syself Kubernetes (Helm chart, Alloy, ESO, cascade deploys) ([#10368](https://github.com/tuist/tuist/pull/10368))
* use feature flags for Kura cache endpoint selection ([#10380](https://github.com/tuist/tuist/pull/10380))
* page level filters for bundles ([#10376](https://github.com/tuist/tuist/pull/10376))
### 🐛 Bug Fixes

* stabilize flaky BundlesLiveTest assertions ([#10434](https://github.com/tuist/tuist/pull/10434))
* stabilize clickhouse transaction-backed tests ([#10409](https://github.com/tuist/tuist/pull/10409))
* handle non-integer bundle size analysis page param ([#10414](https://github.com/tuist/tuist/pull/10414))
* add muted/unmuted test case event types ([#10417](https://github.com/tuist/tuist/pull/10417))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.168.1...server@1.170.0

## What's Changed in server@1.168.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* widen bundle size columns to bigint ([#10400](https://github.com/tuist/tuist/pull/10400))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.168.0...server@1.168.1

## What's Changed in server@1.168.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add total flaky tests and total tests counts to dashboard ([#10393](https://github.com/tuist/tuist/pull/10393))
* page level filter for xcode cache page ([#10375](https://github.com/tuist/tuist/pull/10375))
### 🐛 Bug Fixes

* ops accounts modal — country picker, prefill, Stripe dashboard admin ([#10384](https://github.com/tuist/tuist/pull/10384))
* exercise repeated-header branch in HeadersTest correctly ([#10396](https://github.com/tuist/tuist/pull/10396))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.166.1...server@1.168.0

## What's Changed in server@1.166.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* make AddStateToTestCases migration idempotent ([#10394](https://github.com/tuist/tuist/pull/10394))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.166.0...server@1.166.1

## What's Changed in server@1.166.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* page level filter for module cache page ([#10374](https://github.com/tuist/tuist/pull/10374))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.165.1...server@1.166.0

## What's Changed in server@1.165.1<!-- RELEASE NOTES START -->

### ⚡ Performance

* speed up shard-plan timing query 46× via denormalization + projection ([#10383](https://github.com/tuist/tuist/pull/10383))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.165.0...server@1.165.1

## What's Changed in server@1.165.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add automations engine for flaky tests ([#10232](https://github.com/tuist/tuist/pull/10232))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.164.0...server@1.165.0

## What's Changed in server@1.164.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add dark mode to docs site ([#10323](https://github.com/tuist/tuist/pull/10323))
* add feature flag headers ([#10382](https://github.com/tuist/tuist/pull/10382))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.163.2...server@1.164.0

## What's Changed in server@1.163.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* restore missing vitepress docs path redirects ([#10371](https://github.com/tuist/tuist/pull/10371))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.163.1...server@1.163.2

## What's Changed in server@1.163.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add /ops/accounts dashboard with Enterprise upgrade flow ([#10359](https://github.com/tuist/tuist/pull/10359))
### 🐛 Bug Fixes

* restore scheme dropdown search and fix recent builds timing race ([#10361](https://github.com/tuist/tuist/pull/10361))
### 🚜 Refactor

* polish ops accounts dashboard — new-tab Stripe, 0 seats, cancel status ([#10377](https://github.com/tuist/tuist/pull/10377))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.162.1...server@1.163.1

## What's Changed in server@1.162.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* return structured errors from list_cacheable_tasks ([#10355](https://github.com/tuist/tuist/pull/10355))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.162.0...server@1.162.1

## What's Changed in server@1.162.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* page level filters ([#10199](https://github.com/tuist/tuist/pull/10199))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.161.0...server@1.162.0

## What's Changed in server@1.161.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* update heading typeface to inter ([#10352](https://github.com/tuist/tuist/pull/10352))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.160.0...server@1.161.0

## What's Changed in server@1.160.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add paginated test case events endpoint ([#10117](https://github.com/tuist/tuist/pull/10117))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.159.2...server@1.160.0

## What's Changed in server@1.159.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bump protobufjs to 7.5.5 for CVE-2026-41242 ([#10346](https://github.com/tuist/tuist/pull/10346))
* retry ClickHouse flush on socket drops ([#10342](https://github.com/tuist/tuist/pull/10342))
* bootstrap install in fresh worktrees ([#10335](https://github.com/tuist/tuist/pull/10335))
* return forbidden for non-user auth on account endpoints ([#10333](https://github.com/tuist/tuist/pull/10333))
### 🚜 Refactor

* Builds.get_build/1 returns {:ok, build} | {:error, :not_found} ([#10337](https://github.com/tuist/tuist/pull/10337))
### ⚡ Performance

* route flaky runs lookup through test_case_runs_by_test_run MV ([#10343](https://github.com/tuist/tuist/pull/10343))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.159.1...server@1.159.2

## What's Changed in server@1.159.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* show account dropdown in docs nav ([#10267](https://github.com/tuist/tuist/pull/10267))
* extend Oban job histogram buckets to 30 minutes ([#10305](https://github.com/tuist/tuist/pull/10305))
### 🐛 Bug Fixes

* return test_case_runs as explicit value on test run upsert ([#10330](https://github.com/tuist/tuist/pull/10330))
* use IF NOT EXISTS for test_run_destinations ClickHouse migration ([#10315](https://github.com/tuist/tuist/pull/10315))
* retry ClickHouse operations on transient connection errors ([#10313](https://github.com/tuist/tuist/pull/10313))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.157.0...server@1.159.1

## What's Changed in server@1.157.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* surface test run destinations on dashboard ([#10293](https://github.com/tuist/tuist/pull/10293))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.156.0...server@1.157.0

## What's Changed in server@1.156.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* remember per-tab query state for sidebar navigation ([#10287](https://github.com/tuist/tuist/pull/10287))
* add scatter plot chart type to analytics dashboards ([#10258](https://github.com/tuist/tuist/pull/10258))
### 🐛 Bug Fixes

* handle duplicate ClickHouse rows in get_command_event_by_*_id ([#10292](https://github.com/tuist/tuist/pull/10292))
* unflake gradle analytics tests and patch trivy findings ([#10289](https://github.com/tuist/tuist/pull/10289))
* size Processor + XcodeProcessor Finch S3 pools to prevent connection starvation ([#10279](https://github.com/tuist/tuist/pull/10279))
* improve SSO authentication error messages ([#10284](https://github.com/tuist/tuist/pull/10284))
* isolate build/xcresult workers and extend processor timeouts ([#10283](https://github.com/tuist/tuist/pull/10283))
* preserve build run list state ([#10274](https://github.com/tuist/tuist/pull/10274))
* align dashboard scheme filters and search ([#10272](https://github.com/tuist/tuist/pull/10272))
* sort dashboard filter options ([#10271](https://github.com/tuist/tuist/pull/10271))
* pin follow-redirects to 1.16.0 ([#10270](https://github.com/tuist/tuist/pull/10270))
* clear stale Slack report channels ([#10269](https://github.com/tuist/tuist/pull/10269))
* move SSO button to its own row on login page ([#10259](https://github.com/tuist/tuist/pull/10259))
* bump Debian base image to patch HIGH CVEs ([#10257](https://github.com/tuist/tuist/pull/10257))
### 🚜 Refactor

* merge /ops/cache into /ops with sidebar layout ([#10250](https://github.com/tuist/tuist/pull/10250))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.155.3...server@1.156.0

## What's Changed in server@1.155.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* align overview test duration widget with tests page ([#10253](https://github.com/tuist/tuist/pull/10253))
* handle inactive Slack report installations ([#10252](https://github.com/tuist/tuist/pull/10252))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.155.2...server@1.155.3

## What's Changed in server@1.155.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* increase processor worker max attempts to survive deployments ([#10249](https://github.com/tuist/tuist/pull/10249))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.155.1...server@1.155.2

## What's Changed in server@1.155.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle S3 download errors and failed_processing status ([#10244](https://github.com/tuist/tuist/pull/10244))
* report discarded Oban jobs to Sentry ([#10245](https://github.com/tuist/tuist/pull/10245))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.155.0...server@1.155.1

## What's Changed in server@1.155.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add custom OAuth2 SSO support ([#9982](https://github.com/tuist/tuist/pull/9982))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.154.1...server@1.155.0

## What's Changed in server@1.154.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include test_case_run_argument_id when building attachment rows ([#10242](https://github.com/tuist/tuist/pull/10242))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.154.0...server@1.154.1

## What's Changed in server@1.154.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* make chart bars clickable to navigate to detail pages ([#10091](https://github.com/tuist/tuist/pull/10091))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.153.1...server@1.154.0

## What's Changed in server@1.153.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add parameterized test argument support ([#10127](https://github.com/tuist/tuist/pull/10127))
### 🐛 Bug Fixes

* refresh account JWTs without crashing on preload ([#10238](https://github.com/tuist/tuist/pull/10238))
* patch vulnerable docs search dependencies ([#10236](https://github.com/tuist/tuist/pull/10236))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.152.4...server@1.153.1

## What's Changed in server@1.152.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use FINAL hint on test_case_runs_by_test_run MV queries ([#10226](https://github.com/tuist/tuist/pull/10226))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.152.3...server@1.152.4

## What's Changed in server@1.152.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* retry backfill inserts on ClickHouse TABLE_IS_READ_ONLY ([#10227](https://github.com/tuist/tuist/pull/10227))
### 📚 Documentation

* document default configuration selection for tuist cache ([#10229](https://github.com/tuist/tuist/pull/10229))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.152.1...server@1.152.3

## What's Changed in server@1.152.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add dashboard language preference to user settings ([#10189](https://github.com/tuist/tuist/pull/10189))
* use Noora components directly in doc markdown ([#10133](https://github.com/tuist/tuist/pull/10133))
### 🐛 Bug Fixes

* use DROP TABLE for inline MVs in ClickHouse 25.12 ([#10225](https://github.com/tuist/tuist/pull/10225))
### ⚡ Performance

* optimize slow ClickHouse queries on test case pages ([#10087](https://github.com/tuist/tuist/pull/10087))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.150.4...server@1.152.1

## What's Changed in server@1.150.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fall back to English OG image for unsupported locales ([#10191](https://github.com/tuist/tuist/pull/10191))
* install CJK and Cyrillic fonts for OG image generation ([#10213](https://github.com/tuist/tuist/pull/10213))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.150.3...server@1.150.4

## What's Changed in server@1.150.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* pass missing fields through xcresult processing worker ([#10204](https://github.com/tuist/tuist/pull/10204))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.150.2...server@1.150.3

## What's Changed in server@1.150.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* assign current_path in blog post LiveView ([#10202](https://github.com/tuist/tuist/pull/10202))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.150.1...server@1.150.2

## What's Changed in server@1.150.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* update defu to 6.1.5 to fix prototype pollution vulnerability ([#10196](https://github.com/tuist/tuist/pull/10196))
* restore backward compatibility for iOS app project listing ([#10159](https://github.com/tuist/tuist/pull/10159))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.150.0...server@1.150.1

## What's Changed in server@1.150.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* generate localized OG images with Carta for all marketing pages ([#10175](https://github.com/tuist/tuist/pull/10175))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.149.0...server@1.150.0

## What's Changed in server@1.149.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* adopt dashboard locale from browser ([#10167](https://github.com/tuist/tuist/pull/10167))
* Localize server-side number and currency formatting ([#10174](https://github.com/tuist/tuist/pull/10174))
### 🐛 Bug Fixes

* publish self-hosted image with embedded processor ([#10172](https://github.com/tuist/tuist/pull/10172))
* broken css in features section ([#10185](https://github.com/tuist/tuist/pull/10185))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.148.0...server@1.149.0

## What's Changed in server@1.148.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* update organization creation flow ([#9952](https://github.com/tuist/tuist/pull/9952))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.147.0...server@1.148.0

## What's Changed in server@1.147.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* per-changelog entry pages with OG images ([#10115](https://github.com/tuist/tuist/pull/10115))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.146.0...server@1.147.0

## What's Changed in server@1.146.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* LLM-based localization with hierarchical L10N.md context ([#10130](https://github.com/tuist/tuist/pull/10130))
### 🐛 Bug Fixes

* handle Test struct in Xcode.event_date_range/1 ([#10160](https://github.com/tuist/tuist/pull/10160))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.145.1...server@1.146.0

## What's Changed in server@1.145.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload xcresult attachments to S3 ([#10138](https://github.com/tuist/tuist/pull/10138))
* add remote processing mode for tuist inspect test ([#10094](https://github.com/tuist/tuist/pull/10094))
### 🐛 Bug Fixes

* authenticate MCP OAuth tokens as User ([#10156](https://github.com/tuist/tuist/pull/10156))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.143.5...server@1.145.1

## What's Changed in server@1.143.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* allow long test case names to wrap in header ([#10125](https://github.com/tuist/tuist/pull/10125))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.143.4...server@1.143.5

## What's Changed in server@1.143.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* update vulnerable JS dependencies (flatted, yaml) ([#10124](https://github.com/tuist/tuist/pull/10124))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.143.3...server@1.143.4

## What's Changed in server@1.143.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix mark-as-flaky race condition losing flaky flag ([#10123](https://github.com/tuist/tuist/pull/10123))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.143.2...server@1.143.3

## What's Changed in server@1.143.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix Project description link in docs references sidebar ([#10119](https://github.com/tuist/tuist/pull/10119))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.143.1...server@1.143.2

## What's Changed in server@1.143.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove broadcast listeners from analytics dashboard pages ([#10109](https://github.com/tuist/tuist/pull/10109))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.143.0...server@1.143.1

## What's Changed in server@1.143.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add branch column and filter to test case detail page ([#10108](https://github.com/tuist/tuist/pull/10108))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.142.0...server@1.143.0

## What's Changed in server@1.142.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add search and sorting to Ran by filter ([#10093](https://github.com/tuist/tuist/pull/10093))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.141.0...server@1.142.0

## What's Changed in server@1.141.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add selective testing observability via MCP, API, CLI, and skills ([#10013](https://github.com/tuist/tuist/pull/10013))
* make flaky test auto-clear duration configurable ([#10076](https://github.com/tuist/tuist/pull/10076))
### 🐛 Bug Fixes

* restore missing doc images after VitePress migration ([#10104](https://github.com/tuist/tuist/pull/10104))
* add og:image dimensions for better LinkedIn rendering ([#10100](https://github.com/tuist/tuist/pull/10100))
* use actual page URL for og:url meta tag ([#10098](https://github.com/tuist/tuist/pull/10098))
* prevent open redirect via protocol-relative return_to paths ([#10095](https://github.com/tuist/tuist/pull/10095))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.139.0...server@1.141.0

## What's Changed in server@1.139.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add login button and update logo text in docs navbar ([#10090](https://github.com/tuist/tuist/pull/10090))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.138.0...server@1.139.0

## What's Changed in server@1.138.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* generate docs OG images with Carta and BrowseServo ([#10084](https://github.com/tuist/tuist/pull/10084))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.137.1...server@1.138.0

## What's Changed in server@1.137.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* reverse recent builds chart data for chronological order ([#10092](https://github.com/tuist/tuist/pull/10092))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.137.0...server@1.137.1

## What's Changed in server@1.137.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add footer to docs pages with edit link and markdown view ([#10088](https://github.com/tuist/tuist/pull/10088))
### 🐛 Bug Fixes

* update gettext source reference ([#10081](https://github.com/tuist/tuist/pull/10081))
* prevent stale CSS by fixing cache headers ([#10075](https://github.com/tuist/tuist/pull/10075))
* docs UI fixes — remove Gradle icons, fix mobile dropdown, add Plain chat ([#10078](https://github.com/tuist/tuist/pull/10078))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.136.2...server@1.137.0

## What's Changed in server@1.136.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* render changelog entries with mdex ([#10061](https://github.com/tuist/tuist/pull/10061))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.136.1...server@1.136.2

## What's Changed in server@1.136.1<!-- RELEASE NOTES START -->

### 🚜 Refactor

* add new cache endpoints as disabled ([#10060](https://github.com/tuist/tuist/pull/10060))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.136.0...server@1.136.1

## What's Changed in server@1.136.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add search functionality to docs site ([#10049](https://github.com/tuist/tuist/pull/10049))
### 🐛 Bug Fixes

* retry MV backfill on TABLE_IS_READ_ONLY ([#10070](https://github.com/tuist/tuist/pull/10070))
* pass database name to SYSTEM SYNC DATABASE REPLICA ([#10068](https://github.com/tuist/tuist/pull/10068))
* strip port 80/443 from MCP OAuth resource URL ([#10067](https://github.com/tuist/tuist/pull/10067))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.135.1...server@1.136.0

## What's Changed in server@1.135.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* optimize test_case_runs queries by test_run_id ([#10053](https://github.com/tuist/tuist/pull/10053))
* add View more button to Gradle cache Recent Builds card ([#10044](https://github.com/tuist/tuist/pull/10044))
### 🐛 Bug Fixes

* use DROP VIEW SYNC to fix deploy migration failure ([#10066](https://github.com/tuist/tuist/pull/10066))
* fix BadMapError crash when requesting non-existent project ([#10042](https://github.com/tuist/tuist/pull/10042))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.134.1...server@1.135.1

## What's Changed in server@1.134.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix broken sharding docs link in dashboard ([#10043](https://github.com/tuist/tuist/pull/10043))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.134.0...server@1.134.1

## What's Changed in server@1.134.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* link build runs to shard plans ([#10032](https://github.com/tuist/tuist/pull/10032))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.133.0...server@1.134.0

## What's Changed in server@1.133.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* show git branch as Noora badge in dashboard navbar ([#10002](https://github.com/tuist/tuist/pull/10002))
* expire stale in-progress test runs after 6 hours ([#10020](https://github.com/tuist/tuist/pull/10020))
### 🐛 Bug Fixes

* query ShardRun table for shard balance analytics ([#10031](https://github.com/tuist/tuist/pull/10031))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.132.6...server@1.133.0

## What's Changed in server@1.132.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* flush ClickHouse buffers in test_fixture to prevent flaky tests ([#10027](https://github.com/tuist/tuist/pull/10027))
### ⚡ Performance

* add project_id to shard MV for efficient main table lookup ([#10028](https://github.com/tuist/tuist/pull/10028))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.132.5...server@1.132.6

## What's Changed in server@1.132.5<!-- RELEASE NOTES START -->

### ⚡ Performance

* drop FINAL from shard_id 20-row ID lookup ([#10025](https://github.com/tuist/tuist/pull/10025))
* paginate shard_id queries on MV instead of main table ([#10023](https://github.com/tuist/tuist/pull/10023))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.132.4...server@1.132.5

## What's Changed in server@1.132.4<!-- RELEASE NOTES START -->

### ⚡ Performance

* optimize slow ClickHouse queries on test tables ([#10022](https://github.com/tuist/tuist/pull/10022))
* optimize slow ClickHouse queries on test tables ([#10014](https://github.com/tuist/tuist/pull/10014))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.132.2...server@1.132.4

## What's Changed in server@1.132.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* filter out in-progress test runs from xcode overview chart ([#10016](https://github.com/tuist/tuist/pull/10016))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.132.1...server@1.132.2

## What's Changed in server@1.132.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* run quarantined tests instead of skipping them ([#9978](https://github.com/tuist/tuist/pull/9978))
* add transport metadata to Loki structured metadata ([#9990](https://github.com/tuist/tuist/pull/9990))
### 🐛 Bug Fixes

* enrich transport logs with request context and reduce noise ([#9999](https://github.com/tuist/tuist/pull/9999))
* use TUIST_SERVER_URL for endpoint URL in dev mode ([#10001](https://github.com/tuist/tuist/pull/10001))
* share clone-local dev instance scoping with cache ([#9979](https://github.com/tuist/tuist/pull/9979))
### ⚡ Performance

* parallelize ClickHouse queries in TestRunLive ([#10010](https://github.com/tuist/tuist/pull/10010))
* pass project_id to test_runs_metrics for ClickHouse primary key match ([#9994](https://github.com/tuist/tuist/pull/9994))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.130.2...server@1.132.1

## What's Changed in server@1.130.2<!-- RELEASE NOTES START -->

### ⚡ Performance

* defer post-processing after create_test_modules in POST /tests ([#9985](https://github.com/tuist/tuist/pull/9985))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.130.1...server@1.130.2

## What's Changed in server@1.130.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test sharding support ([#9796](https://github.com/tuist/tuist/pull/9796))
### ⚡ Performance

* optimize create_test_modules in-memory processing ([#9980](https://github.com/tuist/tuist/pull/9980))
* batch test_cases lookup into single ClickHouse query ([#9976](https://github.com/tuist/tuist/pull/9976))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.129.0...server@1.130.1

## What's Changed in server@1.129.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* trace OpenApiSpex CastAndValidate to diagnose slow endpoints ([#9977](https://github.com/tuist/tuist/pull/9977))
### 🐛 Bug Fixes

* use atom key for OpentelemetryEcto span attributes ([#9975](https://github.com/tuist/tuist/pull/9975))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.128.0...server@1.129.0

## What's Changed in server@1.128.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add OpenTelemetry Ecto tracing for all database repos ([#9963](https://github.com/tuist/tuist/pull/9963))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.127.3...server@1.128.0

## What's Changed in server@1.127.3<!-- RELEASE NOTES START -->

### ⚡ Performance

* tighten xcode_targets date range from ±1 day to -5min/+2h ([#9972](https://github.com/tuist/tuist/pull/9972))
* create flaky_test_case_runs MV for clear_stale_flaky_flags ([#9973](https://github.com/tuist/tuist/pull/9973))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.127.2...server@1.127.3

## What's Changed in server@1.127.2<!-- RELEASE NOTES START -->

### ⚡ Performance

* add date range filter to xcode_targets preload queries ([#9960](https://github.com/tuist/tuist/pull/9960))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.127.1...server@1.127.2

## What's Changed in server@1.127.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove per-attachment ClickHouse lookup on creation ([#9955](https://github.com/tuist/tuist/pull/9955))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.127.0...server@1.127.1

## What's Changed in server@1.127.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add shared HTTP failure observability ([#9935](https://github.com/tuist/tuist/pull/9935))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.126.5...server@1.127.0

## What's Changed in server@1.126.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* simplify branch presence MV migration ([#9956](https://github.com/tuist/tuist/pull/9956))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.126.4...server@1.126.5

## What's Changed in server@1.126.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add allow_nullable_key to branch presence MV ([#9951](https://github.com/tuist/tuist/pull/9951))
* rename duplicate migration to fix Ecto name collision ([#9950](https://github.com/tuist/tuist/pull/9950))
### ⚡ Performance

* recreate branch presence MV with ReplacingMergeTree dedup ([#9954](https://github.com/tuist/tuist/pull/9954))
* use test_case_branch_presence MV for branch/CI queries ([#9948](https://github.com/tuist/tuist/pull/9948))
* add partition hint to get_test_case_run_by_id with project_id ([#9949](https://github.com/tuist/tuist/pull/9949))
* create test_case_branch_presence MV for branch/CI queries ([#9943](https://github.com/tuist/tuist/pull/9943))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.126.3...server@1.126.4

## What's Changed in server@1.126.3<!-- RELEASE NOTES START -->

### ⚡ Performance

* use dashboard count MV for global test case run counts ([#9901](https://github.com/tuist/tuist/pull/9901))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.126.2...server@1.126.3

## What's Changed in server@1.126.2<!-- RELEASE NOTES START -->

### ⚡ Performance

* add dashboard count MV for global test case run counts ([#9923](https://github.com/tuist/tuist/pull/9923))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.126.1...server@1.126.2

## What's Changed in server@1.126.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* make test_case_runs ClickHouse migration idempotent ([#9942](https://github.com/tuist/tuist/pull/9942))
* limit ClickHouse max_threads to reduce CPU contention ([#9941](https://github.com/tuist/tuist/pull/9941))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.126.0...server@1.126.1

## What's Changed in server@1.126.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* buffer ClickHouse inserts for test and cache tables ([#9939](https://github.com/tuist/tuist/pull/9939))
### ⚡ Performance

* optimize test_case_runs ClickHouse query performance ([#9900](https://github.com/tuist/tuist/pull/9900))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.125.1...server@1.126.0

## What's Changed in server@1.125.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix broken marketing links ([#9937](https://github.com/tuist/tuist/pull/9937))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.125.0...server@1.125.1

## What's Changed in server@1.125.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* share configurable repo pool metrics across server and cache ([#9927](https://github.com/tuist/tuist/pull/9927))
* show failed test names in VCS PR comments ([#9929](https://github.com/tuist/tuist/pull/9929))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.124.7...server@1.125.0

## What's Changed in server@1.124.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve noora assets from source and fix trivy version ([#9932](https://github.com/tuist/tuist/pull/9932))
### 📚 Documentation

* update marketing hero copy ([#9933](https://github.com/tuist/tuist/pull/9933))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.124.6...server@1.124.7

## What's Changed in server@1.124.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* reduce Bandit socket idle timeout from 60s to 15s ([#9926](https://github.com/tuist/tuist/pull/9926))
* convert ClickHouse env vars from string to integer and bump pool to 80 ([#9925](https://github.com/tuist/tuist/pull/9925))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.124.5...server@1.124.6

## What's Changed in server@1.124.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* exclude processing builds from VCS PR comments ([#9922](https://github.com/tuist/tuist/pull/9922))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.124.4...server@1.124.5

## What's Changed in server@1.124.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* make /cache/ac endpoint fire-and-forget to eliminate DB reads ([#9908](https://github.com/tuist/tuist/pull/9908))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.124.3...server@1.124.4

## What's Changed in server@1.124.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* drop stale cacheable task counts when replacing build ([#9896](https://github.com/tuist/tuist/pull/9896))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.124.2...server@1.124.3

## What's Changed in server@1.124.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* stop hiding flaky runs when unmarking test as non-flaky ([#9894](https://github.com/tuist/tuist/pull/9894))
* drop temporary build_runs_new table ([#9895](https://github.com/tuist/tuist/pull/9895))
* normalize build storage key to lowercase ([#9893](https://github.com/tuist/tuist/pull/9893))
* handle nil git_ref in post_vcs_pull_request_comment ([#9891](https://github.com/tuist/tuist/pull/9891))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.124.1...server@1.124.2

## What's Changed in server@1.124.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix build_runs deduplication for status transitions ([#9854](https://github.com/tuist/tuist/pull/9854))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.124.0...server@1.124.1

## What's Changed in server@1.124.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* migrate blog markdown rendering from Earmark to MDEx ([#9889](https://github.com/tuist/tuist/pull/9889))
* add Gradle build MCP tools and comparison skill ([#9813](https://github.com/tuist/tuist/pull/9813))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.122.2...server@1.124.0

## What's Changed in server@1.122.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add tests for deprecated /builds routes ([#9887](https://github.com/tuist/tuist/pull/9887))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.122.1...server@1.122.2

## What's Changed in server@1.122.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload CLI session to S3 after command event creation ([#9870](https://github.com/tuist/tuist/pull/9870))
### 🐛 Bug Fixes

* keep legacy /builds routes for backwards compatibility ([#9886](https://github.com/tuist/tuist/pull/9886))
* skip Marketing.Stats polling in dev ([#9881](https://github.com/tuist/tuist/pull/9881))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.121.2...server@1.122.1

## What's Changed in server@1.121.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* preserve card layout on mobile auth pages ([#9869](https://github.com/tuist/tuist/pull/9869))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.121.1...server@1.121.2

## What's Changed in server@1.121.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle unmatched events in SSOSettingsLive ([#9868](https://github.com/tuist/tuist/pull/9868))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.121.0...server@1.121.1

## What's Changed in server@1.121.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* apply environment and time range filters to flaky tests table ([#9841](https://github.com/tuist/tuist/pull/9841))
### 🐛 Bug Fixes

* add missing "Inter Variable" @font-face declarations ([#9862](https://github.com/tuist/tuist/pull/9862))
* dispatch PubSub build events by project type ([#9855](https://github.com/tuist/tuist/pull/9855))
* add alter_sync = 2 to flaky projection migration ([#9859](https://github.com/tuist/tuist/pull/9859))
* always report CAS outputs and improve build run UI ([#9858](https://github.com/tuist/tuist/pull/9858))
* preserve mobile menu state during live counter updates and fix counter width stability ([#9856](https://github.com/tuist/tuist/pull/9856))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.120.0...server@1.121.0

## What's Changed in server@1.120.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add filters to Gradle build runs dashboard ([#9851](https://github.com/tuist/tuist/pull/9851))
### 🐛 Bug Fixes

* readd missing processor webhook secret ([#9857](https://github.com/tuist/tuist/pull/9857))
* preserve flaky flag for quarantined test cases ([#9846](https://github.com/tuist/tuist/pull/9846))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.119.1...server@1.120.0

## What's Changed in server@1.119.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add SSO enforcement option for organizations ([#9832](https://github.com/tuist/tuist/pull/9832))
### 🐛 Bug Fixes

* add SSO enforcement changelog screenshot ([#9847](https://github.com/tuist/tuist/pull/9847))
* add FINAL hint to ClickHouse count queries ([#9822](https://github.com/tuist/tuist/pull/9822))
* coerce cpu_usage_percent to float for ClickHouse ([#9845](https://github.com/tuist/tuist/pull/9845))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.118.4...server@1.119.1

## What's Changed in server@1.118.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* redirect OAuth failures to dedicated error page ([#9839](https://github.com/tuist/tuist/pull/9839))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.118.3...server@1.118.4

## What's Changed in server@1.118.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* stabilize marketing counters ([#9837](https://github.com/tuist/tuist/pull/9837))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.118.2...server@1.118.3

## What's Changed in server@1.118.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* filter processing builds from overview chart ([#9836](https://github.com/tuist/tuist/pull/9836))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.118.1...server@1.118.2

## What's Changed in server@1.118.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* server-side xcactivitylog processing ([#9752](https://github.com/tuist/tuist/pull/9752))
* add counter animation to marketing stats ([#9827](https://github.com/tuist/tuist/pull/9827))
### 🐛 Bug Fixes

* re-add xcode_cache_upload_enabled column to build_runs ([#9834](https://github.com/tuist/tuist/pull/9834))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.117.3...server@1.118.1

## What's Changed in server@1.117.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add bats to CI and upgrade @scalar/api-reference for CVE fix ([#9825](https://github.com/tuist/tuist/pull/9825))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.117.2...server@1.117.3

## What's Changed in server@1.117.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* exclude up_to_date tasks from Gradle Cache tab ([#9824](https://github.com/tuist/tuist/pull/9824))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.117.1...server@1.117.2

## What's Changed in server@1.117.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* reduce metrics cardinality ([#9818](https://github.com/tuist/tuist/pull/9818))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.117.0...server@1.117.1

## What's Changed in server@1.117.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add font smoothing across dashboard and website ([#9791](https://github.com/tuist/tuist/pull/9791))
* remove QA feature ([#9793](https://github.com/tuist/tuist/pull/9793))
* update machine metrics tab to match design ([#9787](https://github.com/tuist/tuist/pull/9787))
### 🐛 Bug Fixes

* fix y-axis label clipping in machine metrics charts ([#9798](https://github.com/tuist/tuist/pull/9798))
* allow MCP session recreation for missing sessions ([#9794](https://github.com/tuist/tuist/pull/9794))
* use TOML array-of-tables syntax in mise.lock ([#9785](https://github.com/tuist/tuist/pull/9785))
* fix machine metrics CSS not being applied ([#9780](https://github.com/tuist/tuist/pull/9780))
### 🚜 Refactor

* migrate MCP implementation from anubis_mcp to emcp ([#9784](https://github.com/tuist/tuist/pull/9784))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.116.0...server@1.117.0

## What's Changed in server@1.116.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add machine metrics seed data for Xcode and Gradle builds



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.115.0...server@1.116.0

## What's Changed in server@1.115.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track machine metrics ([#9760](https://github.com/tuist/tuist/pull/9760))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.114.2...server@1.115.0

## What's Changed in server@1.114.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* attribute Gradle builds to authenticated user ([#9776](https://github.com/tuist/tuist/pull/9776))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.114.1...server@1.114.2

## What's Changed in server@1.114.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* truncate requested tasks column to first two entries ([#9774](https://github.com/tuist/tuist/pull/9774))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.114.0...server@1.114.1

## What's Changed in server@1.114.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add comparison primitives for MCP, API, and agent skills ([#9732](https://github.com/tuist/tuist/pull/9732))
* track requested tasks in Gradle builds ([#9764](https://github.com/tuist/tuist/pull/9764))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.112.1...server@1.114.0

## What's Changed in server@1.112.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* dashboard css fixes ([#9695](https://github.com/tuist/tuist/pull/9695))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.112.0...server@1.112.1

## What's Changed in server@1.112.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* track cache endpoint in analytics events ([#9696](https://github.com/tuist/tuist/pull/9696))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.111.0...server@1.112.0

## What's Changed in server@1.111.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve test cases search UX with skeleton loading ([#9733](https://github.com/tuist/tuist/pull/9733))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.110.5...server@1.111.0

## What's Changed in server@1.110.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* resolve PR head SHA before creating check runs ([#9750](https://github.com/tuist/tuist/pull/9750))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.110.4...server@1.110.5

## What's Changed in server@1.110.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* customer og images ([#9748](https://github.com/tuist/tuist/pull/9748))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.110.3...server@1.110.4

## What's Changed in server@1.110.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* delegate select_widget event to child live view modules ([#9747](https://github.com/tuist/tuist/pull/9747))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.110.2...server@1.110.3

## What's Changed in server@1.110.2<!-- RELEASE NOTES START -->

### ⚡ Performance

* add secondary indexes to command_events_by_ran_at MV ([#9739](https://github.com/tuist/tuist/pull/9739))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.110.1...server@1.110.2

## What's Changed in server@1.110.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent LiveView path params from leaking into query strings ([#9735](https://github.com/tuist/tuist/pull/9735))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.110.0...server@1.110.1

## What's Changed in server@1.110.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add bundle size threshold check runs for PRs ([#9707](https://github.com/tuist/tuist/pull/9707))
### ⚡ Performance

* pre-aggregate cas_events with daily stats MV ([#9736](https://github.com/tuist/tuist/pull/9736))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.109.2...server@1.110.0

## What's Changed in server@1.109.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix asyncresult nil access ([#9737](https://github.com/tuist/tuist/pull/9737))
* use correct query param key for test cases environment selector ([#9734](https://github.com/tuist/tuist/pull/9734))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.109.0...server@1.109.2

## What's Changed in server@1.109.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* load dashboard analytics asynchronously ([#9703](https://github.com/tuist/tuist/pull/9703))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.108.3...server@1.109.0

## What's Changed in server@1.108.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* migrate to anubis_mcp and fix MCP SSE hang ([#9716](https://github.com/tuist/tuist/pull/9716))
* grant default scopes to OAuth tokens for user sessions ([#9728](https://github.com/tuist/tuist/pull/9728))
* fix flaky overview live empty states test ([#9727](https://github.com/tuist/tuist/pull/9727))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.108.2...server@1.108.3

## What's Changed in server@1.108.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* restore scrollable dropdowns in integrations connection modal ([#9726](https://github.com/tuist/tuist/pull/9726))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.108.1...server@1.108.2

## What's Changed in server@1.108.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* group test attachments by repetition ([#9714](https://github.com/tuist/tuist/pull/9714))
### 🐛 Bug Fixes

* include org projects for OAuth-authenticated users ([#9724](https://github.com/tuist/tuist/pull/9724))
* add missing font for gradle test-runs chart label and rename android project ([#9680](https://github.com/tuist/tuist/pull/9680))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.107.9...server@1.108.1

## What's Changed in server@1.107.9<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* propagate cross-run flakiness to test_runs record ([#9719](https://github.com/tuist/tuist/pull/9719))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.107.8...server@1.107.9

## What's Changed in server@1.107.8<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* adjust chart grid left margin for large y-axis labels ([#9715](https://github.com/tuist/tuist/pull/9715))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.107.7...server@1.107.8

## What's Changed in server@1.107.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* pre-aggregate test_case_runs analytics with AggregatingMergeTree ([#9713](https://github.com/tuist/tuist/pull/9713))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.107.6...server@1.107.7

## What's Changed in server@1.107.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bump noora to 0.70.0 ([#9712](https://github.com/tuist/tuist/pull/9712))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.107.5...server@1.107.6

## What's Changed in server@1.107.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* optimize test_case_runs analytics with materialized view ([#9710](https://github.com/tuist/tuist/pull/9710))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.107.4...server@1.107.5

## What's Changed in server@1.107.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bump noora to 0.69.0 ([#9709](https://github.com/tuist/tuist/pull/9709))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.107.3...server@1.107.4

## What's Changed in server@1.107.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* switch ClickHouse from asdf to github backend in mise ([#9700](https://github.com/tuist/tuist/pull/9700))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.107.2...server@1.107.3

## What's Changed in server@1.107.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* include Gradle builds in VCS PR comment ([#9697](https://github.com/tuist/tuist/pull/9697))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.107.1...server@1.107.2

## What's Changed in server@1.107.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add mcp OAuth scope for read-only MCP access ([#9670](https://github.com/tuist/tuist/pull/9670))
* blog post with Tuist now supports Gradle ([#9669](https://github.com/tuist/tuist/pull/9669))
### 🐛 Bug Fixes

* enqueue VCS PR comment from Gradle build and test endpoints ([#9690](https://github.com/tuist/tuist/pull/9690))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.106.1...server@1.107.1

## What's Changed in server@1.106.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add project_id to branch_ci projection for faster DISTINCT query ([#9684](https://github.com/tuist/tuist/pull/9684))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.106.0...server@1.106.1

## What's Changed in server@1.106.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* upload and display all test attachments from xcresult bundles ([#9630](https://github.com/tuist/tuist/pull/9630))
### 🐛 Bug Fixes

* add IF NOT EXISTS to ClickHouse MV migration for concurrent safety ([#9682](https://github.com/tuist/tuist/pull/9682))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.105.1...server@1.106.0

## What's Changed in server@1.105.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* optimize command_events_by_ran_at sort key for faster pagination ([#9675](https://github.com/tuist/tuist/pull/9675))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.105.0...server@1.105.1

## What's Changed in server@1.105.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* load overview analytics asynchronously ([#9623](https://github.com/tuist/tuist/pull/9623))
* PR preview environments with local ClickHouse ([#9640](https://github.com/tuist/tuist/pull/9640))
* show public project CTA banner on tuist/android dashboard ([#9659](https://github.com/tuist/tuist/pull/9659))
### 🐛 Bug Fixes

* optimize test_case_run lookup with UUIDv7 partition pruning ([#9668](https://github.com/tuist/tuist/pull/9668))
* use x-forwarded-proto for MCP OAuth metadata URLs ([#9663](https://github.com/tuist/tuist/pull/9663))
* add partition pruning to xcode_targets queries ([#9658](https://github.com/tuist/tuist/pull/9658))
### 🚜 Refactor

* remove registry ([#9538](https://github.com/tuist/tuist/pull/9538))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.103.2...server@1.105.0

## What's Changed in server@1.103.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* scope test_case_runs new-test query by project_id ([#9656](https://github.com/tuist/tuist/pull/9656))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.103.1...server@1.103.2

## What's Changed in server@1.103.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add environment filter to alert rules ([#9639](https://github.com/tuist/tuist/pull/9639))
* add test case run detail page ([#9633](https://github.com/tuist/tuist/pull/9633))
* add account/project handle context to logs and traces ([#9618](https://github.com/tuist/tuist/pull/9618))
* migrate MCP to Hermes components and streamable HTTP ([#9441](https://github.com/tuist/tuist/pull/9441))
* add self-serve SSO settings page ([#9600](https://github.com/tuist/tuist/pull/9600))
### 🐛 Bug Fixes

* eliminate test_cases self-JOIN queries causing 86 TiB read egress ([#9655](https://github.com/tuist/tuist/pull/9655))
* use alter_sync for ClickHouse projection migration ([#9634](https://github.com/tuist/tuist/pull/9634))
* fix ClickHouse projection migration race condition ([#9632](https://github.com/tuist/tuist/pull/9632))
* add command_events_by_ran_at materialized view for fast pagination ([#9621](https://github.com/tuist/tuist/pull/9621))
* use deep link for Android preview Run button ([#9620](https://github.com/tuist/tuist/pull/9620))
* improve command_events delete performance and correctness ([#9611](https://github.com/tuist/tuist/pull/9611))
* fix build run breakdown pagination showing stale data ([#9613](https://github.com/tuist/tuist/pull/9613))
* fix slow test_case_runs analytics and branch CI projection queries ([#9612](https://github.com/tuist/tuist/pull/9612))
* delay VCS comment worker to avoid ClickHouse buffer race condition ([#9610](https://github.com/tuist/tuist/pull/9610))
* change auto-quarantine flaky tests default to false ([#9608](https://github.com/tuist/tuist/pull/9608))
* Fix login slowness on Safari iOS ([#9599](https://github.com/tuist/tuist/pull/9599))
* speed up command_events queries sorted by duration and hit_rate ([#9595](https://github.com/tuist/tuist/pull/9595))
* remove MODIFY COLUMN from ClickHouse migration ([#9593](https://github.com/tuist/tuist/pull/9593))
* split DROP PROJECTION and MODIFY COLUMN into separate ClickHouse migrations ([#9592](https://github.com/tuist/tuist/pull/9592))
* add mutations_sync to DROP PROJECTION in ClickHouse migration ([#9589](https://github.com/tuist/tuist/pull/9589))
* remove synchronous DELETE from ClickHouse migration to avoid deploy timeout ([#9586](https://github.com/tuist/tuist/pull/9586))
* fix ClickHouse migration for non-nullable test_case_runs columns ([#9582](https://github.com/tuist/tuist/pull/9582))
* wait for pending ClickHouse mutations before altering test_case_runs ([#9579](https://github.com/tuist/tuist/pull/9579))
### ⚡ Performance

* add proj_by_id projection to test_case_runs for fast id lookups ([#9624](https://github.com/tuist/tuist/pull/9624))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.102.5...server@1.103.1

## What's Changed in server@1.102.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* make test_case_runs project_id and ran_at non-nullable to fix projection perf ([#9576](https://github.com/tuist/tuist/pull/9576))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.102.4...server@1.102.5

## What's Changed in server@1.102.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* hide Operations button from non-ops users in account dropdown ([#9577](https://github.com/tuist/tuist/pull/9577))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.102.3...server@1.102.4

## What's Changed in server@1.102.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix failing ClickHouse migration for test_case_runs projections ([#9572](https://github.com/tuist/tuist/pull/9572))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.102.2...server@1.102.3

## What's Changed in server@1.102.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* make MATERIALIZE mutations synchronous to prevent migration failures ([#9571](https://github.com/tuist/tuist/pull/9571))
* optimize slow test case runs listing query ([#9566](https://github.com/tuist/tuist/pull/9566))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.102.1...server@1.102.2

## What's Changed in server@1.102.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* deduplicate first_run test case events ([#9563](https://github.com/tuist/tuist/pull/9563))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.102.0...server@1.102.1

## What's Changed in server@1.102.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add scheme and app_bundle_id filters to alert rules ([#9558](https://github.com/tuist/tuist/pull/9558))
### 🐛 Bug Fixes

* optimize slow test_case_runs ClickHouse queries ([#9561](https://github.com/tuist/tuist/pull/9561))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.101.2...server@1.102.0

## What's Changed in server@1.101.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* scope test_case_runs list endpoints by project_id ([#9559](https://github.com/tuist/tuist/pull/9559))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.101.1...server@1.101.2

## What's Changed in server@1.101.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* Android APK previews with cross-platform share and run ([#9509](https://github.com/tuist/tuist/pull/9509))
### 🐛 Bug Fixes

* show Previews sidebar item for Gradle projects ([#9544](https://github.com/tuist/tuist/pull/9544))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.100.0...server@1.101.1

## What's Changed in server@1.100.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Gradle test quarantine support ([#9493](https://github.com/tuist/tuist/pull/9493))
* add Android bundle support (AAB + APK) ([#9506](https://github.com/tuist/tuist/pull/9506))
* add database-backed cache endpoint management with ops page ([#9449](https://github.com/tuist/tuist/pull/9449))
* add Gradle test insights support ([#9477](https://github.com/tuist/tuist/pull/9477))
* add blog post announcing Linux CLI support ([#9482](https://github.com/tuist/tuist/pull/9482))
* add Builds and Build Runs pages for Gradle ([#9469](https://github.com/tuist/tuist/pull/9469))
* add bundle size alert rule category ([#9478](https://github.com/tuist/tuist/pull/9478))
* crash stack traces with formatted frames, attachments, and download URLs ([#9436](https://github.com/tuist/tuist/pull/9436))
* add build system badge to project cards ([#9472](https://github.com/tuist/tuist/pull/9472))
### 🐛 Bug Fixes

* upgrade ajv to 8.18.0 to fix CVE-2025-69873 ([#9517](https://github.com/tuist/tuist/pull/9517))
* handle unexpected metric in bundle_size_metric_label ([#9496](https://github.com/tuist/tuist/pull/9496))
* charts overflow in overview page ([#9489](https://github.com/tuist/tuist/pull/9489))
* fall back to best compatible manifest in registry ([#9480](https://github.com/tuist/tuist/pull/9480))
* handle nil current_user in organizations index endpoint ([#9448](https://github.com/tuist/tuist/pull/9448))
* tos positioning and background ([#9444](https://github.com/tuist/tuist/pull/9444))
* add service_namespace label to Loki log handler ([#9438](https://github.com/tuist/tuist/pull/9438))
* validate UUID format in get_test before querying ([#9388](https://github.com/tuist/tuist/pull/9388))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.97.0...server@1.100.0

## What's Changed in server@1.97.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Gradle build system support to dashboard ([#9420](https://github.com/tuist/tuist/pull/9420))
* add terms of service and privacy policy links ([#9261](https://github.com/tuist/tuist/pull/9261))
### 🐛 Bug Fixes

* widget cards stacking ([#9421](https://github.com/tuist/tuist/pull/9421))
* backfill missing unquarantined events ([#9412](https://github.com/tuist/tuist/pull/9412))
### 🚜 Refactor

* migrate build_runs to Clickhouse ([#9355](https://github.com/tuist/tuist/pull/9355))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.95.0...server@1.97.0

## What's Changed in server@1.95.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add request ID to traces and logs ([#9409](https://github.com/tuist/tuist/pull/9409))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.94.0...server@1.95.0

## What's Changed in server@1.94.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test case show and run commands with fix-flaky-tests skill ([#9379](https://github.com/tuist/tuist/pull/9379))
* add Gradle build insights and cache analytics ([#9341](https://github.com/tuist/tuist/pull/9341))
* add log forwarding to Loki and additional OTEL traces ([#9358](https://github.com/tuist/tuist/pull/9358))
* add skill for generated projects ([#9353](https://github.com/tuist/tuist/pull/9353))
### 🐛 Bug Fixes

* exclude stale quarantined test cases from list and count ([#9403](https://github.com/tuist/tuist/pull/9403))
* fix Loki logger handler crash from incorrect structured_metadata format ([#9408](https://github.com/tuist/tuist/pull/9408))
* format test controller files ([#9406](https://github.com/tuist/tuist/pull/9406))
* fix Grafana telemetry connectivity and log-trace correlation ([#9404](https://github.com/tuist/tuist/pull/9404))
* drop has_many association fields in insert_all ([#9405](https://github.com/tuist/tuist/pull/9405))
* preserve is_quarantined during test ingestion and fix duplicate quarantined tests ([#9397](https://github.com/tuist/tuist/pull/9397))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.92.0...server@1.94.0

## What's Changed in server@1.92.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* bump minimum supported CLI version to 4.118.1 ([#9392](https://github.com/tuist/tuist/pull/9392))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.91.4...server@1.92.0

## What's Changed in server@1.91.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle nil form in update_alert_rule to prevent BadMapError ([#9380](https://github.com/tuist/tuist/pull/9380))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.91.3...server@1.91.4

## What's Changed in server@1.91.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add authorization checks to VCS connection deletion and invitation revocation ([#9375](https://github.com/tuist/tuist/pull/9375))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.91.2...server@1.91.3

## What's Changed in server@1.91.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add authorization checks to alert rule update and delete handlers (hotfix) ([#9374](https://github.com/tuist/tuist/pull/9374))
* add retry logic to OIDC authentication flow ([#9365](https://github.com/tuist/tuist/pull/9365))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.91.0...server@1.91.2

## What's Changed in server@1.91.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* update features section on landing page ([#9351](https://github.com/tuist/tuist/pull/9351))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.90.4...server@1.91.0

## What's Changed in server@1.90.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add create action to build and test authorization objects ([#9347](https://github.com/tuist/tuist/pull/9347))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.90.3...server@1.90.4

## What's Changed in server@1.90.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* make database username and password optional in dev config ([#9343](https://github.com/tuist/tuist/pull/9343))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.90.2...server@1.90.3

## What's Changed in server@1.90.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add missing fields to runs, builds, and generations API endpoints ([#9339](https://github.com/tuist/tuist/pull/9339))
### 🚜 Refactor

* split Tuist.Runs into Tuist.Builds and Tuist.Tests ([#9332](https://github.com/tuist/tuist/pull/9332))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.90.0...server@1.90.2

## What's Changed in server@1.90.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Gradle build cache support ([#9041](https://github.com/tuist/tuist/pull/9041))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.89.0...server@1.90.0

## What's Changed in server@1.89.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add custom metadata and tags to build runs ([#9310](https://github.com/tuist/tuist/pull/9310))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.88.0...server@1.89.0

## What's Changed in server@1.88.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add PR links to changelog page ([#9305](https://github.com/tuist/tuist/pull/9305))
### 🐛 Bug Fixes

* handle webhook body read timeouts ([#9327](https://github.com/tuist/tuist/pull/9327))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.87.2...server@1.88.0

## What's Changed in server@1.87.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* prevent inline code from wrapping mid-word ([#9325](https://github.com/tuist/tuist/pull/9325))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.87.1...server@1.87.2

## What's Changed in server@1.87.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* filter NoRouteError in Sentry events ([#9320](https://github.com/tuist/tuist/pull/9320))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.87.0...server@1.87.1

## What's Changed in server@1.87.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add generations and cache runs API endpoints and CLI commands ([#9277](https://github.com/tuist/tuist/pull/9277))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.86.2...server@1.87.0

## What's Changed in server@1.86.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use explicit query in get_build to avoid MultipleResultsError ([#9299](https://github.com/tuist/tuist/pull/9299))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.86.1...server@1.86.2

## What's Changed in server@1.86.1<!-- RELEASE NOTES START -->

### ⚡ Performance

* optimize xcode_targets selective_testing queries ([#9303](https://github.com/tuist/tuist/pull/9303))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.86.0...server@1.86.1

## What's Changed in server@1.86.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* include subhashes for the Module Cache tab for a test run ([#9230](https://github.com/tuist/tuist/pull/9230))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.85.1...server@1.86.0

## What's Changed in server@1.85.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove clickhouse pid file ([#9223](https://github.com/tuist/tuist/pull/9223))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.85.0...server@1.85.1

## What's Changed in server@1.85.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Quarantined Tests page with analytics and filtering ([#9245](https://github.com/tuist/tuist/pull/9245))
### 🐛 Bug Fixes

* correct analytics-environment query for test runs analytics ([#9259](https://github.com/tuist/tuist/pull/9259))
* disable link unfurling in Slack messages ([#9283](https://github.com/tuist/tuist/pull/9283))
### 📚 Documentation

* add flaky tests blog post ([#9241](https://github.com/tuist/tuist/pull/9241))
### ⚡ Performance

* improve static asset loading and self-host fonts ([#9285](https://github.com/tuist/tuist/pull/9285))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.84.2...server@1.85.0

## What's Changed in server@1.84.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* increase request body size limit to 50MB ([#9273](https://github.com/tuist/tuist/pull/9273))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.84.1...server@1.84.2

## What's Changed in server@1.84.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* track releases in Sentry using commit SHA ([#9263](https://github.com/tuist/tuist/pull/9263))
### 🐛 Bug Fixes

* fix Sentry event filtering for non-exception events ([#9270](https://github.com/tuist/tuist/pull/9270))
* enforce authorization for deleting public previews ([#9265](https://github.com/tuist/tuist/pull/9265))
* increase read timeout for GitHub webhooks ([#9262](https://github.com/tuist/tuist/pull/9262))
* use TUIST_ prefix for SECRET_KEY_BASE env var ([#9251](https://github.com/tuist/tuist/pull/9251))
* fix Sentry event filter signature ([#9255](https://github.com/tuist/tuist/pull/9255))
### 🚜 Refactor

* update preview access copy ([#9266](https://github.com/tuist/tuist/pull/9266))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.83.0...server@1.84.1

## What's Changed in server@1.83.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* replace AppSignal with Sentry for error tracking ([#9249](https://github.com/tuist/tuist/pull/9249))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.82.1...server@1.83.0

## What's Changed in server@1.82.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* ensure preview artifacts exist before streaming ([#9242](https://github.com/tuist/tuist/pull/9242))
* detect client disconnect in Bandit ensure_completed ([#9244](https://github.com/tuist/tuist/pull/9244))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.82.0...server@1.82.1

## What's Changed in server@1.82.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test case history timeline ([#9232](https://github.com/tuist/tuist/pull/9232))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.81.1...server@1.82.0

## What's Changed in server@1.81.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add test quarantine and automations settings ([#9175](https://github.com/tuist/tuist/pull/9175))
* add filter by type in bundle file breakdown ([#9217](https://github.com/tuist/tuist/pull/9217))
### 🐛 Bug Fixes

* improve body read timeout handling and client disconnect detection ([#9202](https://github.com/tuist/tuist/pull/9202))
* handle missing page in marketing controller gracefully ([#9227](https://github.com/tuist/tuist/pull/9227))
### ⚡ Performance

* add projection to optimize test case runs analytics queries ([#9237](https://github.com/tuist/tuist/pull/9237))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.79.8...server@1.81.1

## What's Changed in server@1.79.8<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use user ID instead of account ID in ran_by filter ([#9220](https://github.com/tuist/tuist/pull/9220))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.79.7...server@1.79.8

## What's Changed in server@1.79.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* reset pagination when binary cache filters change ([#9216](https://github.com/tuist/tuist/pull/9216))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.79.6...server@1.79.7

## What's Changed in server@1.79.6<!-- RELEASE NOTES START -->

### 🚜 Refactor

* move custom credo checks to TuistCommon ([#9211](https://github.com/tuist/tuist/pull/9211))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.79.5...server@1.79.6

## What's Changed in server@1.79.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* improve Slack OAuth error message for expired tokens ([#9195](https://github.com/tuist/tuist/pull/9195))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.79.4...server@1.79.5

## What's Changed in server@1.79.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip private submodules for registry packages ([#9183](https://github.com/tuist/tuist/pull/9183))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.79.3...server@1.79.4

## What's Changed in server@1.79.3<!-- RELEASE NOTES START -->

### ⚡ Performance

* add ClickHouse projection to optimize branch CI query ([#9190](https://github.com/tuist/tuist/pull/9190))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.79.2...server@1.79.3

## What's Changed in server@1.79.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix aws miss ([#9182](https://github.com/tuist/tuist/pull/9182))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.79.1...server@1.79.2

## What's Changed in server@1.79.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle large test case lists in ClickHouse queries ([#9181](https://github.com/tuist/tuist/pull/9181))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.79.0...server@1.79.1

## What's Changed in server@1.79.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add "New" trait to test case runs ([#9162](https://github.com/tuist/tuist/pull/9162))
### 🚜 Refactor

* replace FINAL hints with subquery deduplication in runs module ([#9173](https://github.com/tuist/tuist/pull/9173))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.78.1...server@1.79.0

## What's Changed in server@1.78.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle invalid Flop cursor in cache runs pagination ([#9170](https://github.com/tuist/tuist/pull/9170))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.78.0...server@1.78.1

## What's Changed in server@1.78.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add flaky runs analytics chart to flaky tests page ([#9165](https://github.com/tuist/tuist/pull/9165))
* add CTA banner for unauthenticated users on tuist/tuist project ([#9163](https://github.com/tuist/tuist/pull/9163))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.77.1...server@1.78.0

## What's Changed in server@1.77.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add flaky tests section to VCS PR comments ([#9161](https://github.com/tuist/tuist/pull/9161))
### ⚡ Performance

* optimize module cache page query with 14-day filter ([#9158](https://github.com/tuist/tuist/pull/9158))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.76.0...server@1.77.1

## What's Changed in server@1.76.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add flaky test alert rules ([#9133](https://github.com/tuist/tuist/pull/9133))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.75.0...server@1.76.0

## What's Changed in server@1.75.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add configurable data volumes to seeds.exs with optimized performance ([#9144](https://github.com/tuist/tuist/pull/9144))
### 🐛 Bug Fixes

* add ClickHouseRepo to ecto_repos for AppSignal analytics ([#9159](https://github.com/tuist/tuist/pull/9159))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.74.4...server@1.75.0

## What's Changed in server@1.74.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove non-existent us-east canary node ([#9145](https://github.com/tuist/tuist/pull/9145))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.74.3...server@1.74.4

## What's Changed in server@1.74.3<!-- RELEASE NOTES START -->

### 🧪 Testing

* add regression test for avatar with consecutive delimiters ([#9143](https://github.com/tuist/tuist/pull/9143))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.74.2...server@1.74.3

## What's Changed in server@1.74.2<!-- RELEASE NOTES START -->

### ⚡ Performance

* remove FINAL hint from TestCaseRun queries ([#9142](https://github.com/tuist/tuist/pull/9142))
* add projection to optimize test_case_runs queries ([#9140](https://github.com/tuist/tuist/pull/9140))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.74.0...server@1.74.2

## What's Changed in server@1.74.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* enable custom cache endpoints ([#9134](https://github.com/tuist/tuist/pull/9134))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.73.1...server@1.74.0

## What's Changed in server@1.73.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for flaky tests detection ([#9098](https://github.com/tuist/tuist/pull/9098))
### 🐛 Bug Fixes

* fix ClickHouse bloom_filter index migration syntax ([#9138](https://github.com/tuist/tuist/pull/9138))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.72.1...server@1.73.1

## What's Changed in server@1.72.1<!-- RELEASE NOTES START -->

### 🚜 Refactor

* move sampling plug to TuistCommon ([#9131](https://github.com/tuist/tuist/pull/9131))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.72.0...server@1.72.1

## What's Changed in server@1.72.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add AppSignal sampling for CacheController requests ([#9130](https://github.com/tuist/tuist/pull/9130))
* upgrade Gettext to 1.0 for faster compilation ([#9119](https://github.com/tuist/tuist/pull/9119))
### 🚜 Refactor

* remove support for numeric command event ids ([#9103](https://github.com/tuist/tuist/pull/9103))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.70.1...server@1.72.0

## What's Changed in server@1.70.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add email format validation during user registration ([#9090](https://github.com/tuist/tuist/pull/9090))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.70.0...server@1.70.1

## What's Changed in server@1.70.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add empty state for Xcode cache page ([#9112](https://github.com/tuist/tuist/pull/9112))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.69.0...server@1.70.0

## What's Changed in server@1.69.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* show deprecation notice for CLI < 4.56.1 ([#9110](https://github.com/tuist/tuist/pull/9110))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.68.1...server@1.69.0

## What's Changed in server@1.68.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix chart overflow ([#9109](https://github.com/tuist/tuist/pull/9109))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.68.0...server@1.68.1

## What's Changed in server@1.68.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* implement cache endpoint setting design ([#9104](https://github.com/tuist/tuist/pull/9104))
### 🐛 Bug Fixes

* sidebar width ([#9108](https://github.com/tuist/tuist/pull/9108))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.67.0...server@1.68.0

## What's Changed in server@1.67.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* make sidebar sticky while scrolling ([#9101](https://github.com/tuist/tuist/pull/9101))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.66.3...server@1.67.0

## What's Changed in server@1.66.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip Slack reports for projects with nil timezone ([#9100](https://github.com/tuist/tuist/pull/9100))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.66.2...server@1.66.3

## What's Changed in server@1.66.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* close modal after updating alert rule ([#9095](https://github.com/tuist/tuist/pull/9095))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.66.1...server@1.66.2

## What's Changed in server@1.66.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix flaky race condition test in runs controller ([#9088](https://github.com/tuist/tuist/pull/9088))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.66.0...server@1.66.1

## What's Changed in server@1.66.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add og images to public pages of tuist ([#9079](https://github.com/tuist/tuist/pull/9079))
### 🐛 Bug Fixes

* fixed failing CI ([#9085](https://github.com/tuist/tuist/pull/9085))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.65.0...server@1.66.0

## What's Changed in server@1.65.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Slack alerts for metric regressions ([#9055](https://github.com/tuist/tuist/pull/9055))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.64.2...server@1.65.0

## What's Changed in server@1.64.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* marketing handbook links ([#9074](https://github.com/tuist/tuist/pull/9074))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.64.1...server@1.64.2

## What's Changed in server@1.64.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* extract common code into shared library ([#9046](https://github.com/tuist/tuist/pull/9046))
### 🐛 Bug Fixes

* update AI marketing copy for better grammar ([#9071](https://github.com/tuist/tuist/pull/9071))
* replace Slack channel dropdown with native OAuth picker ([#9068](https://github.com/tuist/tuist/pull/9068))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.63.5...server@1.64.1

## What's Changed in server@1.63.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* filter out non-semantic versions in registry ingestion ([#9056](https://github.com/tuist/tuist/pull/9056))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.63.4...server@1.63.5

## What's Changed in server@1.63.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bump noora ([#9060](https://github.com/tuist/tuist/pull/9060))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.63.3...server@1.63.4

## What's Changed in server@1.63.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* improve Slack report formatting and bundle comparison ([#9057](https://github.com/tuist/tuist/pull/9057))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.63.2...server@1.63.3

## What's Changed in server@1.63.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle invalid page parameter in blog pagination ([#9053](https://github.com/tuist/tuist/pull/9053))
* use inclusive upper bounds for Prometheus histogram buckets ([#9052](https://github.com/tuist/tuist/pull/9052))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.63.1...server@1.63.2

## What's Changed in server@1.63.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use valid AppSignal sample data key for request context ([#9051](https://github.com/tuist/tuist/pull/9051))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.63.0...server@1.63.1

## What's Changed in server@1.63.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* use checkbox dropdown for selecting slack report days ([#9049](https://github.com/tuist/tuist/pull/9049))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.62.2...server@1.63.0

## What's Changed in server@1.62.2<!-- RELEASE NOTES START -->

### 🚜 Refactor

* remove dual-s3 config with feature flag ([#9011](https://github.com/tuist/tuist/pull/9011))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.62.1...server@1.62.2

## What's Changed in server@1.62.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't log http timeouts ([#9040](https://github.com/tuist/tuist/pull/9040))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.62.0...server@1.62.1

## What's Changed in server@1.62.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Slack integration for project analytics reports ([#9015](https://github.com/tuist/tuist/pull/9015))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.61.0...server@1.62.0

## What's Changed in server@1.61.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* custom cache endpoints ([#8980](https://github.com/tuist/tuist/pull/8980))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.60.0...server@1.61.0

## What's Changed in server@1.60.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* show cache endpoint ([#8978](https://github.com/tuist/tuist/pull/8978))
* Dashboard translation update from Weblate ([#9021](https://github.com/tuist/tuist/pull/9021))
* Marketing translation update from Weblate ([#9019](https://github.com/tuist/tuist/pull/9019))
* Marketing translation update from Weblate ([#8975](https://github.com/tuist/tuist/pull/8975))
### 🐛 Bug Fixes

* handle race condition in build run creation ([#8952](https://github.com/tuist/tuist/pull/8952))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.59.5...server@1.60.0

## What's Changed in server@1.59.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* update mailgun api key ([#9008](https://github.com/tuist/tuist/pull/9008))
* use builtin datetime truncation ([#8995](https://github.com/tuist/tuist/pull/8995))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.59.3...server@1.59.5

## What's Changed in server@1.59.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* truncate DateTime microseconds for ClickHouse compatibility ([#8994](https://github.com/tuist/tuist/pull/8994))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.59.2...server@1.59.3

## What's Changed in server@1.59.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* changelog width on mobile ([#8992](https://github.com/tuist/tuist/pull/8992))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.59.1...server@1.59.2

## What's Changed in server@1.59.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* return only latest preview with the source supported platform ([#8989](https://github.com/tuist/tuist/pull/8989))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.59.0...server@1.59.1

## What's Changed in server@1.59.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* new date picker ([#8964](https://github.com/tuist/tuist/pull/8964))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.58.0...server@1.59.0

## What's Changed in server@1.58.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8968](https://github.com/tuist/tuist/pull/8968))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.57.1...server@1.58.0

## What's Changed in server@1.57.1<!-- RELEASE NOTES START -->

### 🚜 Refactor

* consolidate on UUIDv7 ([#8969](https://github.com/tuist/tuist/pull/8969))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.57.0...server@1.57.1

## What's Changed in server@1.57.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8898](https://github.com/tuist/tuist/pull/8898))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.56.6...server@1.57.0

## What's Changed in server@1.56.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove analytics from cache download/upload paths ([#8960](https://github.com/tuist/tuist/pull/8960))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.56.5...server@1.56.6

## What's Changed in server@1.56.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* set AppSignal attribution tags at the right time ([#8951](https://github.com/tuist/tuist/pull/8951))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.56.4...server@1.56.5

## What's Changed in server@1.56.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove unique constraint from previews track migration ([#8955](https://github.com/tuist/tuist/pull/8955))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.56.3...server@1.56.4

## What's Changed in server@1.56.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove localization from /download link ([#8945](https://github.com/tuist/tuist/pull/8945))
* handle GitHub 403s when syncing packages ([#8948](https://github.com/tuist/tuist/pull/8948))
* do not raise when Slack is not configured ([#8947](https://github.com/tuist/tuist/pull/8947))
* force HTTPS clones for submodules ([#8949](https://github.com/tuist/tuist/pull/8949))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.56.2...server@1.56.3

## What's Changed in server@1.56.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use tags instead of custom_data for AppSignal attribution ([#8932](https://github.com/tuist/tuist/pull/8932))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.56.1...server@1.56.2

## What's Changed in server@1.56.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* flatten AppSignal custom data for link templates ([#8928](https://github.com/tuist/tuist/pull/8928))
* add frame-ancestors CSP directive to prevent clickjacking ([#8925](https://github.com/tuist/tuist/pull/8925))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.56.0...server@1.56.1

## What's Changed in server@1.56.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add RequestContextPlug for early request path capture ([#8915](https://github.com/tuist/tuist/pull/8915))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.55.3...server@1.56.0

## What's Changed in server@1.55.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* make format script fail on check errors ([#8918](https://github.com/tuist/tuist/pull/8918))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.55.2...server@1.55.3

## What's Changed in server@1.55.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle personal accounts in TestCaseLive ([#8917](https://github.com/tuist/tuist/pull/8917))
* validate sort_by parameter in TestCasesLive ([#8919](https://github.com/tuist/tuist/pull/8919))
* use custom_data key for AppSignal sample data ([#8913](https://github.com/tuist/tuist/pull/8913))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.55.1...server@1.55.2

## What's Changed in server@1.55.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove localized_href from API docs link ([#8907](https://github.com/tuist/tuist/pull/8907))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.55.0...server@1.55.1

## What's Changed in server@1.55.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add AppSignal attribution plug ([#8821](https://github.com/tuist/tuist/pull/8821))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.54.1...server@1.55.0

## What's Changed in server@1.54.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* Prepare dashboard content for localization ([#8860](https://github.com/tuist/tuist/pull/8860))
### 🐛 Bug Fixes

* Remove Bumble logo from marketing home page ([#8895](https://github.com/tuist/tuist/pull/8895))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.53.0...server@1.54.1

## What's Changed in server@1.53.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8874](https://github.com/tuist/tuist/pull/8874))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.52.3...server@1.53.0

## What's Changed in server@1.52.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* trim whitespace from email and username inputs in forms ([#8885](https://github.com/tuist/tuist/pull/8885))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.52.2...server@1.52.3

## What's Changed in server@1.52.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* scroll top margin for changelog entries ([#8881](https://github.com/tuist/tuist/pull/8881))
* do not report Bandit.TransportError to AppSignal ([#8879](https://github.com/tuist/tuist/pull/8879))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.52.1...server@1.52.2

## What's Changed in server@1.52.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add project:runs:read and project:runs:write scopes ([#8871](https://github.com/tuist/tuist/pull/8871))
### 🐛 Bug Fixes

* pin nodejs ([#8880](https://github.com/tuist/tuist/pull/8880))
* handle AuthenticatedAccount in analytics subject_parameters ([#8876](https://github.com/tuist/tuist/pull/8876))
* link OAuth identity to existing user with same email ([#8863](https://github.com/tuist/tuist/pull/8863))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.51.0...server@1.52.1

## What's Changed in server@1.51.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8837](https://github.com/tuist/tuist/pull/8837))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.50.2...server@1.51.0

## What's Changed in server@1.50.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* inline account tokens bash ([#8856](https://github.com/tuist/tuist/pull/8856))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.50.1...server@1.50.2

## What's Changed in server@1.50.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* registry support of packages with submodules ([#8792](https://github.com/tuist/tuist/pull/8792))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.50.0...server@1.50.1

## What's Changed in server@1.50.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add /api/registry/swift root endpoint returning 200 ([#8839](https://github.com/tuist/tuist/pull/8839))
### 🐛 Bug Fixes

* outdated dependency with a CVE ([#8831](https://github.com/tuist/tuist/pull/8831))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.49.0...server@1.50.0

## What's Changed in server@1.49.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add commit SHA to run detail metadata ([#8853](https://github.com/tuist/tuist/pull/8853))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.48.4...server@1.49.0

## What's Changed in server@1.48.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use ran_at instead of created_at for command_events ordering ([#8851](https://github.com/tuist/tuist/pull/8851))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.48.3...server@1.48.4

## What's Changed in server@1.48.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* disable PostHog in blog iframe pages ([#8850](https://github.com/tuist/tuist/pull/8850))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.48.2...server@1.48.3

## What's Changed in server@1.48.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add missing handle_params/3 callback to ProjectSettingsLive ([#8848](https://github.com/tuist/tuist/pull/8848))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.48.1...server@1.48.2

## What's Changed in server@1.48.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* materialize xcode_targets projection ([#8846](https://github.com/tuist/tuist/pull/8846))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.48.0...server@1.48.1

## What's Changed in server@1.48.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add TTL to xcode tables ([#8844](https://github.com/tuist/tuist/pull/8844))
### 🐛 Bug Fixes

* handle pagination cursor mismatch in LiveView pages ([#8634](https://github.com/tuist/tuist/pull/8634))
* Use Bandit fork to skip body draining on Connection: close ([#8835](https://github.com/tuist/tuist/pull/8835))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.47.2...server@1.48.0

## What's Changed in server@1.47.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* skip projection materialization ([#8845](https://github.com/tuist/tuist/pull/8845))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.47.1...server@1.47.2

## What's Changed in server@1.47.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* optimize slow xcode_targets queries with ClickHouse projection ([#8832](https://github.com/tuist/tuist/pull/8832))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.47.0...server@1.47.1

## What's Changed in server@1.47.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* neutral widgets ([#8789](https://github.com/tuist/tuist/pull/8789))
* Marketing translation update from Weblate ([#8793](https://github.com/tuist/tuist/pull/8793))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.45.0...server@1.47.0

## What's Changed in server@1.45.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for declaring additional Finch pools at runtime using env. variables ([#8833](https://github.com/tuist/tuist/pull/8833))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.44.5...server@1.45.0

## What's Changed in server@1.44.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle invalid repository URLs gracefully in registry identifiers endpoint ([#8829](https://github.com/tuist/tuist/pull/8829))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.44.4...server@1.44.5

## What's Changed in server@1.44.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* centralize Connection: close header for error responses ([#8828](https://github.com/tuist/tuist/pull/8828))
* update billing email ([#8827](https://github.com/tuist/tuist/pull/8827))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.44.3...server@1.44.4

## What's Changed in server@1.44.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* run alter column synchronously ([#8815](https://github.com/tuist/tuist/pull/8815))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.44.2...server@1.44.3

## What's Changed in server@1.44.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* only drop index if it exists ([#8813](https://github.com/tuist/tuist/pull/8813))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.44.1...server@1.44.2

## What's Changed in server@1.44.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* add filter to test runs page ([#8810](https://github.com/tuist/tuist/pull/8810))
### 🐛 Bug Fixes

* navbar padding ([#8801](https://github.com/tuist/tuist/pull/8801))
* filter in test cases ([#8809](https://github.com/tuist/tuist/pull/8809))
* misaligned connected build/test ([#8802](https://github.com/tuist/tuist/pull/8802))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.43.0...server@1.44.1

## What's Changed in server@1.43.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add choosing username when signing up with oauth providers ([#8798](https://github.com/tuist/tuist/pull/8798))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.42.0...server@1.43.0

## What's Changed in server@1.42.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* bump registry limits ([#8791](https://github.com/tuist/tuist/pull/8791))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.41.2...server@1.42.0

## What's Changed in server@1.41.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* increase the number of retries for username ([#8797](https://github.com/tuist/tuist/pull/8797))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.41.1...server@1.41.2

## What's Changed in server@1.41.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle S3/Tigris 404 errors gracefully in storage operations ([#8737](https://github.com/tuist/tuist/pull/8737))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.41.0...server@1.41.1

## What's Changed in server@1.41.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* update Xcode cache icon ([#8788](https://github.com/tuist/tuist/pull/8788))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.40.0...server@1.41.0

## What's Changed in server@1.40.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* tests page ([#8787](https://github.com/tuist/tuist/pull/8787))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.39.0...server@1.40.0

## What's Changed in server@1.39.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* test cases page ([#8774](https://github.com/tuist/tuist/pull/8774))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.38.4...server@1.39.0

## What's Changed in server@1.38.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add revenuecat/purchases-ios-spm to registry denylist ([#8783](https://github.com/tuist/tuist/pull/8783))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.38.3...server@1.38.4

## What's Changed in server@1.38.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't require :type in build insights API to fix a breaking change ([#8780](https://github.com/tuist/tuist/pull/8780))
### 🚜 Refactor

* improve projects in JWT ([#8720](https://github.com/tuist/tuist/pull/8720))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.38.1...server@1.38.3

## What's Changed in server@1.38.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add Connection: close header to cache loader plug ([#8755](https://github.com/tuist/tuist/pull/8755))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.38.0...server@1.38.1

## What's Changed in server@1.38.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add custom S3 storage configuration per account ([#8758](https://github.com/tuist/tuist/pull/8758))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.37.0...server@1.38.0

## What's Changed in server@1.37.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8762](https://github.com/tuist/tuist/pull/8762))
### 🐛 Bug Fixes

* use :text for all oauth_tokens columns ([#8759](https://github.com/tuist/tuist/pull/8759))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.36.2...server@1.37.0

## What's Changed in server@1.36.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* change oauth_tokens state column to text type ([#8757](https://github.com/tuist/tuist/pull/8757))
* use command event ID for result bundle download URL in test run page ([#8756](https://github.com/tuist/tuist/pull/8756))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.36.1...server@1.36.2

## What's Changed in server@1.36.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add Connection: close header to early API rejections ([#8751](https://github.com/tuist/tuist/pull/8751))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.36.0...server@1.36.1

## What's Changed in server@1.36.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8723](https://github.com/tuist/tuist/pull/8723))
### 🐛 Bug Fixes

* test runs query memory limits ([#8748](https://github.com/tuist/tuist/pull/8748))
* handle NaN avg_duration in get_test_run_metrics ([#8747](https://github.com/tuist/tuist/pull/8747))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.35.7...server@1.36.0

## What's Changed in server@1.35.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle nullable fields in test runs backfill migration ([#8741](https://github.com/tuist/tuist/pull/8741))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.35.6...server@1.35.7

## What's Changed in server@1.35.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* backfill migration ([#8738](https://github.com/tuist/tuist/pull/8738))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.35.5...server@1.35.6

## What's Changed in server@1.35.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* internal server error when session expires ([#8735](https://github.com/tuist/tuist/pull/8735))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.35.4...server@1.35.5

## What's Changed in server@1.35.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* validate OAuth state parameter length ([#8734](https://github.com/tuist/tuist/pull/8734))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.35.3...server@1.35.4

## What's Changed in server@1.35.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* blockquote font size ([#8727](https://github.com/tuist/tuist/pull/8727))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.35.2...server@1.35.3

## What's Changed in server@1.35.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* update navbar padding ([#8697](https://github.com/tuist/tuist/pull/8697))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.35.1...server@1.35.2

## What's Changed in server@1.35.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle missing id parameter in blog iframe controller ([#8722](https://github.com/tuist/tuist/pull/8722))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.35.0...server@1.35.1

## What's Changed in server@1.35.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8633](https://github.com/tuist/tuist/pull/8633))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.34.3...server@1.35.0

## What's Changed in server@1.34.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* update og images ([#8696](https://github.com/tuist/tuist/pull/8696))
* remove replacement of product names in mirrored packages in registry ([#8719](https://github.com/tuist/tuist/pull/8719))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.34.2...server@1.34.3

## What's Changed in server@1.34.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Disable Plain's floating button in iframes embedded in blog posts ([#8718](https://github.com/tuist/tuist/pull/8718))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.34.1...server@1.34.2

## What's Changed in server@1.34.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add swift-protobuf to unsupported packages due to submodules ([#8716](https://github.com/tuist/tuist/pull/8716))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.34.0...server@1.34.1

## What's Changed in server@1.34.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add 'From Zero to Many' blog post with interactive visualizations ([#8528](https://github.com/tuist/tuist/pull/8528))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.33.3...server@1.34.0

## What's Changed in server@1.33.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* limit projects encoded in jwt ([#8709](https://github.com/tuist/tuist/pull/8709))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.33.2...server@1.33.3

## What's Changed in server@1.33.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* keep build counts in overview up-to-date ([#8699](https://github.com/tuist/tuist/pull/8699))
* resolve duplicate role creation in add_user_to_organization ([#8702](https://github.com/tuist/tuist/pull/8702))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.33.1...server@1.33.2

## What's Changed in server@1.33.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* module cache hit rate chart unordered dates ([#8691](https://github.com/tuist/tuist/pull/8691))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.33.0...server@1.33.1

## What's Changed in server@1.33.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add S3 CA certificate configuration for air-gapped environments ([#8687](https://github.com/tuist/tuist/pull/8687))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.32.0...server@1.33.0

## What's Changed in server@1.32.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add TUIST_SKIP_DATA_MIGRATION flag ([#8688](https://github.com/tuist/tuist/pull/8688))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.31.2...server@1.32.0

## What's Changed in server@1.31.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* creating organization ([#8679](https://github.com/tuist/tuist/pull/8679))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.31.1...server@1.31.2

## What's Changed in server@1.31.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle non-200 incident responses gracefully ([#8685](https://github.com/tuist/tuist/pull/8685))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.31.0...server@1.31.1

## What's Changed in server@1.31.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* humanize hits and misses value ([#8684](https://github.com/tuist/tuist/pull/8684))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.30.1...server@1.31.0

## What's Changed in server@1.30.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove duplicate Xcode Cache in sidebar ([#8680](https://github.com/tuist/tuist/pull/8680))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.30.0...server@1.30.1

## What's Changed in server@1.30.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* module cache page ([#8666](https://github.com/tuist/tuist/pull/8666))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.29.1...server@1.30.0

## What's Changed in server@1.29.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* overview chart dates order when there are dates with no data ([#8677](https://github.com/tuist/tuist/pull/8677))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.29.0...server@1.29.1

## What's Changed in server@1.29.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Xcode cache overview analytics ([#8652](https://github.com/tuist/tuist/pull/8652))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.28.0...server@1.29.0

## What's Changed in server@1.28.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* manage and remove members in the dashboard ([#8670](https://github.com/tuist/tuist/pull/8670))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.27.0...server@1.28.0

## What's Changed in server@1.27.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add cache hit rate widget ([#8673](https://github.com/tuist/tuist/pull/8673))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.26.0...server@1.27.0

## What's Changed in server@1.26.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add filters to the Compilation Optimizations tab ([#8672](https://github.com/tuist/tuist/pull/8672))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.25.1...server@1.26.0

## What's Changed in server@1.25.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix pricing page CTA not being centered ([#8668](https://github.com/tuist/tuist/pull/8668))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.25.0...server@1.25.1

## What's Changed in server@1.25.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add new blog post about website redesign ([#8571](https://github.com/tuist/tuist/pull/8571))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.24.2...server@1.25.0

## What's Changed in server@1.24.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* make the whole percentile widget dropdown tappable ([#8648](https://github.com/tuist/tuist/pull/8648))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.24.1...server@1.24.2

## What's Changed in server@1.24.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* truncate cas node ([#8645](https://github.com/tuist/tuist/pull/8645))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.24.0...server@1.24.1

## What's Changed in server@1.24.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* show empty state when there's no latency or throughput data ([#8644](https://github.com/tuist/tuist/pull/8644))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.23.0...server@1.24.0

## What's Changed in server@1.23.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8632](https://github.com/tuist/tuist/pull/8632))
### 🐛 Bug Fixes

* handle 404 errors gracefully in Swift package registry ([#8630](https://github.com/tuist/tuist/pull/8630))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.22.0...server@1.23.0

## What's Changed in server@1.22.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8623](https://github.com/tuist/tuist/pull/8623))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.21.0...server@1.22.0

## What's Changed in server@1.21.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8621](https://github.com/tuist/tuist/pull/8621))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.20.0...server@1.21.0

## What's Changed in server@1.20.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8619](https://github.com/tuist/tuist/pull/8619))
### 🐛 Bug Fixes

* Rendering of members fails when the table component tries to access the row key ([#8620](https://github.com/tuist/tuist/pull/8620))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.19.5...server@1.20.0

## What's Changed in server@1.19.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix changelog page's width ([#8617](https://github.com/tuist/tuist/pull/8617))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.19.4...server@1.19.5

## What's Changed in server@1.19.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* label not shown when existing slots for links in dropdown ([#8618](https://github.com/tuist/tuist/pull/8618))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.19.3...server@1.19.4

## What's Changed in server@1.19.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Email & password fields not showing if mailing is not configured ([#8616](https://github.com/tuist/tuist/pull/8616))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.19.2...server@1.19.3

## What's Changed in server@1.19.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* missing labels in dropdowns ([#8615](https://github.com/tuist/tuist/pull/8615))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.19.1...server@1.19.2

## What's Changed in server@1.19.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* validate bundle_id parameter format in bundles API ([#8610](https://github.com/tuist/tuist/pull/8610))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.19.0...server@1.19.1

## What's Changed in server@1.19.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8583](https://github.com/tuist/tuist/pull/8583))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.18.3...server@1.19.0

## What's Changed in server@1.18.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* extract subscription plan regardless of status ([#8592](https://github.com/tuist/tuist/pull/8592))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.18.2...server@1.18.3

## What's Changed in server@1.18.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add GitHub authentication to releases API requests ([#8599](https://github.com/tuist/tuist/pull/8599))
* update dark mode images for empty states ([#8593](https://github.com/tuist/tuist/pull/8593))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.18.0...server@1.18.2

## What's Changed in server@1.18.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* enable Russian locale on marketing site ([#8597](https://github.com/tuist/tuist/pull/8597))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.17.0...server@1.18.0

## What's Changed in server@1.17.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add skip email confirmation for on-premise installations ([#8591](https://github.com/tuist/tuist/pull/8591))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.16.1...server@1.17.0

## What's Changed in server@1.16.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add retry logic with exponential backoff for GitHub API HTTP/2 errors ([#8589](https://github.com/tuist/tuist/pull/8589))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.16.0...server@1.16.1

## What's Changed in server@1.16.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* update mix.exs for new dark mode variables ([#8585](https://github.com/tuist/tuist/pull/8585))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.15.1...server@1.16.0

## What's Changed in server@1.15.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle not_found error in GitHub webhook installation events ([#8580](https://github.com/tuist/tuist/pull/8580))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.15.0...server@1.15.1

## What's Changed in server@1.15.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8554](https://github.com/tuist/tuist/pull/8554))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.14.0...server@1.15.0

## What's Changed in server@1.14.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add English locale files for Weblate integration ([#8582](https://github.com/tuist/tuist/pull/8582))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.13.5...server@1.14.0

## What's Changed in server@1.13.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix highlighted blog post appearing in all posts ([#8577](https://github.com/tuist/tuist/pull/8577))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.13.4...server@1.13.5

## What's Changed in server@1.13.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix animation on faq page ([#8579](https://github.com/tuist/tuist/pull/8579))
* remove blog page title ([#8578](https://github.com/tuist/tuist/pull/8578))
* apply ueberauth host plug to browser_app pipeline for Okta ([#8573](https://github.com/tuist/tuist/pull/8573))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.13.2...server@1.13.4

## What's Changed in server@1.13.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* remove reading time and fix blog images shadows ([#8572](https://github.com/tuist/tuist/pull/8572))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.13.1...server@1.13.2

## What's Changed in server@1.13.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use configured app_url for oauth redirect_uri ([#8569](https://github.com/tuist/tuist/pull/8569))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.13.0...server@1.13.1

## What's Changed in server@1.13.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add filters for bundles ([#8568](https://github.com/tuist/tuist/pull/8568))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.12.2...server@1.13.0

## What's Changed in server@1.12.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* optimize cardinality for http_receive and http_send metrics ([#8567](https://github.com/tuist/tuist/pull/8567))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.12.1...server@1.12.2

## What's Changed in server@1.12.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* reduce HTTP metrics cardinality by removing request_path tag ([#8562](https://github.com/tuist/tuist/pull/8562))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.12.0...server@1.12.1

## What's Changed in server@1.12.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8538](https://github.com/tuist/tuist/pull/8538))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.11.1...server@1.12.0

## What's Changed in server@1.11.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add padding at the bottom of marketing pages ([#8552](https://github.com/tuist/tuist/pull/8552))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.11.0...server@1.11.1

## What's Changed in server@1.11.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add storage region selection ([#8551](https://github.com/tuist/tuist/pull/8551))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.10.3...server@1.11.0

## What's Changed in server@1.10.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* update blog category design ([#8507](https://github.com/tuist/tuist/pull/8507))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.10.2...server@1.10.3

## What's Changed in server@1.10.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* show times in local timezone ([#8550](https://github.com/tuist/tuist/pull/8550))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.10.1...server@1.10.2

## What's Changed in server@1.10.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* buttons overflowing when all providers configured ([#8546](https://github.com/tuist/tuist/pull/8546))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.10.0...server@1.10.1

## What's Changed in server@1.10.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* SSO login page ([#8542](https://github.com/tuist/tuist/pull/8542))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.9.1...server@1.10.0

## What's Changed in server@1.9.1<!-- RELEASE NOTES START -->

### 🧪 Testing

* suppress error logs in package release worker tests ([#8524](https://github.com/tuist/tuist/pull/8524))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.9.0...server@1.9.1

## What's Changed in server@1.9.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Support customizing the from and reply to addresses ([#8523](https://github.com/tuist/tuist/pull/8523))
* Marketing translation update from Weblate ([#8518](https://github.com/tuist/tuist/pull/8518))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.7.0...server@1.9.0

## What's Changed in server@1.7.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8516](https://github.com/tuist/tuist/pull/8516))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.6.1...server@1.7.0

## What's Changed in server@1.6.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* separate currency from translatable text and add translation CI protection ([#8514](https://github.com/tuist/tuist/pull/8514))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.6.0...server@1.6.1

## What's Changed in server@1.6.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8510](https://github.com/tuist/tuist/pull/8510))
* Marketing translation update from Weblate ([#8495](https://github.com/tuist/tuist/pull/8495))
* Marketing translation update from Weblate ([#8490](https://github.com/tuist/tuist/pull/8490))
* implement mobile navigation bar ([#8492](https://github.com/tuist/tuist/pull/8492))
### 🐛 Bug Fixes

* navbar not being sticky in the about page ([#8502](https://github.com/tuist/tuist/pull/8502))
* make the whole highlight blog post component show arrow on hover and be clickable ([#8500](https://github.com/tuist/tuist/pull/8500))
* filters bar being off-center ([#8496](https://github.com/tuist/tuist/pull/8496))
* switch to mobile navbar only when viewport width is <768px ([#8499](https://github.com/tuist/tuist/pull/8499))
* width of cards in about ([#8493](https://github.com/tuist/tuist/pull/8493))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.4.1...server@1.6.0

## What's Changed in server@1.4.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* disable horizontal scroll on mobile ([#8488](https://github.com/tuist/tuist/pull/8488))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.4.0...server@1.4.1

## What's Changed in server@1.4.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing next ([#8164](https://github.com/tuist/tuist/pull/8164))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.3.0...server@1.4.0

## What's Changed in server@1.3.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Marketing translation update from Weblate ([#8473](https://github.com/tuist/tuist/pull/8473))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.2.1...server@1.3.0

## What's Changed in server@1.2.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* clean cache entries ([#8462](https://github.com/tuist/tuist/pull/8462))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.2.0...server@1.2.1

## What's Changed in server@1.2.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Extract marketing strings for localization ([#8443](https://github.com/tuist/tuist/pull/8443))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.1.1...server@1.2.0

## What's Changed in server@1.1.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add name attributes to text_input components in user registration ([#8459](https://github.com/tuist/tuist/pull/8459))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.1.0...server@1.1.1

## What's Changed in server@1.1.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* clean CAS ([#8461](https://github.com/tuist/tuist/pull/8461))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@1.0.0...server@1.1.0

## What's Changed in server@1.0.0<!-- RELEASE NOTES START -->

### 🚜 Refactor

* remove dual-storage support for xcode graphs and command events ([#8412](https://github.com/tuist/tuist/pull/8412))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.41.2...server@1.0.0

## What's Changed in server@0.41.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* GitHub comments for different PR git references ([#8433](https://github.com/tuist/tuist/pull/8433))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.41.1...server@0.41.2

## What's Changed in server@0.41.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* GitHub integration for monorepos ([#8415](https://github.com/tuist/tuist/pull/8415))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.41.0...server@0.41.1

## What's Changed in server@0.41.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* allow users with ops access to do any :read operations ([#8416](https://github.com/tuist/tuist/pull/8416))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.40.3...server@0.41.0

## What's Changed in server@0.40.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* make bundle type optional ([#8411](https://github.com/tuist/tuist/pull/8411))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.40.2...server@0.40.3

## What's Changed in server@0.40.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix http request buckets ([#8398](https://github.com/tuist/tuist/pull/8398))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.40.1...server@0.40.2

## What's Changed in server@0.40.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* name for created by of VCS connection ([#8394](https://github.com/tuist/tuist/pull/8394))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.40.0...server@0.40.1

## What's Changed in server@0.40.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve GitHub app integration ([#8294](https://github.com/tuist/tuist/pull/8294))
* add CI run reference to build runs ([#8356](https://github.com/tuist/tuist/pull/8356))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.39.1...server@0.40.0

## What's Changed in server@0.39.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* case insensitive comparison for invitations ([#8343](https://github.com/tuist/tuist/pull/8343))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.39.0...server@0.39.1

## What's Changed in server@0.39.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add configuration filter in the Build Runs page ([#8342](https://github.com/tuist/tuist/pull/8342))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.38.1...server@0.39.0

## What's Changed in server@0.38.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Runtime error trying to access encrypted secrets ([#8334](https://github.com/tuist/tuist/pull/8334))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.38.0...server@0.38.1

## What's Changed in server@0.38.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Add support for offline-validated licenses ([#8333](https://github.com/tuist/tuist/pull/8333))
* add configuration to build insights ([#8330](https://github.com/tuist/tuist/pull/8330))
### 🐛 Bug Fixes

* Respond with bad request to image requests against HTML endpoints  ([#8316](https://github.com/tuist/tuist/pull/8316))
* latest preview link for non-main branch or multiple bundle ids ([#8314](https://github.com/tuist/tuist/pull/8314))
* dark mode in private mode ([#8310](https://github.com/tuist/tuist/pull/8310))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.37.4...server@0.38.0

## What's Changed in server@0.37.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bot comments ([#8309](https://github.com/tuist/tuist/pull/8309))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.37.3...server@0.37.4

## What's Changed in server@0.37.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* triggering QA session on preview upload ([#8305](https://github.com/tuist/tuist/pull/8305))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.37.2...server@0.37.3

## What's Changed in server@0.37.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* db connections by moving from direct connection to session pooler ([#8300](https://github.com/tuist/tuist/pull/8300))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.37.1...server@0.37.2

## What's Changed in server@0.37.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* upload QA recording with standard mp4 format ([#8301](https://github.com/tuist/tuist/pull/8301))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.37.0...server@0.37.1

## What's Changed in server@0.37.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add link to create organization ([#8289](https://github.com/tuist/tuist/pull/8289))
* move back to installing axe via brew ([#8272](https://github.com/tuist/tuist/pull/8272))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.35.0...server@0.37.0

## What's Changed in server@0.35.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* improve the UI when the environment is being prepared ([#8270](https://github.com/tuist/tuist/pull/8270))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.34.0...server@0.35.0

## What's Changed in server@0.34.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add playback speed dropdown in the QA timeline ([#8262](https://github.com/tuist/tuist/pull/8262))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.33.2...server@0.34.0

## What's Changed in server@0.33.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Check for the truthiness of TUIST_HOSTED ([#8260](https://github.com/tuist/tuist/pull/8260))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.33.1...server@0.33.2

## What's Changed in server@0.33.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* incorrect Sort by label for Build duration ([#8259](https://github.com/tuist/tuist/pull/8259))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.33.0...server@0.33.1

## What's Changed in server@0.33.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* show QA step state in timeline ([#8252](https://github.com/tuist/tuist/pull/8252))
### 🐛 Bug Fixes

* use better method for QA recording ([#8240](https://github.com/tuist/tuist/pull/8240))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.32.0...server@0.33.0

## What's Changed in server@0.32.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* update icon radius to liquid glass ([#8251](https://github.com/tuist/tuist/pull/8251))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.31.1...server@0.32.0

## What's Changed in server@0.31.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Revert "chore(server): update dependencies ([#8216](https://github.com/tuist/tuist/pull/8216))" ([#8249](https://github.com/tuist/tuist/pull/8249))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.31.0...server@0.31.1

## What's Changed in server@0.31.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add QA running state ([#8248](https://github.com/tuist/tuist/pull/8248))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.30.0...server@0.31.0

## What's Changed in server@0.30.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add QA empty state ([#8245](https://github.com/tuist/tuist/pull/8245))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.29.3...server@0.30.0

## What's Changed in server@0.29.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Lower the timeouts for lightweight operations against S3 ([#8225](https://github.com/tuist/tuist/pull/8225))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.29.2...server@0.29.3

## What's Changed in server@0.29.2<!-- RELEASE NOTES START -->

### ⛰️  Features

* add QA credentials ([#8221](https://github.com/tuist/tuist/pull/8221))
### 🐛 Bug Fixes

* upload QA recording ([#8236](https://github.com/tuist/tuist/pull/8236))
* fix ci ([#8233](https://github.com/tuist/tuist/pull/8233))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.28.2...server@0.29.2

## What's Changed in server@0.28.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Change modal title from 'Create project' to 'Invite member' ([#8226](https://github.com/tuist/tuist/pull/8226))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.28.1...server@0.28.2

## What's Changed in server@0.28.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* registry scope ([#8223](https://github.com/tuist/tuist/pull/8223))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.28.0...server@0.28.1

## What's Changed in server@0.28.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add QA app description ([#8218](https://github.com/tuist/tuist/pull/8218))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.27.1...server@0.28.0

## What's Changed in server@0.27.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* run correct worker for billing ([#8215](https://github.com/tuist/tuist/pull/8215))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.27.0...server@0.27.1

## What's Changed in server@0.27.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* show used QA session launch argument groups ([#8205](https://github.com/tuist/tuist/pull/8205))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.26.1...server@0.27.0

## What's Changed in server@0.26.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Fix the module name of the worker to sync the Stripe meters ([#8211](https://github.com/tuist/tuist/pull/8211))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.26.0...server@0.26.1

## What's Changed in server@0.26.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* namespace unit minute billing ([#8194](https://github.com/tuist/tuist/pull/8194))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.25.0...server@0.26.0

## What's Changed in server@0.25.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add missing QA session columns ([#8202](https://github.com/tuist/tuist/pull/8202))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.24.0...server@0.25.0

## What's Changed in server@0.24.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add Prometheus metrics for outgoing HTTP requests ([#8198](https://github.com/tuist/tuist/pull/8198))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.23.0...server@0.24.0

## What's Changed in server@0.23.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* project settings ([#8197](https://github.com/tuist/tuist/pull/8197))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.22.2...server@0.23.0

## What's Changed in server@0.22.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Lean on multiplexing requests in a single connection over having many HTTP2 connections against GitHub ([#8196](https://github.com/tuist/tuist/pull/8196))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.22.1...server@0.22.2

## What's Changed in server@0.22.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* handle 0 bundle download size ([#8193](https://github.com/tuist/tuist/pull/8193))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.22.0...server@0.22.1

## What's Changed in server@0.22.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* LLM usage token billing ([#8179](https://github.com/tuist/tuist/pull/8179))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.21.1...server@0.22.0

## What's Changed in server@0.21.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Database Connection Drops ([#8189](https://github.com/tuist/tuist/pull/8189))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.21.0...server@0.21.1

## What's Changed in server@0.21.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* update QA sidebar icon ([#8188](https://github.com/tuist/tuist/pull/8188))
* include the link to the QA session in GitHub comments ([#8186](https://github.com/tuist/tuist/pull/8186))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.19.1...server@0.21.0

## What's Changed in server@0.19.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* set inserted_at for streamed logs ([#8177](https://github.com/tuist/tuist/pull/8177))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.19.0...server@0.19.1

## What's Changed in server@0.19.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* QA timeline ([#8142](https://github.com/tuist/tuist/pull/8142))
* add initial support for default previews visibility ([#8175](https://github.com/tuist/tuist/pull/8175))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.17.1...server@0.19.0

## What's Changed in server@0.17.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* timeouts batch-inserting cache action items ([#8176](https://github.com/tuist/tuist/pull/8176))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.17.0...server@0.17.1

## What's Changed in server@0.17.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* sanitize agent output ([#8160](https://github.com/tuist/tuist/pull/8160))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.16.0...server@0.17.0

## What's Changed in server@0.16.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* optimize bundle loading performance with database indexes ([#8168](https://github.com/tuist/tuist/pull/8168))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.15.1...server@0.16.0

## What's Changed in server@0.15.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* correct selective test misses description ([#8163](https://github.com/tuist/tuist/pull/8163))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.15.0...server@0.15.1

## What's Changed in server@0.15.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* QA early access signup page ([#8060](https://github.com/tuist/tuist/pull/8060))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.14.1...server@0.15.0

## What's Changed in server@0.14.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix CLA workflow for fork contributions ([#8149](https://github.com/tuist/tuist/pull/8149))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.14.0...server@0.14.1

## What's Changed in server@0.14.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* log component ([#8140](https://github.com/tuist/tuist/pull/8140))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.12...server@0.14.0

## What's Changed in server@0.13.12<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* disable HTTP2 for S3 ([#8159](https://github.com/tuist/tuist/pull/8159))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.11...server@0.13.12

## What's Changed in server@0.13.11<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* cascade the deletion of invitations ([#8103](https://github.com/tuist/tuist/pull/8103))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.10...server@0.13.11

## What's Changed in server@0.13.10<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use integer values for status filter options ([#8155](https://github.com/tuist/tuist/pull/8155))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.9...server@0.13.10

## What's Changed in server@0.13.9<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* respect Tigris feature flag for registry ([#8153](https://github.com/tuist/tuist/pull/8153))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.8...server@0.13.9

## What's Changed in server@0.13.8<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bump Elixir version in Dockerfile ([#8154](https://github.com/tuist/tuist/pull/8154))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.7...server@0.13.8

## What's Changed in server@0.13.7<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* disable preview pages being public by default ([#8151](https://github.com/tuist/tuist/pull/8151))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.6...server@0.13.7

## What's Changed in server@0.13.6<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* starting xcresult multipart upload when run doesn't exist yet ([#8150](https://github.com/tuist/tuist/pull/8150))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.5...server@0.13.6

## What's Changed in server@0.13.5<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't try to create package releases when they already exist ([#8147](https://github.com/tuist/tuist/pull/8147))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.4...server@0.13.5

## What's Changed in server@0.13.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* use port from `DATABASE_URL` ([#8145](https://github.com/tuist/tuist/pull/8145))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.3...server@0.13.4

## What's Changed in server@0.13.3<!-- RELEASE NOTES START -->

### 🚜 Refactor

* move web and worker into one process ([#8137](https://github.com/tuist/tuist/pull/8137))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.2...server@0.13.3

## What's Changed in server@0.13.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Tigris prod credentials ([#8143](https://github.com/tuist/tuist/pull/8143))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.13.1...server@0.13.2

## What's Changed in server@0.13.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* single QA run dashboard ([#8114](https://github.com/tuist/tuist/pull/8114))
### 🐛 Bug Fixes

* display improvements for QA dashboard ([#8130](https://github.com/tuist/tuist/pull/8130))
* don't configure Finch pools for endpoints that aren't configured ([#8141](https://github.com/tuist/tuist/pull/8141))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.12.0...server@0.13.1

## What's Changed in server@0.12.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add support for QA launch arguments ([#8077](https://github.com/tuist/tuist/pull/8077))
### 🐛 Bug Fixes

* uploading run analytics when run has not been inserted yet ([#8127](https://github.com/tuist/tuist/pull/8127))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.11.0...server@0.12.0

## What's Changed in server@0.11.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add feature flag for Tigris as an alternative storage ([#8134](https://github.com/tuist/tuist/pull/8134))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.10.3...server@0.11.0

## What's Changed in server@0.10.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* macOS app download ([#8136](https://github.com/tuist/tuist/pull/8136))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.10.2...server@0.10.3

## What's Changed in server@0.10.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* don't suspend canary machine ([#8131](https://github.com/tuist/tuist/pull/8131))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.10.1...server@0.10.2

## What's Changed in server@0.10.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* Add oban_met as dependency to enable Oban analytics in the split worker setup ([#8129](https://github.com/tuist/tuist/pull/8129))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.10.0...server@0.10.1

## What's Changed in server@0.10.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* QA run analytics and overview dashboard ([#8097](https://github.com/tuist/tuist/pull/8097))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.9.4...server@0.10.0

## What's Changed in server@0.9.4<!-- RELEASE NOTES START -->

### 🚜 Refactor

* refactor package sync workers ([#8112](https://github.com/tuist/tuist/pull/8112))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.9.3...server@0.9.4

## What's Changed in server@0.9.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* running Oban cron jobs ([#8128](https://github.com/tuist/tuist/pull/8128))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.9.2...server@0.9.3

## What's Changed in server@0.9.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* replace all `Timex.from_now` with our date formatter ([#8108](https://github.com/tuist/tuist/pull/8108))
* prevent scientific notation in trend badge display ([#8109](https://github.com/tuist/tuist/pull/8109))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.9.1...server@0.9.2

## What's Changed in server@0.9.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* retry on :closed_for_writing  ([#8106](https://github.com/tuist/tuist/pull/8106))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.9.0...server@0.9.1

## What's Changed in server@0.9.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* skip dev releases in registry ([#8107](https://github.com/tuist/tuist/pull/8107))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.8.1...server@0.9.0

## What's Changed in server@0.8.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* memory leak with Prometheus metrics ([#8100](https://github.com/tuist/tuist/pull/8100))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.8.0...server@0.8.1

## What's Changed in server@0.8.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* retrieve QA screenshots from S3, show for actions ([#8086](https://github.com/tuist/tuist/pull/8086))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.7.4...server@0.8.0

## What's Changed in server@0.7.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* runs metadata failing to upload ([#8084](https://github.com/tuist/tuist/pull/8084))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.7.3...server@0.7.4

## What's Changed in server@0.7.3<!-- RELEASE NOTES START -->

### 🚜 Refactor

* move all remaining authorization logic to letme ([#8014](https://github.com/tuist/tuist/pull/8014))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.7.2...server@0.7.3

## What's Changed in server@0.7.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* launch errors related to ClickHouse and Cachex ([#8082](https://github.com/tuist/tuist/pull/8082))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.7.1...server@0.7.2

## What's Changed in server@0.7.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* make migrations reversible ([#8074](https://github.com/tuist/tuist/pull/8074))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.7.0...server@0.7.1

## What's Changed in server@0.7.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* use Appium for describe_ui ([#8058](https://github.com/tuist/tuist/pull/8058))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.6.4...server@0.7.0

## What's Changed in server@0.6.4<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* runtime errors processing telemetry events for Prometheus ([#8072](https://github.com/tuist/tuist/pull/8072))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.6.3...server@0.6.4

## What's Changed in server@0.6.3<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* add default minio port value ([#8061](https://github.com/tuist/tuist/pull/8061))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.6.2...server@0.6.3

## What's Changed in server@0.6.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* showing billing page when an account has payment method without a card ([#8066](https://github.com/tuist/tuist/pull/8066))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.6.1...server@0.6.2

## What's Changed in server@0.6.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* bucket prefixed to the object key when using a custom domain ([#8062](https://github.com/tuist/tuist/pull/8062))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.6.0...server@0.6.1

## What's Changed in server@0.6.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* live streaming QA logs ([#8055](https://github.com/tuist/tuist/pull/8055))
* improve QA reports with more granular steps ([#8027](https://github.com/tuist/tuist/pull/8027))
* use a global storage ([#7995](https://github.com/tuist/tuist/pull/7995))
* ops page, QA agent logs and business intelligence, LLM token usage tracking ([#8005](https://github.com/tuist/tuist/pull/8005))
* guard QA functionality behind a feature flag ([#8008](https://github.com/tuist/tuist/pull/8008))
* run QA in Namespace runners ([#7997](https://github.com/tuist/tuist/pull/7997))
* relay QA agent logs to server ([#7981](https://github.com/tuist/tuist/pull/7981))
* QA GitHub events ([#7982](https://github.com/tuist/tuist/pull/7982))
* send QA agent events ([#7967](https://github.com/tuist/tuist/pull/7967))
* write xcode rows through ingestion buffer ([#7968](https://github.com/tuist/tuist/pull/7968))
* run llm QA agent ([#7914](https://github.com/tuist/tuist/pull/7914))
* create ingestion buffer for CommandEvents ([#7942](https://github.com/tuist/tuist/pull/7942))
### 🐛 Bug Fixes

* sanitize metadata values to prevent String.Chars protocol errors ([#8046](https://github.com/tuist/tuist/pull/8046))
* downgrade liveview ([#8034](https://github.com/tuist/tuist/pull/8034))
* remove :commands tag from Redis pipeline metric ([#8035](https://github.com/tuist/tuist/pull/8035))
* lock contention in `prom_ex` ([#8022](https://github.com/tuist/tuist/pull/8022))
* disable Prometheus in production ([#8020](https://github.com/tuist/tuist/pull/8020))
* add empty state to qa runs table ([#8015](https://github.com/tuist/tuist/pull/8015))
* add missing namespace JWT private key ([#8013](https://github.com/tuist/tuist/pull/8013))
* fix rendering preview QR code images in GitLab ([#8012](https://github.com/tuist/tuist/pull/8012))
* project name validation ([#7998](https://github.com/tuist/tuist/pull/7998))
* use request version instead of header for determining ID format ([#7975](https://github.com/tuist/tuist/pull/7975))
* handle xcresult upload with asynchronously inserted command events ([#7971](https://github.com/tuist/tuist/pull/7971))
* fix crash on unknown sorting parameters ([#7974](https://github.com/tuist/tuist/pull/7974))
* do not set charset for png preview responses ([#7964](https://github.com/tuist/tuist/pull/7964))
### 🚜 Refactor

* rename socket ([#7994](https://github.com/tuist/tuist/pull/7994))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.4.3...server@0.6.0

## What's Changed in server@0.4.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* fix duplicate member invitations ([#7949](https://github.com/tuist/tuist/pull/7949))
### 🚜 Refactor

* remove denormalized Xcode target view ([#7930](https://github.com/tuist/tuist/pull/7930))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.4.0...server@0.4.2

## What's Changed in server@0.4.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* add database fields for Okta configuration in organizations ([#7946](https://github.com/tuist/tuist/pull/7946))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.3.0...server@0.4.0

## What's Changed in server@0.3.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Show build time saved only for CI environments ([#7931](https://github.com/tuist/tuist/pull/7931))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.2.7...server@0.3.0

## What's Changed in server@0.2.3<!-- RELEASE NOTES START -->

### ⛰️  Features

* Support running the web and the worker independently ([#7921](https://github.com/tuist/tuist/pull/7921))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.2.2...server@0.2.3

## What's Changed in server@0.2.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* Include the fediverse creator tag in the marketing pages' posts ([#7925](https://github.com/tuist/tuist/pull/7925))
### 🐛 Bug Fixes

* fix server not launching after embracing semver versioning ([#7922](https://github.com/tuist/tuist/pull/7922))
* use computed default value for remote cache and test hits count ([#7913](https://github.com/tuist/tuist/pull/7913))
* billing date ([#7908](https://github.com/tuist/tuist/pull/7908))
* cache hits count ([#7905](https://github.com/tuist/tuist/pull/7905))
* cache hits count ([#7903](https://github.com/tuist/tuist/pull/7903))



**Full Changelog**: https://github.com/tuist/tuist/compare/server@0.1.2...server@0.2.0

<!-- generated by git-cliff -->
