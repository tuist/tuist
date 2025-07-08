---
title: "Automate your Swift projects"
category: "product"
tags: ["automation", "swift", "fastlane", "scripting", "sake", "mise"]
excerpt: "We compare various automation options for Swift projects including Fastlane, Sake, swift-sh, bash, and other scripting languages. Our guide presents practical examples and trade-offs to help developers select the most appropriate solution for their specific needs, suitable for both newcomers and those evolving existing automation setups."
author: pepicrft
---

**Audience: Developers who are new to the ecosystem and have recognized the need for automation, or developers with existing codebases that include automation who are looking to evolve their setups. All examples mentioned in this post are included in [this repository](https://github.com/tuist/automation-in-swift-projects-reference) for your reference.**

If you are an app developer, you most likely want to automate certain tasks in your projects, such as publishing your app to the [App Store](https://www.apple.com/app-store/) or running tests from the terminal. [Apple](https://apple.com) provides the foundational building blocks for these automations, which are included in the OS and in Xcode's toolchain. However, in many cases, these tools are too low-level, requiring a layer of convenience through defaults or the construction of more advanced workflows that connect these low-level components—potentially parallelizing some of the steps for improved efficiency.

In this comprehensive post, we'll explore a non-exhaustive list of relevant options that you might consider adopting for your projects. Each approach has its unique strengths and trade-offs, which we'll examine to help you make an informed decision based on your specific needs and constraints.

## Fastlane: The established solution

[Fastlane](https://fastlane.tools/) is a well-established solution in the automation space. If you're new to app development, this might sound unfamiliar, but virtually everyone who has been developing apps for a while knows about Fastlane and its capabilities.

Fastlane is a [Ruby](https://www.ruby-lang.org/en/)-based solution that provides a Domain Specific Language (DSL) for defining workflows, along with a set of low-level tools that fill certain gaps in the underlying Apple tools. It adds convenience through more sensible defaults and streamlined processes. Its greatest strength lies in its vast [ecosystem of plugins](https://docs.fastlane.tools/plugins/available-plugins/), most of which were developed and are maintained by the community. These plugins are distributed as Ruby dependencies using Ruby's dependency management system, [Bundler](https://bundler.io), and can be added with a single command or line of code.

One of the perceived downsides of Fastlane is that you might need to familiarize yourself with Ruby if you haven't written it before. The inconsistency between the language used by Fastlane (Ruby) and the one used to develop your app (Swift) might feel uncomfortable, and that explains the emergence of other solutions that aim to take on the role of Fastlane. However, by choosing an alternative, you'd be trading away Fastlane's extensive ecosystem—something that's not easily replicated by newer tools.

To use Fastlane effectively, you'll need to add Ruby and Fastlane as dependencies of your project, and then create a `Fastfile`, which is the place where you'll define your project's automation. With [Mise](https://mise.jdx.dev), you can do this easily in your `mise.toml` file:

```toml
[tools]
ruby = "{{ get_env(name='RUBY_VERSION', default='3.4.3') }}"
"gem:fastlane" =  "2.227.1"
```

With a simple `mise install` command, you'll get the environment provisioned with the necessary dependencies. You can then create a `fastlane/Fastfile` where you'll declare what Fastlane calls "lanes." Think of lanes as workflows or tasks that encapsulate a series of related operations. For example, the following lane builds a project:

```ruby
lane :build do
  gym(
    project: "Automation/Automation.xcodeproj",
    skip_package_ipa: true,
    skip_archive: true,
    skip_codesigning: true
  )
end
```

This example is quite simple, but in your actual tasks, you'll most likely add more steps that will run sequentially before or after the project builds. For instance, you might include steps to provision your environment to enable proper app signing, run tests, or perform post-build validation.

## Sake: Swift-based automation

If you prefer to align the automation language with your application programming language (i.e., [Swift](https://www.swift.org)), another interesting solution is [Sake](https://sakeswift.org/), which draws inspiration for its name and approach from the well-known [Make](https://www.gnu.org/software/make/) build automation tool. A Sake setup is a [Swift Package](https://www.swift.org/documentation/package-manager/) with a Command Line Interface (CLI) and API that provides a layer of convenience around lower-level tools.

Modeling your automation as a Swift Package allows Sake to leverage SwiftPM as both a build tool and dependency manager. This is particularly useful if you want to reuse Swift Packages implemented by the community, such as a [Swift SDK](https://github.com/AvdLee/appstoreconnect-swift-sdk) to interact with the [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi).

Continuing with our example of building an app, we can implement the same logic as in the Fastlane example in a Swift `Sakefile` file:

```swift
import Foundation
import Sake
import Command
import Path

@main
@CommandGroup
struct Commands: SakeApp {
    public static var build: Sake.Command {
        Command(
            run: { _ in
                let sakefilePath = try AbsolutePath(validating: #file, relativeTo: try AbsolutePath(validating: FileManager.default.currentDirectoryPath))
                let rootDirectory = sakefilePath.parentDirectory.parentDirectory
                
                try await CommandRunner().run(arguments: [
                    "/usr/bin/xcrun", "xcodebuild",
                    "-project", rootDirectory.appending(components: ["Automation", "Automation.xcodeproj"]).pathString,
                    "-scheme", "Automation",
                    "-destination", "generic/platform=iOS",
                    "CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''"
                ]).pipedStream().awaitCompletion()
                
            }
        )
    }
}
```

The first thing you'll notice is that this is written in Swift, a language with which you're likely already familiar if you're developing iOS apps. Conceptually, the idea is similar to Fastlane, where you have tasks that are executed in sequence. In Sake, these tasks are declared as static variables in a `@main` struct.

Another aspect you'll notice if you run Sake for the first time is that **it will take some time** to fetch the dependencies and warm the build cache. If you're accustomed to scripts in bash or interpreted languages, this might initially feel like a degradation in developer experience. However, subsequent runs should be much faster once the dependencies are cached. Think of Sake as trading Fastlane's instant launch time for the ability to write your automation in Swift, a language you're already using for your app development.

## swift-sh: Single-file Swift scripts

In a similar vein as Sake, there's another tool that allows you to write your scripts in Swift: [swift-sh](https://github.com/mxcl/swift-sh). Like Sake, swift-sh undergoes a dependency-fetching and building process, so cold runs will take time to complete. However, swift-sh completely abstracts away packages to the point that your workflow is literally one portable file with annotations at the top for declaring dependencies.

We can transform the previous script into a one-file swift-sh script:

```swift
#!/usr/bin/swift sh

import Command  // tuist/command ~> 0.13.0
import Foundation
import Path  // tuist/path ~> 0.3.8

if CommandLine.arguments.count == 2 {
    let projectPath = try AbsolutePath(
        validating: CommandLine.arguments[1],
        relativeTo: try AbsolutePath(validating: FileManager.default.currentDirectoryPath))

    try await CommandRunner().run(arguments: [
        "/usr/bin/xcrun", "xcodebuild",
        "-project",
        projectPath.pathString,
        "-scheme", "Automation",
        "-destination", "generic/platform=iOS",
        "CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''",
    ]).pipedStream().awaitCompletion()
    
} else {
    print("Usage: ./build.swift path/to/project.xcodeproj")
    exit(1)
}
```

Swift-sh achieves script portability by leveraging annotations placed next to imports. These annotations are then converted to a SwiftPM package in a global cache directory for you behind the scenes. One caveat of this approach is that since the files are copied into the cache directory, we can't obtain the root of the project's directory relative to the path of the script.

One option could be to make paths relative to the working directory, but that would couple the execution of the script to the root directory, which is not ideal for flexibility. In the above script, we decided to pass the path as the first argument when invoking the script: `./build.swift Automation/Automation.xcodeproj`. This approach makes the script more versatile and usable from different locations.

We haven't discussed argument parsing yet, but in both Swift approaches—Sake and swift-sh—you can make use of Apple's excellent [swift-argument-parser](https://github.com/apple/swift-argument-parser) package to declare and parse command-line arguments. You can use [this example](https://sakeswift.org/advanced-argument-parsing.html) as a reference for implementing more sophisticated argument handling.

## Bash: Unbeatable portability

Perhaps the most obvious approach, but still worth mentioning, is writing your scripts in bash. Bash scripts offer unbeatable portability and launch time advantages. They run instantly on virtually any Unix-like system without requiring any additional runtime or dependencies.

The primary challenge with bash scripts is, well... writing bash. It's not the most enjoyable scripting language to use for complex tasks. The syntax might feel too verbose, and pieces of logic can be difficult to encapsulate and reuse effectively. However, Large Language Models (LLMs) are changing this landscape dramatically.

LLMs are becoming increasingly capable of writing code, and scripting code is something they can do very well, including bash. This approach is becoming so popular that developers have coined a term for it: ["vibe coding."](https://en.wikipedia.org/wiki/Vibe_coding) You can effectively "vibe code" your bash scripts, and it's easier than you might think. These scripts generally require low maintenance, but even when maintenance is needed—for example, to add functionality or optimize performance—you can also leverage LLM solutions to assist with these tasks.

Here's a simple bash script example that performs the same build operation:

```bash
#!/usr/bin/env bash

set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

/usr/bin/xcrun xcodebuild \
  -project $ROOT_DIR/Automation/Automation.xcodeproj \
  -scheme "Automation" \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

Note in the example above that, similar to Sake, we can easily get the directory containing the script and use it to construct the path to the Xcode project. If you compare this approach to the Swift and Ruby versions, it's slightly more verbose but not significantly so. Things might become more complex as you add control flows and error handling, but you'd be surprised at how manageable these scripts can remain, especially with the help of modern tools and LLMs.

If you'd like to define a user-friendly interface for your bash scripts—for example, to pass flags and arguments—doing so in pure bash can result in a lot of boilerplate code. Fortunately, [usage](https://github.com/jdx/usage), created by the same developer as Mise, allows you to define that interface using comments in the script:

```bash
#!/usr/bin/env -S usage bash
#USAGE flag "-c --clean" help="Clean the project before building"

if [ "$usage_clean" = "true" ]; then
  # Call xcodebuild passing the 'clean' argument
fi
```

Note the change in the shebang line, which now runs `usage bash` instead of just `bash`. The "usage" tool will parse the `#USAGE` comments to construct the command-line interface for you, parse the provided arguments, and expose them as environment variables that follow the naming convention `usage_$name`. This approach significantly reduces the amount of boilerplate code needed to handle command-line arguments in bash scripts.

## Other scripting languages: Python and JavaScript

Another automation approach that you might consider involves dynamic and interpreted languages such as [Python](https://www.python.org) or [JavaScript](https://developer.mozilla.org/en-US/docs/Web/JavaScript). If your team feels comfortable writing in these languages, they can be excellent options for automation tasks. Like Ruby (e.g., Fastlane), these languages run scripts instantly without a compilation step, and they provide access to extensive ecosystems of libraries—perhaps not as mobile-tailored as the ecosystem that Fastlane has built over the years, but still rich and diverse.

You can leverage [Mise](https://mise.jdx.dev) to provision the environment with the runtimes necessary to run these scripts, such as Node.js or Python, and use the package managers of those ecosystems to pull in the dependencies your scripts require. In the case of JavaScript, there are modern runtimes like [Deno](https://deno.com) that take a dependency-resolution approach similar to swift-sh, where the dependencies are declared directly in the scripts themselves. For example:

```js
#!/usr/bin/env -S deno run --allow-run --allow-read

const command = new Deno.Command("/usr/bin/xcrun", {
  args: [
    "xcodebuild",
    "-project",
    "Automation/Automation.xcodeproj",
    "-scheme",
    "Automation",
    "-destination",
    "generic/platform=iOS",
    "CODE_SIGNING_ALLOWED=NO",
    "CODE_SIGNING_REQUIRED=NO",
    "CODE_SIGN_IDENTITY=",
  ],
  cwd: new URL(".", import.meta.url).pathname,
  stdout: "inherit",
  stderr: "inherit",
});

const child = command.spawn();
const status = await child.status;
Deno.exit(status.code);
```

JavaScript runtimes like Deno provide you with an extensive standard library and ecosystem of packages that rival what Fastlane offers through Ruby. They also benefit from the widespread familiarity of JavaScript among developers, making them accessible to team members who might not be Swift or Ruby experts.

## Closing words: Finding your automation path

There's no perfect solution that fits all projects and teams. If you value having access to a rich ecosystem of plugins specifically designed for mobile app development, then Fastlane might be your best choice. However, with LLMs now capable of generating automation code in languages that might otherwise be tedious to write, such as bash, Fastlane's plugins as units of encapsulation and reusability might not be as critical as they once were.

This shifting landscape means you might want to lean toward the side of portability, which bash scripts can provide. But once again, with tools like Mise being able to provision environments quickly and reliably, portability becomes less of an issue because you can reasonably assume developers will have the right environment to run the script.

What factors remain, then, in making your decision? The joy and efficiency of writing and maintaining those scripts is a significant consideration, which many teams might find in using Swift. With Swift, you'd be trading away the instant launch time of interpreted languages, but hopefully, this is something that Apple will address in the future, meaning it won't be as much of an issue long-term. However, don't expect the immediate responsiveness of running a bash, Ruby, or Python script.

Note that you can mix-and-match. For example, you can use Bash scripts for small workflows, and use Swift for more advanced ones such that you can leverage the expressiveness of the language. If you're curious about our approach at Tuist, we leaned into the portability and instant launch time of bash, while leveraging LLMs to help us write and maintain our scripts. This combination has proven effective for our specific needs and workflows.

Our final advice: Don't feel tempted to simply adopt what everyone else is doing, and don't be afraid to pursue a path that feels unconventional for your team. The low-level building blocks have become more capable over the years, so some of the abstractions the community has settled on might no longer be necessary for your specific use case. You'll often be surprised by how far you can go with a simple bash script and an LLM helping you in the process.

Regardless of which path you choose, we recommend leveraging [Mise](https://mise.jdx.dev) to provision the environments that your scripts depend on, and [owning your automation](/blog/2025/03/11/own-your-automation) such that it's not coupled to any particular platform. Remember: your automation belongs to your project and should serve your specific needs.
