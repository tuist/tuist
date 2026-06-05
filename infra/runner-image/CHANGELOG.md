# Changelog

All notable changes to this project will be documented in this file.
## What's Changed in runner-image@0.3.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* runner job steps + log capture (live tail, per-step) ([#10985](https://github.com/tuist/tuist/pull/10985))
### 🐛 Bug Fixes

* pin runners-controller to 0.11.0 to deploy the runner _diag env var ([#11118](https://github.com/tuist/tuist/pull/11118))



**Full Changelog**: https://github.com/tuist/tuist/compare/runner-image@0.2.1...runner-image@0.3.0

## What's Changed in runner-image@0.2.1<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* roll runners-controller back to 0.7.0 to restore CI docker ([#11102](https://github.com/tuist/tuist/pull/11102))



**Full Changelog**: https://github.com/tuist/tuist/compare/runner-image@0.2.0...runner-image@0.2.1

## What's Changed in runner-image@0.2.0<!-- RELEASE NOTES START -->

### ⛰️  Features

* own macOS+Xcode base image ([#10834](https://github.com/tuist/tuist/pull/10834))
* move runners to the tuist-linux label and default the profile to 2 vCPU / 8 GB ([#11052](https://github.com/tuist/tuist/pull/11052))
* account-scoped Runner Profiles (Linux v1) ([#10970](https://github.com/tuist/tuist/pull/10970))
* provision Postgres in-cluster via CNPG with /ops/db UI ([#10942](https://github.com/tuist/tuist/pull/10942))
* wire CAPI core's workload connection for the Mac-mini fleets ([#10981](https://github.com/tuist/tuist/pull/10981))
* Support self-hosted Kura endpoints ([#10965](https://github.com/tuist/tuist/pull/10965))
* cluster-managed vm-image-builder fleet ([#10825](https://github.com/tuist/tuist/pull/10825))
* Linux runners on Hetzner Robot bare metal with Kata Containers QEMU microVMs and queue-driven autoscaling ([#10794](https://github.com/tuist/tuist/pull/10794))
* join the macOS fleet to a Tailscale tailnet ([#10761](https://github.com/tuist/tuist/pull/10761))
### 🐛 Bug Fixes

* anchor runner-image cliff tag_pattern so it ignores linux-runner-image tags ([#11021](https://github.com/tuist/tuist/pull/11021))
* restore Cloudflare global Kura deploys ([#10877](https://github.com/tuist/tuist/pull/10877))
* wipe Cirrus's placeholder /Users/runner before addUser ([#10833](https://github.com/tuist/tuist/pull/10833))
### ⚡ Performance

* unblock Release workflow by skipping cliff's GitHub API enrichment ([#10890](https://github.com/tuist/tuist/pull/10890))



**Full Changelog**: https://github.com/tuist/tuist/compare/runner-image@0.1.5...runner-image@0.2.0

## What's Changed in runner-image@0.1.5<!-- RELEASE NOTES START -->

### ⛰️  Features

* align self-hosted runner paths with GitHub-hosted ([#10826](https://github.com/tuist/tuist/pull/10826))
### 🐛 Bug Fixes

* create runner subdirs as root, chown each one ([#10832](https://github.com/tuist/tuist/pull/10832))
* chown /Users/runner so the runner user owns its home ([#10830](https://github.com/tuist/tuist/pull/10830))



**Full Changelog**: https://github.com/tuist/tuist/compare/runner-image@0.1.4...runner-image@0.1.5

## What's Changed in runner-image@0.1.4<!-- RELEASE NOTES START -->

### ⛰️  Features

* recycle stale runner Pods on RunnerPool image bump ([#10817](https://github.com/tuist/tuist/pull/10817))
* switch runner image to LaunchAgent + autologin ([#10807](https://github.com/tuist/tuist/pull/10807))
### 🐛 Bug Fixes

* publish #10807's LaunchAgent rebuild through release pipeline ([#10818](https://github.com/tuist/tuist/pull/10818))
### 🚜 Refactor

* release on path, not commit scope ([#10824](https://github.com/tuist/tuist/pull/10824))



**Full Changelog**: https://github.com/tuist/tuist/compare/runner-image@0.1.2...runner-image@0.1.4

## What's Changed in runner-image@0.1.2<!-- RELEASE NOTES START -->

### 🐛 Bug Fixes

* simplify Xcode symlink provisioner to match convention ([#10814](https://github.com/tuist/tuist/pull/10814))
* symlink Xcode_26.4.1.app at the real Xcode_26.4.app bundle ([#10808](https://github.com/tuist/tuist/pull/10808))
* isolate Tart GHCR credentials for xcresult image ([#10796](https://github.com/tuist/tuist/pull/10796))
* bump Xcode to 26.4.1 + symlink Xcode_26.4.app ([#10803](https://github.com/tuist/tuist/pull/10803))
* trigger release pipeline now that 403 is fixed ([#10802](https://github.com/tuist/tuist/pull/10802))



**Full Changelog**: https://github.com/tuist/tuist/compare/runner-image@0.1.1...runner-image@0.1.2

## What's Changed in runner-image@0.1.1<!-- RELEASE NOTES START -->

### ⛰️  Features

* tuist runners — shared warm pool with dispatch-time binding ([#10653](https://github.com/tuist/tuist/pull/10653))
* manage multi-region Kura servers ([#10489](https://github.com/tuist/tuist/pull/10489))
* support GitHub Enterprise Server installations ([#10471](https://github.com/tuist/tuist/pull/10471))
* manage xcresult processor as a k8s Deployment via tart-cri (Mac minis as real k8s nodes) ([#10499](https://github.com/tuist/tuist/pull/10499))
* run processor in-cluster via Oban queue + least-privilege role ([#10428](https://github.com/tuist/tuist/pull/10428))
* migrate from Render to Syself Kubernetes (Helm chart, Alloy, ESO, cascade deploys) ([#10368](https://github.com/tuist/tuist/pull/10368))
* add self-hosted Helm chart with observability ([#10055](https://github.com/tuist/tuist/pull/10055))
* publish CLI spec JSON as release artifact ([#9843](https://github.com/tuist/tuist/pull/9843))
* move Noora web component library into monorepo ([#9768](https://github.com/tuist/tuist/pull/9768))
* add Android companion app with the initial log in screen ([#9536](https://github.com/tuist/tuist/pull/9536))
* publish skills to tuist/agent-skills repo instead of NPM ([#9402](https://github.com/tuist/tuist/pull/9402))
* publish Tuist skills as NPM package ([#9395](https://github.com/tuist/tuist/pull/9395))
* add Linux support for auth and cache commands ([#9291](https://github.com/tuist/tuist/pull/9291))
* add Gradle plugin to release workflow ([#9334](https://github.com/tuist/tuist/pull/9334))
* reenable image releases ([#9054](https://github.com/tuist/tuist/pull/9054))
* release docker images ([#8966](https://github.com/tuist/tuist/pull/8966))
* migrate workflows to OIDC authentication ([#8870](https://github.com/tuist/tuist/pull/8870))
* improve release formatting and notes generation
* create unified release workflow to prevent race conditions
* add distribution for the Tuist App ([#6618](https://github.com/tuist/tuist/pull/6618))
* support for focusing on project targets ([#3654](https://github.com/tuist/tuist/pull/3654))
### 🐛 Bug Fixes

* publish HOME fix through release pipeline ([#10800](https://github.com/tuist/tuist/pull/10800))
* set HOME on the runner image LaunchDaemon ([#10797](https://github.com/tuist/tuist/pull/10797))
* clear docker ghcr credentials for xcresult image ([#10792](https://github.com/tuist/tuist/pull/10792))
* repair release artifact paths ([#10781](https://github.com/tuist/tuist/pull/10781))
* release xcresult processor image for server fixes ([#10737](https://github.com/tuist/tuist/pull/10737))
* configure managed Kura TLS issuer ([#10741](https://github.com/tuist/tuist/pull/10741))
* unbreak capi-scaleway canary; stop racing on chart values in release flow ([#10689](https://github.com/tuist/tuist/pull/10689))
* don't strand released components when one release job fails ([#10669](https://github.com/tuist/tuist/pull/10669))
* restore main CI checks ([#10651](https://github.com/tuist/tuist/pull/10651))
* restore previous macOS runner for CLI release ([#10565](https://github.com/tuist/tuist/pull/10565))
* stream artifact backfill to bound migration memory ([#10558](https://github.com/tuist/tuist/pull/10558))
* prevent canary deploy migration hook timeout ([#10550](https://github.com/tuist/tuist/pull/10550))
* bound artifact backfill memory and give migration job a memory request ([#10541](https://github.com/tuist/tuist/pull/10541))
* disable nginx proxy_request_buffering on server ingress ([#10535](https://github.com/tuist/tuist/pull/10535))
* sync S3 credentials from 1Password via ESO ([#10517](https://github.com/tuist/tuist/pull/10517))
* raise ingress-nginx body size to unblock createBundle ([#10492](https://github.com/tuist/tuist/pull/10492))
* retry ClickHouse flush on socket drops ([#10342](https://github.com/tuist/tuist/pull/10342))
* run Release App job on GitHub Actions instead of namespace ([#10321](https://github.com/tuist/tuist/pull/10321))
* include CLI module paths in app release detection ([#10312](https://github.com/tuist/tuist/pull/10312))
* unflake gradle analytics tests and patch trivy findings ([#10289](https://github.com/tuist/tuist/pull/10289))
* split TUIST_GITHUB_TOKEN into dedicated PATs per workflow ([#10223](https://github.com/tuist/tuist/pull/10223))
* revert release workflow to cancel-in-progress: true ([#10221](https://github.com/tuist/tuist/pull/10221))
* remove --tags from release push to avoid duplicate tag errors ([#10217](https://github.com/tuist/tuist/pull/10217))
* publish self-hosted image with embedded processor ([#10172](https://github.com/tuist/tuist/pull/10172))
* add missing macOS platforms to mise.lock ([#10030](https://github.com/tuist/tuist/pull/10030))
* set MISE_LOCKED=1 in all CI workflows ([#10017](https://github.com/tuist/tuist/pull/10017))
* fix release workflow GitHub API rate limit failures ([#9808](https://github.com/tuist/tuist/pull/9808))
* trigger release for dependency bumps ([#9704](https://github.com/tuist/tuist/pull/9704))
* publish Gradle plugin before updating settings version ([#9674](https://github.com/tuist/tuist/pull/9674))
* use --autostash in release push retry loop ([#9651](https://github.com/tuist/tuist/pull/9651))
* prevent commit-and-release from being skipped when optional jobs are skipped ([#9649](https://github.com/tuist/tuist/pull/9649))
* bump Release CLI job timeout from 30 to 50 minutes ([#9631](https://github.com/tuist/tuist/pull/9631))
* add --no-prepare to mise run in release workflow ([#9628](https://github.com/tuist/tuist/pull/9628))
* fix download page and Sparkle updates not reflecting latest version ([#9617](https://github.com/tuist/tuist/pull/9617))
* prevent commit-and-release from running when a dependency is cancelled or failed ([#9603](https://github.com/tuist/tuist/pull/9603))
* use namespace-profile-default-with-volume for release jobs ([#9590](https://github.com/tuist/tuist/pull/9590))
* move macOS pipelines back to GitHub runners ([#9584](https://github.com/tuist/tuist/pull/9584))
* install both profiles, let export re-sign for App Store ([#9570](https://github.com/tuist/tuist/pull/9570))
* fix iOS App Store upload signing and release triggers ([#9569](https://github.com/tuist/tuist/pull/9569))
* fix iOS App Store upload ([#9568](https://github.com/tuist/tuist/pull/9568))
* Use latest Gradle plugin version in init and add takeaways ([#9543](https://github.com/tuist/tuist/pull/9543))
* add Docker Buildx setup for GHA cache to work ([#9515](https://github.com/tuist/tuist/pull/9515))
* bump Swift to 6.2 for Linux static builds to fix SSL certificates ([#9505](https://github.com/tuist/tuist/pull/9505))
* stop auto-bumping plugin minimum CLI version ([#9497](https://github.com/tuist/tuist/pull/9497))
* make gradle release atomic and prevent version drift ([#9488](https://github.com/tuist/tuist/pull/9488))
* ensure release notes are generated for Gradle releases ([#9485](https://github.com/tuist/tuist/pull/9485))
* remove --include-path filter from release check
* use Swift Static Linux SDK for fully static binaries ([#9450](https://github.com/tuist/tuist/pull/9450))
* update Constants.swift path in release workflow ([#9359](https://github.com/tuist/tuist/pull/9359))
* fix Gradle artifact download path in release workflow ([#9342](https://github.com/tuist/tuist/pull/9342))
* read Gradle publish keys from the tuist 1Password bundle ([#9338](https://github.com/tuist/tuist/pull/9338))
* fix release and deploy ([#9069](https://github.com/tuist/tuist/pull/9069))
* add missing tuist install step in release-ios job ([#9037](https://github.com/tuist/tuist/pull/9037))
* use GitHub run number for CFBundleVersion ([#8986](https://github.com/tuist/tuist/pull/8986))
* move tuist install to a dedicated step, so it can be cached and skipped ([#8877](https://github.com/tuist/tuist/pull/8877))
* only use .build cache on exact key match ([#8875](https://github.com/tuist/tuist/pull/8875))
* generate correct Sparkle appcast ([#8328](https://github.com/tuist/tuist/pull/8328))
* download app artifacts to app path ([#8327](https://github.com/tuist/tuist/pull/8327))
* retain app artifact paths on download ([#8326](https://github.com/tuist/tuist/pull/8326))
* correct macOS app artifact location ([#8325](https://github.com/tuist/tuist/pull/8325))
* reorder release steps ([#8323](https://github.com/tuist/tuist/pull/8323))
* release cancelled after being committed ([#8322](https://github.com/tuist/tuist/pull/8322))
* trigger macOS app release ([#8318](https://github.com/tuist/tuist/pull/8318))
* only commit and release after all builds are finished ([#8317](https://github.com/tuist/tuist/pull/8317))
* include ProjectDescription.xcframework.zip in GitHub releases ([#8312](https://github.com/tuist/tuist/pull/8312))
* Downgrade ProjectDescription Swift version to 6.1 ([#8283](https://github.com/tuist/tuist/pull/8283))
* Downgrade `ProjectDescription` Swift version to 6.1 ([#8280](https://github.com/tuist/tuist/pull/8280))
* attach app artifacts with the app release ([#8279](https://github.com/tuist/tuist/pull/8279))
* release without binary cache ([#8277](https://github.com/tuist/tuist/pull/8277))
* iOS app release ([#8271](https://github.com/tuist/tuist/pull/8271))
* correct server cliff config path in release workflow ([#8045](https://github.com/tuist/tuist/pull/8045))
* releasing of Homebrew formula and cask ([#8017](https://github.com/tuist/tuist/pull/8017))
* Fix empty release notes in GitHub releases ([#7933](https://github.com/tuist/tuist/pull/7933))
* use existing cliff.toml files with comment markers
* remove --unreleased flag from git-cliff commands to show proper version in release notes
* handle server version detection and prevent commit failures
* add version validation to prevent releasing older versions
* released app missing staple ([#7778](https://github.com/tuist/tuist/pull/7778))
* finding latest update ([#7046](https://github.com/tuist/tuist/pull/7046))
* generating Sparkle appcast ([#7033](https://github.com/tuist/tuist/pull/7033))
* rename macOS app build ([#6802](https://github.com/tuist/tuist/pull/6802))
* release workflow PR step ([#4066](https://github.com/tuist/tuist/pull/4066))



**Full Changelog**: https://github.com/tuist/tuist/compare/runner-image@0.1.0...runner-image@0.1.1

<!-- generated by git-cliff -->
