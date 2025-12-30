---
title: "Own your Swift apps' automation"
category: "product"
tags: ["ci", "automation"]
excerpt: "Discover how to increase flexibility in your CI workflow for Swift apps by taking ownership of your automation and reducing provider dependencies."
author: pepicrft
---

Technology evolves very rapidly these days.
This is great, because there's more innovation and more opportunities.
However,
it also means non-crowded markets filled with innovation eventually become crowded and stagnate.
What used to be your economic moat is now a commodity.
And what used to be your competitive advantage is now an expected baseline.

Since a business's ultimate goal is to grow and stay relevant,
they need to adapt accordingly.
Some design their business environment to foster innovation.
This becomes more challenging as the company grows,
and is in fact what makes [open source companies](https://pepicrft.me/blog/2025/03/04/tuist-mental-models) outcompete their closed-source counterparts.
Other companies focus on building ecosystems where more players are incentivized to keep their business relevant.
I'd say it's the proprietary version of the open-source ethos.
If you think of Apple's app store, that's what it is.
And last but not least, some companies invest in creating seamless experiences that increase customer retention.
The integrated nature of their solutions provides such value that customers choose to stay.

## Continuous integration

What does all of this have to do with Swift apps' automation? A lot more than you might think.
Last year, while chatting with an app developer,
he shared that they were renovating their contract with their CI provider,
that the price had increased significantly,
and that there was a company that even offered to take care of migrating their pipelines.
I was surprised by this situation in CI,
especially considering there are many choices these days to choose from.
What opportunities might we be missing as an ecosystem?

This brings me to an interesting dilemma, which you can apply to many aspects of life, and is closely related to how services evolve over time, sometimes prioritizing profit over values.
If you find yourself in a position where a service price increases substantially, and you feel constrained in your options,
should it be your responsibility to maintain flexibility,
or should that be the responsibility of the service provider?
Ideally both parties would work together on this, but in today's world, maintaining your own flexibility is valuable.

We've reached this position partly because we've often entrusted CI providers with full ownership of our automation.
It's completely understandable.
When you're reading docs on how to set up a CI pipeline,
you don't have time to think deeply about the long-term implications of choices made based on those suggestions,
but some of them implicitly create strong dependencies on the service provider,
which can eventually limit your options.

In this post, I'd like to share why taking more ownership of your automation might be beneficial in today's CI landscape,
where dependencies naturally form and what you can do about it with today's tools, and share a bit about our approach to CI and our future plans.

## Why owning your automation is a good idea

There are several benefits to owning more of your automation:

- **Portability:** In a world with many options, it's valuable to maintain flexibility to move between providers if needed (e.g., when your needs or circumstances change).
- **Debuggability:** If you own your automation, you can debug it easily because your automation is environment agnostic. You can run it locally or in any CI provider. At the end of the day, those should just be macOS environments with the development tools installed.
- **Flexibility:** When relying heavily on specific CI providers, you're constrained by the DSL of their pipelines and their capabilities. Many choose YAML as a format, which isn't always the most expressive language for complex automation needs.

Moreover, Git platforms like [GitHub](https://github.com), [GitLab](https://gitlab.com), and [Codeberg](https://codeberg.org) have incorporated CI capabilities where you can bring your remote build environments with services like [Cirrus Runners](https://cirrus-runners.app/) and [Depot](https://depot.dev/). Thanks to that, you have a CI experience that's more tightly integrated with the platform where developers are already spending their time.

The provisioning of [macOS build environments](/blog/2025/02/12/vm) might get commoditized too by cloud providers like AWS, so at that point you might be able to just add your AWS credentials to your Git platform and voilà.

Because the space is changing rapidly, especially with projects like [Dagger](https://dagger.io/), we think the time is perfect to start thinking about taking greater ownership of your automation. Let's talk about pipelines first.

## CI pipelines

When you think about the capabilities of a CI provider and how they're reflected in your pipelines, we can group the steps into the following categories:

1. **Installing environment tools:** Like `Fastlane`, `swiftlint`, or `tuist`. In many cases, you find steps that run `brew install`, and in other cases, you use steps from the provider, like with GitHub Actions where you have `actions/setup-xxx` steps that encapsulate the installation of tools.
2. **Caching needs:** Pipelines also allow declaring cacheable directories along with the logic for calculating a hash to store and restore them.
3. **Core action:** Every job usually has a core action, that's either a call to the language toolchain (e.g. `swift test`) or to some script that extends the underlying command with some pre and post logic and defaults. In the context of Swift app development, it's common to find invocations to Fastlane lanes, `bundle exec fastlane build`.
4. **Exposing secrets:** That are configured through their UI, exposed as environment variables to the pipeline, and filtered out from the logs.
5. **Job composition:** Then there are some pipeline primitives to combine jobs (e.g. run this one after that other one completes, or run these two things in parallel). This is an area where some companies have invested more than others, for example by providing a visual editor for the pipeline.

Let's talk about how you can take more ownership of each aspect.

## Installing tools

It's common to see repositories having an `install.sh` script, or steps in the README.md that developers can execute or follow to install the tools. In some cases, the same script is run on CI, and in other cases, they use community steps that come with caching capabilities built-in.
As we covered in [this post](/blog/2025/02/04/mise), this is something that you can solve with Mise, and have a unified solution that works across environments (local and CI). All you need is a `mise.toml` file with the tools your project depends on:

```toml
[tool]
swiftformat = "0.55.5"
ruby =  "3.4.2"

[hooks]
postinstall = "bundle install"
```

So all you need in your pipelines and in your local environment is a `mise install` command. Simple, isn't it?
Mise also supports installing any SwiftPM package that's publicly available in a repository by using the convention:

```toml
"spm:account/repo" = "1.2.3"
```

And even install tools written in other programming languages by pulling the binaries using [UBI](https://github.com/houseabsolute/ubi) or letting Mise compile them from the source, for example Go or Rust CLIs.

A side advantage of adopting Mise is that you minimize issues related to inconsistent versions, and you can adopt tools written in other languages or that run in other runtimes, like Fastlane and Ruby, without worrying too much about whether developers will be able to provision their environment successfully. That's all delegated to Mise.

Mise all the things!

## Caching

This is one of the more challenging aspects.
Not because it's impossible to solve, since you could use a CLI to store and restore artifacts using an S3-compliant storage,
but because the process would be quite involved and you'd need to build your own hashing function.

We started working on addressing this with [cache](https://github.com/tuist/cache), a tool that brings declarative caching capabilities to any scripts.
We are drawing inspiration from [usage](https://usage.jdx.dev/) regarding the design.

```bash
#!/usr/bin/env cache bash
# CACHE paths [".build"]
# CACHE key ".."
# CACHE restore_keys [...]
```

## Action

This is an area the Swift ecosystem solved a long time ago with [Fastlane](https://github.com/fastlane/fastlane),
and it's something that many organizations use today.
Fastlane provides sensible defaults to the underlying tooling, 
and has its own system for encapsulating and distributing shareable units of automation called lanes through Ruby gems.

Since Fastlane was created and popularized, a lot has changed,
and we're starting to notice evolving preferences.
Apple's toolchain has gotten better and more capable.
We have LLMs that facilitate writing in languages like Bash, making scripts more portable without requiring a Ruby runtime.
Note that by moving to something like Bash,
you'd trade having access to an ecosystem of steps,
but Bash has a registry too, [Basher](https://www.basher.it/),
and with LLM-based code editors being able to write most of your automation code these days,
the need for sharing or accessing shared steps is not as pressing as it used to be.

At Tuist, all our scripts are bash. Once written, we barely touch them. You can model them as [Mise tasks](https://mise.jdx.dev/tasks/) and use comments in the script to declare the CLI interface:

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

## Secrets

Another capability of CI providers,
one that in fact makes debugging pipelines harder,
is exposing secrets and redacting them from the logs.

The former is something that Mise solves with their [secrets](https://mise.jdx.dev/environments/secrets.html) capability.
So your secrets can be part of your repository, but they're encrypted using a pair of public and private keys.
This offers advantages over managing through your CI provider's UI, some of which don't have a record of the changes that happened in the past and the reasons that motivated them. With Mise's approach, that information is in the repo.

You can have one or multiple `.env.json` files, each representing an environment, and they are encrypted, so only the person (or the environment) with the private key can decrypt them.

Note that you'll need to be careful not to print their values through standard output. CI services redact the output, but by shifting secrets to your repo, that becomes your responsibility. This is something we (or Mise) might build tooling for in the future.

## Job composition

Pipelines typically do things like run x and y in parallel, or on failure of x, run y. On top of this ability, CI providers build features like UI that allows you to visualize the concurrency and the timeline of the execution.

Note that concurrency is something that you can achieve within a single action. Most of the work that you'll do from there are IO-bound operations, like interacting with the network, or running a system process, and all runtimes provide a way to spawn multiple processes and wait for them to finish. In the context of Swift, this would be creating a task group and adding tasks to it.

Note that by doing that, we're making different tradeoffs:
1. The ability to retry individual steps.
2. The ability to visualize the pipeline execution.
3. The ability to work around concurrency limitations of underlying tools (e.g. number of simulators running)

We believe all of these challenges are solvable while maintaining flexibility, as [Dagger](https://dagger.io/) is demonstrating, but exploring them in the context of app development is an opportunity that's still open.

## What's next?

As you might have noticed, there are already many things you can do to increase your flexibility when working with CI providers, ensuring you can choose solutions that best fit your needs. While we're not yet at the ideal state in terms of tooling to maximize this flexibility, this is where we'd like Tuist to help. In the following months we'll explore:

- Bringing the declaration of caching needs closer to scripts and offering it as an open source commons that's platform and language agnostic.
- Building another open source tool and toolkit to redact secrets, and maybe hooking Mise into it to use it as a backend.
- Drawing inspiration from Dagger, and exploring what a Swift-based DSL that's CI-platform independent would look like. Unlike them, we won't virtualize using Docker, because for Swift apps, we need a macOS environment. We'll apply many of the learnings from building the generated projects' DSL. We'll use the toolchains for redacting the secrets and caching.
- Exploring alternative ways to enhance job composition. This is an area we're still exploring, so stay tuned.
- Also drawing inspiration from Dagger, we'll investigate if we can build a CLI-first experience for CI, where you can do things like piping logs to your terminal.

We strongly believe everyone should have the freedom to choose the CI provider that aligns with their values and needs, and we're excited to contribute tools that enhance this flexibility for developers.