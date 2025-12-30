---
title: "A Mise guide for Swift developers"
category: "learn"
tags: ["tooling", "devtools"]
excerpt: "In this blog post we share how to use Mise to install, activate, and share tools to enhance Swift development."
author: pepicrft
---

When building with Swift, [Apple](https://apple.com) provides a comprehensive toolchain through the [Xcode](https://developer.apple.com/xcode/) installation. Running `swift run` seamlessly builds and executes your code using the Swift compiler, eliminating concerns about the underlying toolchain. However, additional tools like [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) or [swift-openapi-generator](https://github.com/apple/swift-openapi-generator) may be required. These tools need to be installed on your system, raising the question of how to manage their installation—not only for developers' environments but also for CI/CD pipelines. In this blog post, we’d like to introduce you to [Mise](https://github.com/jdx/mise), a tool that not only addresses the installation and distribution of tools but also ensures they are activated deterministically so that everyone is using the same version of the tools.

## What is Mise?

Mise is a front-end for your development environment.  
Okay, that might sound abstract, but if we talk about the problems it solves, it becomes clearer.  
Almost every project has:

1. A set of tools it depends on.
2. A set of scripts to interact with the project from the terminal.
3. Environment variables to configure the interaction with the project.

Traditionally, developers address the first point with [Homebrew](https://brew.sh), telling developers in the `README.md` file what additional tools need to be installed. However, this approach is not ideal. First, it’s manual, and second, there’s no mechanism to ensure the presence of not only the tools but **the right version of the tools**. The second point is usually handled with `Makefiles`, custom bash scripts, Ruby scripts run by [Fastlane](https://fastlane.tools), or a mix of everything. If Fastlane is the tool, it requires developers to have Ruby installed, along with the Ruby dependencies (i.e., `gems`) installed via `bundle install`. Do you start to notice the amount of indirection? As for the third point, which is less common, it’s usually addressed by instructing developers in the README to introduce project state into a global environment, which is generally not a good idea.

Now, imagine simplifying all of the above to just one command:

```bash
mise install
```

Well, that’s what a front-end for your development environment is all about. Now that we’ve understood what Mise is, let’s walk through some of its features and how they can be valuable in the context of app development with Swift. Before continuing, make sure you have Mise installed on your system. You can install it by following [these steps](https://mise.jdx.dev/getting-started.htm).


## Dev tools

The first and most core feature of Mise is the ability to install and activate [dev tools](https://mise.jdx.dev/dev-tools/). Note that we say "activate" because, unlike Homebrew, Mise differentiates between installing a tool and making a specific version of it available. Thanks to this, you have control over which version of the tool is activated—either globally or scoped to a particular project. For example, let’s say we have a project that uses SwiftFormat, SwiftLint, and Tuist. We can create a mise.toml file with the following content:


```toml
[tools]
tuist = "4.39.1"
swiftlint = "0.54.0"
swiftformat = "0.53.3"
```

Then, run `mise install`. This command will not only install the tools but also activate those specific versions. If you run `swiftlint --version`, you’ll see that it’s using the version specified in the `mise.toml` file. This might seem like a subtle detail, but inconsistent versions across environments are often a common source of wasted time debugging issues.

### Backends

"How" to install a specific dev tool is determined by what Mise calls "backends." By default, Mise tries to use the [asdf](https://asdf-vm.com/) backend. asdf is another developer tool for installing developer tools, and the installation logic for each tool is declared in what they call plugins. For example, in the case of SwiftLint, there’s an [official plugin](https://github.com/mise-plugins/mise-swiftlint) that declares how to install SwiftLint.

But what if you want to depend on a Swift CLI contained in a repository that doesn’t have a plugin? Well, there’s the [SwiftPM](https://mise.jdx.dev/dev-tools/backends/spm.html) backend. In other words, Mise knows how to install it automatically without needing a plugin or a script that instructs Tuist on how to do so. If you’re familiar with [Mint](https://github.com/yonaskolb/Mint), think of the SwiftPM backend of Mise as Mint. The amazing thing about Mise is that you don’t need a tool per language or technology. You can use one tool to rule them all. In your `mise.toml`, you could declare the tool like this:

```toml
[tools]
"spm:owner/repo" = "latest"
```

> The backend will compile the CLI on the host, which may take some time and potentially fail if the required toolchain is not present. Therefore, it’s always recommended to provide binaries. However, as long as your CLI is not that big, this is a good way to get started.

Thanks to the dev tools in the `mise.toml`, you no longer need a lengthy list of steps in the README telling developers which tools they need to install.

## Hooks

Let’s now talk about [hooks](https://mise.jdx.dev/hooks.html). Some projects might require additional steps beyond installing tools. For example, if you’re using Tuist, you might need to run `tuist install`, or if you’re using Fastlane, you might need to run `bundle install` to install the Ruby dependencies. Mise allows you to define hooks that can run at certain moments, such as when cd-ing into a directory or after running `mise install`. The latter is particularly useful in the context of app development because it’s the place where we could install Ruby dependencies and SPM packages:

```toml
[hooks]
postinstall = [
  'bundle install',
  'tuist install'
]
```

## Environment variables

Mise also allows activating environment variables and secrets when entering a particular project. Unlike other ecosystems, using environment variables to configure Xcode behaviors is not that common. However, there’s a capability in Mise that can be quite useful in improving the ergonomics of your automation: Mise allows configuring the `PATH` environment variable, which is used by the system to resolve executables. Why is that useful? You might wonder. Well, if you’re a Fastlane user and are a bit tired of having to prefix your commands with `bundle exec`, you can use the following Mise configuration:

```toml
[tools]
ruby = "3.4.1"

[hooks]
postinstall = [
  'bundle install --binstubs=.bundlestubs',
]

[env]
_.path = [".bundlestubs"]
```


## Tasks

Tasks are the last feature we’d like to talk about. At Tuist, we use them extensively across our repositories. Think of them as language-agnostic Fastlane lanes or Makefiles with superpowers. Tasks are scripts that you can invoke with `mise run`. They can be defined in the [`mise.toml` file](https://mise.jdx.dev/tasks/toml-tasks.html) or in [files](https://mise.jdx.dev/tasks/file-tasks.html) following a conventional structure that’s then used to construct the full command name. We lean on using files to keep the configuration file tidy. For example, let’s say you’d like to have a task, build, to `build` the scheme `MyApp` of your project. You can create a file at `.mise/tasks/build.sh` with the following content:

```bash
#!/usr/bin/env bash
#MISE description="Build MyApp"
#MISE alias="b"
#USAGE flag "-n --no-signing" help="Disable the signing"

if [ "$usage_no_signing" = "true" ]; then
  xcodebuild -scheme MyApp -workspace $MISE_PROJECT_ROOT/MyApp.xcworkspace clean build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
else
  xcodebuild -scheme MyApp -workspace $MISE_PROJECT_ROOT/MyApp.xcworkspace clean build
fi
```

You can run it with `mise run build`, or more interactively, run `mise run` and then select the task you want to run from the terminal. Cool, isn’t it?

There’s a lot to parse in the above script. Did you notice those annotations under the [shebang](https://en.wikipedia.org/wiki/Shebang_(Unix))? They are annotations used by Mise to provide extra capabilities. The description is used by Mise to show the description alongside the task name when listing the tasks, making it easy to recognize what the task does. You can also define aliases for the task. In the case above, we defined the alias `b`, which allows running `mise run b`. Last but not least, one of our favorites: the USAGE annotation. Usage is a [specification](https://usage.jdx.dev) to declare the interface of a CLI. Thanks to having a standard specification, it can be codified using comments, which Mise will use to parse and validate arguments for you, and then provide you with the values as environment variables. Thanks to that, we can turn our scripts into mini CLIs without having to include parsing and validation logic in the scripts:

```bash
mise run build --no-signing
```

Note that we wrote the above script in bash, but you could have chosen your language of choice, such as Ruby. By adding the tool to the `mise.toml` and updating the shebang to `!#/usr/bin/env ruby`, you can have the peace of mind that everyone will be able to run the script because Mise will take care of installing the right version of Ruby.

## Some closing words

We think Mise is amazing. It’s a love letter to automation.
When we gave it a try for the first time, we didn’t think twice about embracing it as one of our installation methods and making Tuist play an evangelist role in the Swift ecosystem.
We recommend giving it a try in your projects and experimenting with it across local and CI environments.
We bet you’ll find it as useful as we did.
