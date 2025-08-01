---
title: Releasing Tuist 2.0
category: "product"
tags: ['Tuist', '2.0', 'Xcode', 'Swift', "Project generation"]
excerpt: In this post, we share more details about this new major version of the project, 2.0, and present the direction we are taking as we move towards 3.0.
author: pepicrft
type: release
---

After over [5 thousand commits](https://github.com/tuist/tuist/commits) from [120 contributors](https://github.com/tuist/tuist/graphs/contributors) and over three years after we landed the first commit on the project,
I'm thrilled to share with all of you that we released the second major version of the project, [Tuist 2.0](https://github.com/tuist/tuist/releases/tag/2.0.0).

As you might know,
projects that follow [semantic versioning](https://semver.org/) use major versions to flag breaking changes in the release.
From the user standpoint, that can be seen as unfavorable because the migration is usually manual.
However,
breaking changes are often necessary to continue to improve the developer experience (DX).
In this new major iteration of Tuist,
we're  **moving away from poor API designs**,
replacing some of them with **more straightforward and convenient APIs**,
and **pruning features** that were distant from the project's direction.

Because the release already provides [release notes and migration guidelines](https://github.com/tuist/tuist/releases/tag/2.0.0),
I won't repeat myself,
and I'll get a bit philosophical in the paragraphs that follow to tell you more about what's coming in our path to Tuist 3.0.
Let's dive right in.

## Evolving our plugins architecture

[Plugins](https://docs.old.tuist.io/plugins/using-plugins) were born to allow developers to share primitives of Tuist projects.
In particular, they can share [project description helpers](https://docs.old.tuist.io/guides/helpers) and [tasks](https://docs.old.tuist.io/commands/task).
Turning Tuist into an extensible **platform** was,
in hindsight,
a great idea.
Still, the approach we took failed to acknowledge that developers would want to depend on Swift packages from their plugins.
Extending our solution to support that would lead us to build a dependency manager.
As you can imagine,
that's not a good idea considering there are other package managers we can build upon.
Therefore we'll overhaul our plugins architecture to piggyback on the Swift Package Manager's work.
We are still fleshing out the details,
but without spoiling you too much,
plugins would be represented by Swift Packages that follow a convention defined by Tuist.
For example,
a task would become an executable in a Swift Package that follows the naming convention `tuist-{name}`.
Thanks to that,
developers can add transitive dependencies to their plugins,
and we can leverage the Swift Package Manager CLI to export the plugins in a distributable format.

Checkout a more in depth RFC: [here](https://github.com/tuist/tuist/discussions/3491)
```bash
tuist plugin init # Creates a Swift Packagefollowing the plugin convetions
tuist plugin build # Builds the lugin using the "swift" CLI
tuist plugin test # Tests the plugin using the "swift" CLI
tuist plugin archive # Creates an pre-compiled archive to install the plugin
```

Not only will third-party developers build for the platform,
but we'll also use it to extract some of the current commands that are more suitable to be opted into.
We can't wait to see what developers will build upon this new plugins architecture.

## Caching improvements

Improving build times remains one of the most concerning areas when scaling up Xcode projects.
Luckily,
our internal graph representation of projects positioned us to provide a solution without the complexity and maintenance of introducing a new build system like [Bazel](https://bazel.build/) entails.
The idea is simple,
the project is represented by a graph with targets as nodes,
some of which can be replaced with their binary counterpart at generation time.
The binaries are identified with a fingerprint that changes if the target or any of its dependencies changes.
Sounds trivial, but it has a set of challenges.

One of the challenges we are going through is getting a **deterministic and accurate fingerprint**.
It's challenging because Xcode projects support bringing implicitness to the build process.
For instance,
a script build phase could affect the built artifact of the target without the Tuist's fingerprinting logic being aware of it.
We can't detect implicitness,
but we can provide APIs to make it explicit.
Detecting sources of implicitness will require close collaboration with developers.

Another challenge is **generating a valid graph with binaries after the mutation.**
The scenarios that we used as a reference are very ideal and,
in most cases, distant from reality.
There are many different flavors of Xcode projects out there that the mutation logic needs to handle gracefully.
If our mutation logic doesn't support them,
developers might end up getting a project that doesn't compile,
or even worse,
they won't get a project at all.

When we adventured ourselves into the caching land,
we knew it was not going to be easy.
Our goal towards 3.0 is to continue to work with developers to make caching **accessible and bulletproof**.

## Third-party dependencies

Before we introduced [`Dependencies.swift`](https://docs.old.tuist.io/guides/third-party-dependencies),
adding third-party dependency dependencies to a Tuist project was non-standard,
and in some scenarios,
led to integration issues that surfaced at compilation time.
Moreover,
the integration of Swift Packages proposed by Apple proved to offer a poor developer experience.
For example,
the resolution of dependencies sometimes fails at launch time,
and it gets invalidated after deleting the derivd data directory.

`Dependencies.swift` offered a standard solution across Carthage and Package dependencies
and integrated dependencies into the projects' graphs to allow users to leverage Tuist features.
One of those features is `tuist cache`,
which allows developers to cache their Swift Packages as binaries.
In the current state,
users can declare and integrate Carthage and Package dependencies,
but there seem to be some package scenarios that are not well merged into the graphs.
The consequence is that users get a project that doesn't compile.

Because we believe in an integrated experience adding third-party dependencies,
we'll continue iterating through this functionality and make sure all the scenarios reported by users are handled gracefully.
If you are encountering issues,
please don't hesitate to [file an issue](https://github.com/tuist/tuist/issues/new?assignees=&labels=&template=Bug_report.md) with a reproducible example.

## Cloud

For months,
we've been pondering the idea of providing some workflows that require a server-side component:

- Remote binary caching.
- Share the local app running in your simulator with someone else.
- Get a dashboard with a project and build insights.
- Compare insights against a baseline (e.g., `main` branch) and post a report on a GitHub PR.
- Coordinate the process of releasing apps to the App Store.

Moreover, the idea of providing an open-source web app paired nicely with finding a model to financially sustain the project to avoid falling into the same trap as projects like [Babel](https://babeljs.io/). Many companies depend on it, and they struggle to financially support people to work on it full-time.

Therefore, towards Tuist 3.0, we'll build an open-source MIT-licensed web app, **Tuist Cloud**,
and provide hosting as a service.
Since it'll be open-source and the contract between the client and the server will be documented,
users will have the flexibility to bring their own implementation.
We won't fight against that,
but we are hopeful developers will acknowledge the importance of keeping the project alive and would opt for the path of paying for the service.

The organization will remain a non-profit organization on [Open Collective](https://opencollective.com/tuistapp).
The revenue will be oriented towards having people working on Tuist and Tuist Cloud part or full-time..

If you wanted to learn web development, Ruby, and Rails,
let us know,
and we'll be happy to pair with you on building new features for the project.

## Closing words

Tuist 2.0 wouldn't have been possible without the continuous dedication of the project's core maintainers, contributors, and users.
They are the ones pushing the project beyond their limits and bringing new ideas to the table.
When I started the project back in 2018, I wouldn't have imagined there'd be many of us on this boat solving such exciting challenges on top of a format like Xcode projects' that is closed to extensibility.

**Tuist is here to stay** because you've proven to us there's a need for this tool in the industry.
