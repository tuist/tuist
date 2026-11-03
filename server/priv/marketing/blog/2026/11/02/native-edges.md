---
title: "Native edges: principles for native apps with a shared core"
category: "engineering"
tags: ["engineering", "architecture", "rust", "swiftui", "jetpack-compose", "kotlin", "build-systems", "once"]
excerpt: "Seven principles for building native apps on a shared core: what goes in the core, how edges talk to it, how navigation stays addressable, and how the build graph keeps it fast. With a sample app for iOS, Android, and the terminal."
author: pepicrft
---

For a long time, building a client for each platform meant writing every screen and fixing every bug once per platform, which meant a team for each, or picking which platforms to leave out. So, as an industry, we came up with ways to live with that cost.

[Electron](https://www.electronjs.org), [React Native](https://reactnative.dev), and more recently [Tauri](https://tauri.app) came out of that. They gave teams a dynamic runtime, hot reloading, and the web ecosystem of libraries and packages, so a single team could build for several platforms. [Slack](https://slack.com), [Linear](https://linear.app), [Discord](https://discord.com), [Notion](https://www.notion.com), and [Visual Studio Code](https://code.visualstudio.com) are all built on a web stack, and many of us use them every day. More recently, [Raycast](https://www.raycast.com) took the same route to bring its app to Windows. [Raycast 2.0](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast) shares a React and TypeScript frontend across macOS and Windows, loaded in each platform's web view, and the team explains the choice with hiring, the UI components available on the web, and keeping their extensions consistent, along with iteration speed.

Coding agents have changed part of that equation. Building a [SwiftUI](https://developer.apple.com/xcode/swiftui/) view and its [Jetpack Compose](https://developer.android.com/compose) counterpart used to mean writing the same thing twice, and today an agent can do most of that work while you review it. Compiling it is still slow. Anyone who has waited on [Xcode](https://developer.apple.com/xcode/) or [Gradle](https://gradle.org) knows how much of a day that can take, and it's the problem we've been working on at Tuist for years, through caching, selective testing, and now [Once](https://github.com/tuist/once).

When native builds get fast as well, one of the main reasons to pick a web runtime, iteration speed, gets weaker. The others, like the ecosystem or the team you can hire, may still apply to you, and a big codebase won't be rewritten because the economics shifted. We wanted to know what we would build if we started a multi-platform app today, so we wrote down the principles we'd follow and built a small sample app to try them.

This builds on work we started almost ten years ago, when we explored modular architectures for iOS apps and came up with microfeatures, which many teams adopted and which we later renamed [The Modular Architecture](/en/docs/guides/features/projects/tma-architecture). Tuist grew out of that work. This post applies the same ideas about boundaries and build graphs across platforms.

We call this set of principles **native edges**. They describe an app as two layers that both ship inside it. The **headless core** holds the business logic and has no UI. The **native edges** are what users see and touch, one per platform, and they connect the core to that platform. We avoid the terms frontend and backend because people usually read them as UI and server.

The principles are:

1. [Keep business logic in a headless core](#1-keep-business-logic-in-a-headless-core).
2. [Choose a core language that runs everywhere you ship](#2-choose-a-core-language-that-runs-everywhere-you-ship).
3. [Connect the edges to the core through a small, typed API](#3-connect-the-edges-to-the-core-through-a-small-typed-api).
4. [Make every screen reachable by an address](#4-make-every-screen-reachable-by-an-address).
5. [Model the whole app in one build graph](#5-model-the-whole-app-in-one-build-graph).
6. [Keep the graph shallow and wide](#6-keep-the-graph-shallow-and-wide).
7. [Compile only what each edge needs](#7-compile-only-what-each-edge-needs).

You can adopt them selectively. Every project has its own constraints, and some will have good reasons to keep a piece of logic in Swift, to share less, or to pick different tools than ours.

## The sample app

To try the principles end to end, we built [Native Edges](https://github.com/tuist/native-edges), a client-side agent. You sign in with your ChatGPT account and talk to an agent whose loop, tools, and conversation history run and live on your device, while the model itself runs in the cloud. There's an iOS app in SwiftUI, an Android app in Kotlin and Jetpack Compose, and a command-line tool in Rust, and all three share one headless core in Rust. The core handles the device-code sign-in and token refresh, the agent loop and its requests to the model, the tools the agent uses to read earlier conversations, and the history, which it stores in [SQLite](https://www.sqlite.org) through [Diesel](https://diesel.rs).

Here's the iOS app, built and launched on a simulator with `once run`. It signs in with a device code, lists the stored conversations, and asks the agent a question that makes it read earlier ones. Then the CLI lists the app's routes, builds the URL for one conversation, and the simulator opens it:

<video data-theme-variant="light" autoplay muted loop playsinline controls preload="metadata" poster="/marketing/images/blog/2026/11/02/native-edges-ios-light-poster.webp" aria-label="The Native Edges iOS app signing in, answering a question from earlier conversations, and opening a conversation from a deep link">
  <source src="/marketing/images/blog/2026/11/02/native-edges-ios-light.mp4" type="video/mp4" />
</video>
<video data-theme-variant="dark" autoplay muted loop playsinline controls preload="metadata" poster="/marketing/images/blog/2026/11/02/native-edges-ios-dark-poster.webp" aria-label="The Native Edges iOS app signing in, answering a question from earlier conversations, and opening a conversation from a deep link">
  <source src="/marketing/images/blog/2026/11/02/native-edges-ios-dark.mp4" type="video/mp4" />
</video>

We'll use the sample as the running example. The diagram shows its three edges, plus two more the same core could support, which the sample doesn't include:

```mermaid
graph TB
  subgraph edges["Native edges"]
    apple["iOS<br/>SwiftUI + Swift"]
    android["Android<br/>Jetpack Compose + Kotlin"]
    cli["CLI<br/>Terminal"]
    desktop["Linux and Windows<br/>GPUI (not in the sample)"]
    web["Web<br/>HTML + JavaScript (not in the sample)"]
  end
  subgraph core["Headless core in Rust"]
    nav["Route catalog and deep links"]
    auth["Sign-in and sessions"]
    agent["Agent loop and model API"]
    store["Conversation history"]
    nav ~~~ auth ~~~ agent ~~~ store
  end
  apple -->|"UniFFI Swift bindings"| core
  android -->|"UniFFI Kotlin bindings + JNA"| core
  cli -->|"Rust calls"| core
  desktop -.->|"Rust calls"| core
  web -.->|"WebAssembly"| core
  classDef coreNode stroke:#6f2cff,stroke-width:1.5px
  classDef proposed stroke-dasharray: 4 4
  class nav,auth,agent,store coreNode
  class desktop,web proposed
  style core stroke:#6f2cff,stroke-width:1.5px
```

## 1. Keep business logic in a headless core

Put in the edge what only the platform can do, and put the rest in the core.

The edge is the user-facing layer. For apps, the UI goes to a framework that compiles to the platform and follows its conventions: SwiftUI on Apple platforms, Jetpack Compose on Android. Anything that is only reachable through the platform's frameworks goes in the edge too: the [Keychain](https://developer.apple.com/documentation/security/keychain-services) or the [Android Keystore](https://developer.android.com/privacy-and-security/keystore), presenting a browser for an [OAuth](https://oauth.net/2/) flow, registering for [push notifications](https://developer.apple.com/documentation/usernotifications), [Live Activities](https://developer.apple.com/documentation/activitykit), [share extensions](https://developer.apple.com/design/human-interface-guidelines/sharing-and-collaboration), or on-device [speech recognition](https://developer.apple.com/documentation/speech). Users notice when an app ignores how their platform does these things.

An edge doesn't have to be an app. A command-line tool is an edge whose platform is the terminal, and a web app can be one too, with the core compiled to [WebAssembly](https://webassembly.org) and the browser as the platform.

The core is the logic that is the same on every platform: which fields of a record can be edited, how a list is paginated, how an OAuth token is refreshed, how history is reconciled after a reconnect, or making sure a late response from a cancelled request doesn't overwrite newer results. Because the core has no UI and doesn't depend on any platform framework, you can cover most of the app's behavior with unit tests that run in seconds, without a simulator, an emulator, or UI automation, and those tests apply to every platform at once. You still need some tests per edge for rendering and platform integration, but there are far fewer of them.

[Ghostty](https://ghostty.org), the terminal emulator by [Mitchell Hashimoto](https://mitchellh.com), is a good example of this split. Its core, [libghostty](https://ghostty.org/docs/about#libghostty), is written in Zig, exposes a C API, and handles terminal emulation, fonts, and rendering. The macOS app on top of it is written in Swift with AppKit and SwiftUI, and the Linux app uses GTK. Ghostty's core does more than ours, since it includes rendering, but the idea is the same: a shared engine with an app on each platform that feels at home there.

## 2. Choose a core language that runs everywhere you ship

Look for a language with good toolchains and a good standard library on every platform you support, so you don't find out halfway through a feature that the API you need isn't available on one of them. [Rust](https://www.rust-lang.org) works well here. It compiles to iOS, Android, macOS, Linux, Windows, and WebAssembly, and its crates cover almost everything a client needs. The browser is the exception to keep in mind: on [`wasm32-unknown-unknown`](https://doc.rust-lang.org/rustc/platform-support/wasm32-unknown-unknown.html), parts of the standard library like the file system and threads don't work, so a web edge needs crates that use the browser's APIs instead. [Zig](https://ziglang.org) is another good candidate, with explicit allocators and cross-compilation built into its toolchain. [Go](https://go.dev) can work too, although it ships with a garbage collector.

Memory is a big part of why we lean towards Rust and Zig. Neither uses a garbage collector, which gives you close control over allocations. That matters when the core runs in places with strict limits, like app extensions and widgets that the system terminates when they use too much memory, watches, or embedded devices. It also means the app doesn't run a second garbage collector next to Swift's reference counting or the Android runtime's own collector. You still have to respect ownership rules at the boundary, and measure memory on the constrained targets.

People often ask us why we don't use [Kotlin Multiplatform](https://kotlinlang.org/docs/multiplatform.html) on Apple platforms, or [Swift on Android](https://www.swift.org/android-workgroup/). Both work, and teams ship apps with them. We prefer Rust and Zig because a platform language running on another platform brings its runtime and memory model along, and its standard library and tooling are usually most complete on the platform it was designed for.

We also expect the choice of language to matter less over time. As models write more of the code, what counts is that the language fits the job and that agents are good at writing and reasoning about it. Rust's compiler is strict and its error messages are detailed, which gives an agent fast and precise feedback when it gets something wrong.

If we had to pick a stack today, it would look like this:

| Platform | Native edge: UI | Native edge: platform services | Headless core |
| --- | --- | --- | --- |
| iOS, iPadOS, macOS | SwiftUI | [Swift](https://www.swift.org) | Rust |
| Android | Jetpack Compose | [Kotlin](https://kotlinlang.org) | Rust |
| Linux, Windows | [GPUI](https://www.gpui.rs) | Rust | Rust |
| Command line | Terminal | Rust | Rust |
| Web | HTML and JavaScript | Browser APIs | Rust compiled to WebAssembly |

For desktop outside macOS, we'd go with [GPUI](https://www.gpui.rs), the UI framework the [Zed](https://zed.dev) team built for their editor. It isn't the operating system's own toolkit. It draws its own UI on the GPU, but it compiles to a native binary, integrates with each platform, and there's an ecosystem of components around it, such as [GPUI Component](https://github.com/longbridge/gpui-component), for building desktop apps like Zed itself. Since it's Rust too, on Linux and Windows the edge and the core are written in the same language, and there's no bridge between them.

The command line is in the table because a CLI is a native experience too, with the terminal as its platform. Developers notice when a CLI starts fast, follows the terminal's conventions, and works well with pipes and scripts. With a headless core, the CLI is a thin edge on top of the logic you already have, so building one in Rust takes little extra work. Agents often use software through CLIs, so we expect that edge to matter more over time.

## 3. Connect the edges to the core through a small, typed API

The sample uses [UniFFI](https://github.com/mozilla/uniffi-rs), a tool from Mozilla that generates Swift and Kotlin bindings from annotations in the Rust code. The core marks what it exports, and the edges call typed functions and get typed values back:

```rust
#[derive(uniffi::Record)]
pub struct Destination {
    pub route: String,
    pub params: Params,
    pub url: String,
}

#[derive(Debug, uniffi::Error)]
#[uniffi(flat_error)]
pub enum CoreError {
    /// No session, or it expired: show the sign-in screen.
    Unauthorized { message: String },
    Failed { kind: String, message: String },
}

/// Resolves a deep link into its destination and parents.
#[uniffi::export]
pub fn open(url: String) -> Result<Vec<Destination>, CoreError> {
    // ...
}

/// Sends a message and waits for the agent's answer.
#[uniffi::export]
pub fn send(
    id: Option<String>,
    text: String,
) -> Result<Conversation, CoreError> {
    // ...
}
```

In Swift, those are ordinary functions, and the Rust error is a Swift error you can catch. `send` blocks while the agent works, so the sample runs it off the main actor with a small `background` helper of its own:

```swift
let stack = try EdgesCore.open(url: link)
let reply = try await background {
    try EdgesCore.send(id: id, text: text)
}
```

Kotlin gets the same API, with `CoreException.Unauthorized` in place of the Swift error case, and the CLI calls the Rust functions directly. Adding a capability means exporting a function in Rust, and both apps get it with types the compiler checks. The core returns plain values, like a conversation and the URLs it links to, and each edge decides how to present them: a pushed view on iOS, a back-stack entry on Android, or printed output in the terminal.

The API also has to work in the other direction, because sometimes the core needs something only the platform provides. A token refresh rotates the session, and the new session has to land in the Keychain on iOS and in Keystore-backed encrypted storage on Android. For that we use the delegate pattern: the core declares what it needs as an interface, and each edge provides an implementation. With UniFFI, that's a Rust trait marked `with_foreign`, which Swift and Kotlin can implement:

```rust
/// Provided by the edge: the Keychain on iOS, the Keystore
/// on Android, and a private file in the terminal.
#[uniffi::export(with_foreign)]
pub trait SecureStorage: Send + Sync {
    fn read(&self, key: String) -> Option<String>;
    fn write(&self, key: String, value: String);
    fn delete(&self, key: String);
}
```

On iOS, the implementation is a small class over the Keychain, and the app hands it to the core at launch, along with a directory where the core keeps its SQLite database:

```swift
final class Keychain: SecureStorage {
    func read(key: String) -> String? { /* SecItemCopyMatching */ }
    func write(key: String, value: String) { /* SecItemAdd */ }
    func delete(key: String) { /* SecItemDelete */ }
}

let directory = URL.applicationSupportDirectory.path
_ = try launch(dataDir: directory, storage: Keychain())
```

Android passes a `Keystore` class that encrypts the value with an Android Keystore key, and the CLI passes one that writes files only you can read. The core decides what to keep and when, for example saving a renewed session after a refresh, and the edge decides how the operating system keeps it safe. The core's tests pass an in-memory implementation, so they don't need a Keychain or a simulator. The trait is simplified for the sample: in a production app, `write` and `delete` should report failures so the core can decide what to do with them.

## 4. Make every screen reachable by an address

Core tests cover the shared rules, but sometimes you want to test how an edge and the core work together: that a screen renders the data the core returns, or that an action in the UI triggers the right call. Whether you or an agent runs that test, it helps a lot if getting to the screen is quick.

A CLI makes this easy, because every operation is a named command with options and arguments that you can find in the code and run. Web apps are close to that, since every page has a URL that an agent can read from the route definitions and open. Mobile and desktop apps usually have neither, so getting to a screen means launching the app and tapping through every step in between, which is slow and breaks whenever the UI changes. So we think native apps should have a **declarative navigation system** that does two things:

1. **Makes routes discoverable.** Destinations are declared as data, like an enum or a list of types, so someone reading the code, or an agent, can find every place the app can go.
2. **Lets you open any route directly.** A single entry point takes a route, usually as a URL, and builds the navigation state for it, so you can jump straight to a specific screen or record.

How much of this belongs in the core? Navigation itself belongs to the platform. Stacks, tabs, sheets, transitions, and Back behavior are exactly where each platform has strong conventions. The core can own the catalog of routes and the parsing of URLs, so every edge agrees on which destinations exist and what a link means. In the sample, each route has an identifier, a URL pattern, and a parent, so a deep link opens on top of the screens you'd normally pass through, and Back works as if you had tapped your way there:

```rust
// Simplified from core/src/routes.rs.
pub static ROUTES: &[Route] = &[
    Route {
        id: "conversations",
        path: "conversations",
        parent: None,
    },
    Route {
        id: "new",
        path: "conversations/new",
        parent: Some("conversations"),
    },
    Route {
        id: "conversation",
        path: "conversations/{id}",
        parent: Some("conversations"),
    },
];
```

Every edge asks the core what a URL means, and a tap on a row opens that row's URL, so a tap and a deep link go through the same code. An agent can list the routes with the CLI and then open a specific conversation on a simulator or an emulator with a single command:

```sh
edges routes
xcrun simctl openurl booted edges://conversations/011d032b115d6baa
adb shell am start -a android.intent.action.VIEW \
  -d edges://conversations/011d032b115d6baa
```

The routes are shared, but the data isn't: each edge in the sample keeps its own database, so a link only opens a conversation that exists in that app. And because the same URLs can come from notifications and shared links, treat them as untrusted input. A route says where to go, and the core and the server still decide what the user can see.

Each platform already has tools for the edge side:

- **iOS and macOS:** model destinations as a `Codable` enum and drive a [`NavigationStack`](https://developer.apple.com/documentation/swiftui/navigationstack) from a [`NavigationPath`](https://developer.apple.com/documentation/swiftui/navigationpath), then turn incoming URLs into that path in [`onOpenURL`](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:)). Point-Free's [swift-navigation](https://github.com/pointfreeco/swift-navigation) models every destination, including sheets and alerts, as state, so opening a screen is constructing a value. On macOS, `open <url>` does what `simctl openurl` does on a simulator.
- **Android:** [Navigation Compose](https://developer.android.com/develop/ui/compose/navigation) supports type-safe routes declared as `@Serializable` classes, with deep links mapped to them. In [Navigation 3](https://developer.android.com/guide/navigation/navigation-3), the back stack is a list of keys that you own, and deep link matchers turn a URL into the initial back stack.
- **Desktop with GPUI:** GPUI's actions are declared with names and dispatched by name, which is how Zed's command palette lists everything the editor can do. Routes can follow the same pattern, with a command-line flag like `--open <route>` as the way in.

## 5. Model the whole app in one build graph

You can build this architecture with the tools you already have, but we recommend **a build system that can model the entire graph**: the Rust core compiled for each platform, the Swift and Kotlin bindings generated from it, the apps that link them, and the tests for each of them.

Xcode and Gradle work well within their own ecosystems, and Rust usually enters them as a script phase or a custom task that runs [Cargo](https://doc.rust-lang.org/cargo/), or as a prebuilt binary checked into the repository. The outer build system sees one opaque step. Gradle can cache a custom task if you declare its inputs and outputs carefully, but neither tool can schedule or cache the individual crates inside it, so the Rust side ends up rebuilding more than it should.

[Bazel](https://bazel.build) and [Buck2](https://buck2.build) can model all of this, and many teams use them for that reason. They ask you to learn their rules and configure toolchains, and many teams find their developer experience hard to live with. For the sample we used [Once](https://github.com/tuist/once), the build system we're building at Tuist. It models the same kind of typed graph with remote caching, configured in a single TOML file. It's still early and in canary. Here's an excerpt of the sample's [`once.toml`](https://github.com/tuist/native-edges/blob/main/once.toml):

```toml
# The headless core, built once per edge.
[[target]]
name = "CoreIOS"
kind = "rust_library"
srcs = ["core/src/**/*.rs"]
deps = ["./CoreIOSDependencies"]

[target.attrs]
crate_name = "edges_core"
crate_root = "core/src/lib.rs"
target = "aarch64-apple-ios-sim"
crate_type = "staticlib"

# The terminal edge.
[[target]]
name = "CLI"
kind = "rust_binary"
srcs = ["cli/src/**/*.rs"]
deps = ["./Core", "./CoreDependencies"]

# The SwiftUI edge, and the Swift bindings it calls.
[[target]]
name = "SwiftBindings"
kind = "uniffi_bindings"
deps = ["bindgen/Bindgen", "./CoreIOS"]

[target.attrs]
language = "swift"

[[target]]
name = "IOS"
kind = "apple_application"
srcs = ["ios/Sources/**/*.swift"]
deps = ["./CoreIOS", "./SwiftBindings", "./SimulatorSDK"]

[target.attrs]
platform = "ios"
bundle_id = "dev.tuist.edges"
sdk_frameworks = ["Security"]

# The Jetpack Compose edge.
[[target]]
name = "Android"
kind = "android_binary"
srcs = ["android/src/**/*.kt"]
deps = ["./CoreAndroid", "./KotlinBindings", "./Compose"]

[target.attrs]
application_id = "dev.tuist.edges"
min_sdk_version = 26
```

Rust libraries, Apple applications, Android binaries, the bindings between them, and their tests are all targets in the same graph. Third-party crates are resolved from `Cargo.lock` into per-platform dependency targets, so each crate compiles on its own and gets its own cache key, instead of everything being compiled by a single `cargo build`.

The bindings are generated inside the graph too, rather than checked into the repository. Once has no built-in rule for UniFFI, so the sample adds one in a small [Starlark module](https://github.com/tuist/native-edges/blob/main/modules/uniffi.star). It builds `uniffi-bindgen` from source, runs it against the compiled core, and compiles the generated code into a Swift module for iOS and a Kotlin library for Android. The generation step is cached like any other, keyed on the generator, its configuration, and the compiled core.

A graph like this is also what makes caching effective. Each step gets a key computed from its inputs, so a change to a SwiftUI view doesn't recompile the Rust core, and the results can be shared between your machine, your teammates', CI, and agents working in other worktrees. When the work a build does depends on the size of the change rather than the size of the app, native iteration gets much closer to the hot reloading that made web runtimes attractive. Linking, installing, and launching the app still take time, but they no longer come with a full rebuild.

## 6. Keep the graph shallow and wide

When teams think about build times, they usually think about the build system: whether it caches and whether it supports remote execution. The shape of the graph matters as much, and it's easy to overlook because it comes from architecture decisions. A build system can only run in parallel what the graph lets it run in parallel. If your modules form a long chain where each one depends on the previous one, they compile one after another, and a machine with 16 cores or a fleet of remote workers will mostly sit idle. The longest path through the graph, measured in time, is what Apple calls the critical path in its [WWDC talk on build parallelization](https://developer.apple.com/videos/play/wwdc2022/110364/), and no amount of hardware makes the build faster than that path.

The shape also decides how much an edit costs. Incremental builds are most of the builds you run in a day, and when you change a target, the targets that depend on it may have to recompile or relink, depending on what changed and how the compiler and the build system handle it. A remote cache helps only if someone already built that exact state. The more targets sit downstream of the code you touch, the more work an edit can trigger.

So aim for **a shallow, wide graph**, with many targets side by side and few dependencies nested several levels down. It keeps clean builds parallel and incremental builds small. A few practices help:

- **Only add a dependency when you need it.** Every dependency means one target waits for another, and puts the second one downstream of every change to the first.
- **Depend on interfaces, not implementations.** Splitting a module into a small interface module and an implementation module lets features depend on the stable interface, so implementations compile in parallel and changing one doesn't recompile its consumers. Bruno Rocha, who now works on build tooling at Spotify, explains the technique in [Reducing iOS Build Times by using Interface Modules](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets).
- **Keep shared foundations small and stable.** A module everything depends on is on everyone's critical path, and changing it invalidates most of the graph.
- **Look at the build timeline, not only the total.** Long stretches with a single task running point to a chain worth breaking up, or to one expensive step, like a link, that deserves attention.

Spotify's account of [moving its iOS app to Bazel](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly) shows the two working together. Their CI feedback loop went from 80 to 20 minutes. They credit remote caching and remote execution, and also the work on module isolation and app architecture that ran alongside the migration, which let them build and test only the parts of the graph a change affected.

The sample is small, but its graph has this shape. Each edge depends only on its build of the core and its own platform libraries, no edge depends on another, and the core's builds for each platform are independent of each other too. In a larger app, the same applies to features: give each one its own state instead of routing everything through a global model, and add a target only where there's a real boundary.

## 7. Compile only what each edge needs

Edges need different things from the core. A CLI doesn't need the code that only a widget uses, a widget doesn't need the whole business API, and a web build pays for every kilobyte it ships. Linkers can strip some unused code, but you get much more control if the graph lets each edge include or leave out pieces of the core at compile time.

There are two levels to this. Within the code, Rust's [conditional compilation](https://doc.rust-lang.org/reference/conditional-compilation.html) and [Cargo features](https://doc.rust-lang.org/cargo/reference/features.html) let you leave out code that a target doesn't use. Within the graph, each edge depends only on the targets it uses. In the sample, the iOS app depends on the Swift bindings, the Android app on the Kotlin bindings and [JNA](https://github.com/java-native-access/jna), which those bindings load the core through, and the CLI on neither. A larger app can go further and split the core into crates along real boundaries, so that, for example, a widget that only shows the latest conversation depends on the storage crate and never links the networking code. The same splits that keep the graph wide also keep each edge small.

## Adopting native edges

### Starting with one platform

You don't have to design the core up front. We like to start building for one platform and move logic into the core as soon as it looks reusable. A few signs that something belongs there: it doesn't import any platform framework, another platform would need exactly the same behavior, or you'd want to test it without launching the app. Typical candidates are:

- The API client: routes, request and response types, validation, and error mapping.
- Authentication: building the sign-in URL, exchanging codes for tokens, and refreshing them.
- Pagination, search, and filtering rules for lists.
- Form validation, like which fields are required and what a valid date range looks like.
- The route catalog and deep-link parsing.
- Local caching and reconciling data after a reconnect.

When you add the second platform, most of the work is building a new edge on top of a core that already exists and is already tested. The same rule applies as features evolve: when a Swift or Kotlin model starts making business decisions, that logic moves into the core.

### If you already have clients

Most teams won't start from scratch. If you already have clients on several platforms, each written in its platform's language and built with its own tools, we'd start by modeling them in one build graph connected to a remote cache. That pays off on its own, before any code moves, and it's what makes adding a Rust core affordable later. Then pick one piece that's duplicated across your clients, like the API client, authentication, or validation rules, and move it into the core. While you do it, think about what your app would look like as a CLI or a set of commands an agent can run. Each piece you move is one less thing to write twice, and over time the edges get thinner until they mostly contain UI and calls to platform APIs. Your clients keep shipping the whole time.

### What we're doing at Tuist

The native clients of [Atlas](/blog/2026/09/23/atlas-what-we-built-next), our internal operations platform, are built with these principles in mind: an iOS and macOS app in SwiftUI, an Android app in Kotlin, and a CLI, all on one Rust core. We're also taking the first steps to move Tuist's own clients to the same model. Across them, we've found a lot of duplicated logic. Most of it is written in Swift, and some of it we've had to write again in Kotlin and other languages, so we're moving that headless layer into a shared core in Rust, with the CLI and the apps as its edges. We'll share more as it takes shape.

We're still early, and the sample is deliberately small, so treat this as an exploration. If you want to try the principles, the [sample app](https://github.com/tuist/native-edges) and [Once](https://github.com/tuist/once) are both on GitHub, and we'd love to hear what you build.
