---
title: Principles
titleTemplate: :title - Contribute to Tuist
description: This document describes the principles that guide the development of Tuist.
---

# Principles

This page describes principles that are pillars to the design and development of Tuist. They evolve with the project and are meant to ensure a sustainable growth that is well-aligned with the project foundation.

## Default to conventions

One of the reasons why Tuist exists is because Xcode is weak in conventions and that leads to complex projects that are hard to scale up and maintain. For that reason, Tuist takes a different approach by defaulting to simple and thoroughly designed conventions. **Developers can opt-out from the conventions, but that’s a conscious decision that doesn’t feel natural.**

For example, there’s a convention for defining dependencies between targets by using the provided public interface. By doing that, Tuist ensures that the projects are generated with the right configurations for the linking to work. Developers have the option to define the dependencies through build settings, but they’d be doing it implicitly and therefore breaking Tuist features such as `tuist graph` or `tuist cache` that rely on some conventions being followed.

The reason why we default to conventions is that the more decision we can make on behalf of the developers, the more focus they’ll have crafting features for their apps. When we are left with no conventions like it’s the case in many projects, we have to make decisions that will end up not being consistent with other decisions and as a consequence, there’ll be an accidental complexity that will be hard to manage.

## Manifests are the source of truth

Having many layers of configurations and contracts between them results in a project setup that is hard to reason about and maintain. Think for a second on an average project. The definition of the project lives in the `.xcodeproj` directories, the CLI in scripts (e.g `Fastfiles`), and the CI logic in pipelines. Those are three layers with contracts between them that we need to maintain. _How often have you been in a situation where you changed something in your projects, and then a week later you realized that the release scripts broke?_

We can simplify this by having a single source of truth, the manifest files. Those files provide Tuist with the information that it needs to generate Xcode projects that developers can use to edit their files. Moreover, it allows having standard commands for building projects from a local or CI environment.

**Tuist should own the complexity and expose a simple, safe, and enjoyable interface to describe their projects as explicitly as possible.**

## Make the implicit explicit

Xcode supports implicit configurations. A good example of that is inferring the implicitly defined dependencies. While implicitness is fine for small projects, where configurations are simple, as projects get larger it might cause slowness or odd behaviors.

Tuist should provide explicit APIs for implicit Xcode behaviors. It should also support defining Xcode implicitness but implemented in such a way that encourages developers to opt for the explicit approach. Supporting Xcode implicitness and intricacies facilitates the adoption of Tuist, after which teams can take some time to get rid of the implicitness.

The definition of dependencies is a good example of that. While developers can define dependencies through build settings and phases, Tuist provides a beautiful API that encourages its adoption.

**Designing the API to be explicit allows Tuist to run some checks and optimizations on the projects that otherwise wouldn’t be possible.** Moreover, it enables features like `tuist graph`, which exports a representation of the dependency graph, or `tuist cache`, which caches all the targets as binaries.

> [!TIP]
> We should treat each request to port features from Xcode as an opportunity to simplify concepts with simple and explicit APIs.

## Keep it simple

One of the main challenges when scaling Xcode projects comes from the fact that **Xcode exposes a lot of complexity to the users.** Due to that, teams have a high bus factor and only a few people in the team understand the project and the errors that the build system throws. That’s a bad situation to be in because the team relies on a few people.

Xcode is a great tool, but so many years of improvements, new platforms, and programming languages, are reflected on their surface, which struggled to remain simple.

Tuist should take the opportunity to keep things simple because working on simple things is fun and motivates us. No one wants to spend time trying to debug an error that happens at the very end of the compilation process, or understanding why they are not able to run the app on their devices. Xcode delegates the tasks to its underlying build system and in some cases it does a very poor job translating errors into actionable items. Have you ever got a _“framework X not found”_ error and you didn’t know what to do? Imagine if we got a list of potential root causes for the bug.

## Start from the developer’s experience

Part of the reason why there is a lack of innovation around Xcode, or put differently, not as much as in other programming environments, is because **we often start analyzing problems from existing solutions.** As a consequence, most of the solutions that we find nowadays revolve around the same ideas and workflows. While it’s good to include existing solutions in the equations, we should not let them constrain our creativity.

We like to think as [Tom Preston](https://tom.preston-werner.com/) puts it in [this podcast](https://tom.preston-werner.com/): _“Most things can be achieved, whatever you have in your head you can probably pull off with code as long as is possible within the constrains of the universe”._ If **we imagine how we’d like the developer experience to be**, it’s just a matter of time to pull it off — by starting to analyze the problems from the developer experience gives us a unique point of view that will lead us to solutions that users will love to use.

We might feel tempted to follow what everyone is doing, even if that means sticking with the inconveniences that everyone continues to complain about. Let’s not do that. How do I imagine archiving my app? How would I love code signing to be? What processes can I help streamline with Tuist? For example, adding support for [Fastlane](https://fastlane.tools/) is a solution to a problem that we need to understand first. We can get to the root of the problem by asking “why” questions. Once we narrow down where the motivation comes from, we can think of how Tuist can help them best. Maybe the solution is integrating with Fastlane, but it’s important we don’t disregard other equally valid solutions that we can put on the table before making trade-offs.

## Errors can and will happen

We, developers, have an inherent temptation to disregard that errors can happen. As a result, we design and test software only considering the ideal scenario.

Swift, its type system, and a well-architected code might help prevent some errors, but not all of them because some are out of our control. We can’t assume the user will always have an internet connection, or that the system commands will return successfully. The environments in which Tuist runs are not sandboxes that we control, and hence we need to make an effort to understand how they might change and impact Tuist.

Poorly handled errors result in bad user experience, and users might lose trust in the project. We want users to enjoy every single piece of Tuist, even the way we present errors to them.

We should put ourselves in the shoes of users and imagine what we’d expect the error to tell us. If the programming language is the communication channel through which errors propagate, and the users are the destination of the errors, they should be written in the same language that the target (users) speak. They should include enough information to know what happened and hide the information that is not relevant. Also, they should be actionable by telling users what steps they can take to recover from them.

And last but not least, our test cases should contemplate failing scenarios. Not only they ensure that we are handling errors as we are supposed to, but prevent future developers from breaking that logic.
