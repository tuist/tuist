---
title: Elixir cache
titleTemplate: ":title · Cache · Guides · Tuist"
description: Enable dependency caching for your Elixir project and keep using Mix.
---

# Elixir cache

Tuist reuses compiled dependencies locally and across CI builds. Enable it once,
then keep using `mix compile` and `mix test`.

## Set up

Follow <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Get started with Elixir</.localized_link> once. The shared setup enables dependency caching alongside build and test insights; no extra cache setup is needed.

`cache: true` automatically selects supported Hex and Git dependencies; you don't
need to list them. Native/custom compilation and local dependencies continue
through Mix normally. Your application's source files are not cached.

## Build as usual

```sh
mix compile
mix test
```

When a dependency needs compilation, Tuist checks the local cache, then the shared
remote cache. A miss compiles normally and stores the result for future builds.
Selected, supported dependencies that Mix considers up to date count as local
hits when their compiled outputs are present and valid; no cache lookup is
needed. If authentication or the cache is unavailable, Mix still compiles normally.

## See your cache hits

Open **Mix Cache** in your project's dashboard for hit rates, transfers and recent
builds. Select a build's **Mix cache** tab to see which tasks hit or missed.
**CAS Outputs** shows actual remote downloads and uploads; local hits don't create
remote transfer records. Reusing already-current outputs contributes to hit rate
but has no transfer bytes, restore latency or estimated time saved.

To try a restore, clean a supported dependency's compiled output and build again:

```sh
mix deps.clean nimble_options --build
mix compile
```

Replace `nimble_options` with a dependency your project uses that has already
populated the cache. Keep the same Mix environment and compiler settings.

## Customize only when needed

Most projects can keep `cache: true`. Use a keyword list for exceptions:

```elixir
tuist: [
  project: "your-account/your-project",
  cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
]
```

- **Extra compile-time inputs:** declare external files with `inputs: ["schemas"]`
  and environment variables with `env: ["COMPILER_OPTION"]`.
- **Local only:** set `remote: false`.
- **No remote uploads:** set `upload: false`. Server permissions still control access.
- **Disable caching:** set `cache: false`.

> [!IMPORTANT]
> Compilation can execute arbitrary Elixir code. Declare additional inputs and
> exclude dependencies whose time/network-dependent code or side effects must run
> on every build. Cached artifacts can include secrets, and cache writers are
> trusted code producers: don't give untrusted jobs cache-write credentials.

For dependency selection, reuse across different checkout paths, troubleshooting
and implementation details, see
<.localized_link href="/guides/features/cache/elixir-advanced">advanced Elixir cache configuration</.localized_link>.
