---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Speed up Xcode builds locally and on CI with Tuist's Xcode cache integration."
}
---
# Xcode cache {#xcode-cache}

Tuist provides support for the Xcode compilation cache, which allows teams to share compilation artifacts by leveraging the build system's caching capabilities.

The Xcode cache was introduced in Xcode 26. You might also see it referred to as the Xcode build cache; it reuses compilation artifacts keyed by their inputs, and Tuist's remote cache makes those artifacts shareable across machines.

> [!TIP]
> **Combine with the module cache**
>
> The Xcode cache and the <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> work at different granularity levels and complement each other. The module cache replaces whole modules with prebuilt `.xcframework`s before the build runs, while the Xcode cache reuses compilation outputs during the build.

> [!TIP]
> **On developer machines, keep `CompilationCache.noindex` when you clean**
>
> By default, the compilation cache store lives inside `DerivedData`, so deleting `DerivedData` throws it away along with the build products. On a developer machine, prefer deleting only the build products: the rebuild then replays from the store on disk, without fetching anything.


## Setup {#setup}

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link>
> - Xcode 26.0 or later


If you don't already have a Tuist account and project, you can create one by running:

```bash
tuist init
```

Once you have a `Tuist.swift` file referencing your `fullHandle`, you can set up the caching for your project by running:

```bash
tuist setup cache
```

This command creates a [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) to run a local cache service on startup that the Swift [build system](https://github.com/swiftlang/swift-build) uses to share compilation artifacts. This command needs to be run once in both your local and CI environments.

To set up the cache on the CI, make sure you are <.localized_link href="/guides/integrations/continuous-integration#authentication">authenticated</.localized_link>.

### Configure Xcode Build Settings {#configure-xcode-build-settings}

For an existing Xcode project, copy the build settings printed by `tuist setup cache` into your project's Build Settings or an existing `.xcconfig` file. The command prints the configuration for your account; it does not generate a configuration file or edit your Xcode project. Keep `$(inherited)` when extending `OTHER_SWIFT_FLAGS` so other compiler options are preserved.

The settings include:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_PLUGIN_PATH = <path to libtuist_cas_plugin.dylib>
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
OTHER_SWIFT_FLAGS = $(inherited) -cas-plugin-option tuist-instance=your-org/your-project
```

Note that `COMPILATION_CACHE_ENABLE_PLUGIN`, `COMPILATION_CACHE_PLUGIN_PATH`, and `COMPILATION_CACHE_REMOTE_SERVICE_PATH` need to be added as **user-defined build settings** since they're not directly exposed in Xcode's build settings UI.

> [!NOTE]
> **One socket for every project**
>
> `tuist setup cache` installs a single cache proxy per machine, so every project uses the same `COMPILATION_CACHE_REMOTE_SERVICE_PATH`. The `tuist-instance` plugin option is what identifies the project.

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH` is what shares C and Objective-C**
>
> It is easy to read this setting as "where the cache service lives" and treat it as optional. It is also the switch that decides whether C, Objective-C, precompiled modules and precompiled headers are shared at all: the build system only runs its caching for those when a remote cache service is configured. Leave it out and you still get Swift compilations shared, but every C/Objective-C file and every module is recompiled on any machine that has not built the project before.


You can also specify these settings when running `xcodebuild` by adding the following flags, such as:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_PLUGIN_PATH=<path to libtuist_cas_plugin.dylib> \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/cas-proxy.sock \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES \
    'OTHER_SWIFT_FLAGS=$(inherited) -cas-plugin-option tuist-instance=your-org/your-project'
```

> [!NOTE]
> **Prefix mapping on Xcode 27 and later**
>
> On Xcode 27 and later, `tuist setup cache` also prints `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING`, and `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`. They make compilation cache keys independent of where the project and `DerivedData` live. Add them as user-defined build settings. Enabling them changes every cache key, so the next build populates the cache again. `tuist generate` sets them for you when `enableCaching` is on.

> [!NOTE]
> **Generated Projects**
>
> Setting the settings manually is not needed if your project is generated by Tuist.
>
> In that case, all you need is to add `enableCaching: true` to your `Tuist.swift` file:
> ```swift
> import ProjectDescription
>
> let tuist = Tuist(
>     fullHandle: "your-org/your-project",
>     project: .tuist(
>         generationOptions: .options(
>             enableCaching: true
>         )
>     )
> )
> ```


### Cache upload policy {#cache-upload-policy}

By default, the cache service both downloads and uploads artifacts to the remote cache. You can control this with the `xcodeCache` option in your `Tuist.swift` file to enable read-only mode, where artifacts are downloaded but never uploaded:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: false
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

A common pattern is to push artifacts only from CI, where builds are reproducible, while keeping local environments read-only. You can achieve this using `Environment.isCI`, which checks for the `CI` environment variable set by most CI providers:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: Environment.isCI
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

With this setup, local builds benefit from cached artifacts without uploading, while CI builds populate the cache for the rest of the team.

The upload policy is recorded per project on the machine that runs `tuist setup cache`. To change it, update `upload` and run `tuist setup cache` again, and `tuist generate` too if Tuist generates your project. Uploads after that follow the new policy without restarting the cache on that machine. Jobs for the same project that run on one machine at the same time share its policy, so the most recent `tuist setup cache` decides it for all of them.

### Store size limit {#store-size-limit}

A compilation cache store grows with every build. To bound the project's stores, set `storeSizeLimit` in your `Tuist.swift` file:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        storeSizeLimit: .gigabytes(20)
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

While no build is running, Tuist checks each of the project's stores every 10 minutes. It deletes a store's oldest cached outputs once newer builds have written about half the limit, so the store settles at about the limit. A store can be larger than the limit while builds are running, and a store that was already larger when you set the limit shrinks once new builds have written that much. When several projects use the same store, as they do with its default location, the smallest of their limits applies. The limit applies on every machine where you run `tuist setup cache`, so run it again after changing the limit.

### Module cache hashes {#module-cache-hashes}

Compilation cache settings aren't part of <.localized_link href="/guides/features/projects/hashing">module cache hashes</.localized_link>. Tuist leaves every `COMPILATION_CACHE_*` build setting, and every `-cas-plugin-option` flag with its value, out of the hash. Turning `enableCaching` on or off, or changing the upload policy, keeps your targets' hashes, so the <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> binaries you already warmed stay valid. You can compare builds with and without the Xcode cache against the same module cache.

> [!NOTE]
> **Prefix mapping settings are hashed**
>
> On Xcode 27 and later, `enableCaching: true` also sets `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING`, and `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`. These settings are part of module cache hashes, so on Xcode 27 and later, turning `enableCaching` on or off changes your targets' hashes.

### Reusing parts of large outputs {#reusing-parts-of-large-outputs}

The Xcode cache can reduce transfers with content-defined chunking. Instead of treating each large output as unrelated to earlier versions, it splits the compressed output at boundaries determined by its contents. After an edit, matching chunks can be reused even when their offsets have changed.

Uploads send only chunks that the server is missing. Downloads first obtain the exact cached action and the output's chunk recipe, then reuse verified chunks stored on the local machine and fetch the missing pieces. The complete reconstructed output is verified before it is restored to the compiler cache.

The transfer-chunk cache is separate from `DerivedData`, so its chunks can survive cleaning the compilation cache or restarting the local cache service. It is disposable and bounded to at most one gibibyte of chunk payload, with an additional temporary staging file of at most two mebibytes. Evicted or damaged chunks are downloaded again when needed. Keeping the compilation cache itself is still faster than reconstructing its contents.

The client uses chunked transfers only when the server advertises compatible support. Older clients can still read complete outputs, and clients connected to older or unsupported servers retain ordinary transfers. Small outputs stay on the existing whole-output path.

This reduces transferred bytes, not compiler invalidation. Changing a source file can still require compilation; chunking helps publish or restore the resulting output. Savings depend on the output and the edit, and a cold machine with no matching chunks must download all of the output.

### Continuous integration {#continuous-integration}

To enable caching in your CI environment, you need to run the same command as in local environments: `tuist setup cache`.

For authentication, you can use either <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC authentication</.localized_link> (recommended for supported CI providers) or an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> via the `TUIST_TOKEN` environment variable.

An example workflow for GitHub Actions using OIDC authentication:
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

See the <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> for more examples, including token-based authentication and other CI platforms like Xcode Cloud, CircleCI, Bitrise, and Codemagic.

### Compilation cache store on CI {#compilation-cache-store-on-ci}

The compilation cache store is the local directory where Xcode keeps compilation outputs. The `COMPILATION_CACHE_CAS_PATH` build setting sets its location, which defaults to `CompilationCache.noindex` inside `DerivedData`.

#### Stateful store {#stateful-store}

To keep a store between builds, point `COMPILATION_CACHE_CAS_PATH` (and `TUIST_COMPILATION_CACHE_CAS_PATH` for `tuist cache`) at one durable path, and bound its size with a [store size limit](#store-size-limit).

## Troubleshooting {#troubleshooting}

### Builds warn that the Xcode cache proxy failed {#cas-proxy-failed}

If a build shows a warning like the following, which Xcode prefixes with `CAS error:` or `CAS operation failed:` depending on which compilation hit the failure first:

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

then the compilation cache could not reach the local cache proxy that `tuist setup cache` installs. The build still succeeds, but the affected compilations get no remote cache hits, so it runs like a build with an empty cache. Their uploads are kept on disk and sent once the proxy handles requests again: later in the same build if it comes back in time, otherwise during the next build on the same machine. A CI machine that is discarded after the job loses them. The warning appears once per build, in Xcode's Issue navigator and in `xcodebuild` output.

To check whether the proxy is running, look for a process listening on the socket named in the warning:

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

If the command prints nothing, run `tuist setup cache` to start the proxy again. On CI, run `tuist setup cache` before any `xcodebuild` invocation in every job.

### Builds are extremely slow and emit `CAS error: deadlineExceeded` warnings {#cas-deadline-exceeded}

If your builds take much longer than expected and the Xcode build log is full of warnings like:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

or:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

then `COMPILATION_CACHE_REMOTE_SERVICE_PATH` points at a socket nothing listens on, usually the per-project socket (`~/.local/state/tuist/<org>_<project>.sock`) that earlier versions of Tuist configured. Tuist no longer serves that socket. Xcode retries the connection on every compilation cache request rather than failing fast, which can make a build take an hour or more, and Tuist cannot change that behavior.

To fix it:

- **Generated projects**: run `tuist generate` again.
- **Other projects**: replace the `COMPILATION_CACHE_*` build settings with the ones `tuist setup cache` prints, as described in [Configure Xcode Build Settings](#configure-xcode-build-settings).

If you are not using the Xcode cache, remove the `COMPILATION_CACHE_*` build settings instead and run `tuist teardown cache`.

### `uploaded CAS output` appears locally even though uploads are disabled {#uploaded-cas-output-with-upload-disabled}

When `xcodeCache: .xcodeCache(upload: false)` (or `upload: Environment.isCI` on a non-CI machine) is set, you may still see `note: uploaded CAS output ...` in the build log. `xcodebuild` has no way to skip those calls, so Tuist still receives them, but it does not publish anything to the Tuist server. The dashboard metrics account for this, so no spurious upload traffic is reported.
