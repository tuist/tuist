---
title: "Elixir Patterns We'd Love to See in Swift"
category: "learn"
tags: ["elixir", "swift", "server", "developer-experience"] 
excerpt: "Exploring the patterns and developer experiences in Elixir that captured our hearts while building Tuist's server. From hot-reloading to server-driven UI, discover the features we'd love to see inspire Swift's evolution as it grows beyond Apple platforms."
author: pepicrft
og_image_path: /marketing/images/blog/2025/07/15/elixir.jpg
---

**This blog post is written for developers who want to understand why we chose Elixir for our server, how Swift and Elixir compare, and which Elixir patterns we'd love to see adopted in Swift.**

[Steve Jobs](https://en.wikipedia.org/wiki/Steve_Jobs) said that [computers are bicycles for the mind](https://www.themarginalian.org/2011/12/21/steve-jobs-bicycle-for-the-mind-1990/). I think programming languages are too. They are tools for expression, to be creative.

At Tuist, we've been huge fans of [Swift](https://www.swift.org/), the most common programming language of the ecosystem we build for. Yet, we always remained open to finding the right programming language or technology that would allow us to express what we wanted to express.

Through Swift, we could express ourselves in terminals. We built Tuist's main CLI and filled some gaps with other open source tools like [Noora](https://github.com/tuist/noora). Through [VitePress](https://vitepress.dev/), a JavaScript-based solution, we could build a documentation website for our community with built-in search, llm.txt generation, in multiple languages. And then the time to build a server came, and with it the decision to choose the best expression tool.

We needed a solution that allowed us to build and maintain a powerful and simple solution with as few resources as possible. Primarily because we were limited in budget, but also because simpler software is easier to reason about and evolve.

At the time, we had come across [Elixir](https://elixir-lang.org/) and immediately felt it was the right tool to express ourselves in a new domain: the web. We discovered patterns and approaches that we absolutely fell in love with—patterns that we believe could inspire and enhance Swift's evolution, especially as it continues to grow beyond Apple platforms.

In this post, we'll walk you through what made us fall in love with Elixir, the incredible developer experience it provides, and the patterns we'd love to see influence Swift's future.

## Erlang and Processes

We can't understand Elixir without talking about Erlang. [Erlang](https://www.erlang.org/) is a programming language and runtime created at Ericsson in the 1980s to power their telecommunication networks. It was designed to build highly-concurrent, scalable, and fault-tolerant software. Sounds familiar? These needs are common across the modern web applications that we build today. Erlang comprises a runtime (BEAM), a programming language (Erlang), and a set of primitives to architect your apps (OTP - Open Telecom Platform). At the core of Erlang sits the idea of processes upon which almost everything builds. Joe Armstrong captured what led him to processes in his [thesis](https://erlang.org/download/armstrong_thesis_2003.pdf). He refers to it as _Concurrency Oriented Programming_:

*The word concurrency refers to sets of events which happen simultaneously. The real world is concurrent, and consists of a large number of events many of which happen simultaneously. At an atomic level our bodies are made up of atoms, and molecules, in simultaneous motion. At a macroscopic level the universe is populated with galaxies of stars in simultaneous motion.*

*When we perform a simple action, like driving a car along a freeway, we are aware of the fact that there may be several hundreds of cars within our immediate environment, yet we are able to perform the complex task of driving a car, and avoiding all these potential hazards without even thinking about it. In the real world sequential activities are a rarity. As we walk down the street we would be very surprised to find only one thing happening, we expect to encounter many simultaneous events.*

*If we did not have the ability to analyze and predict the outcome of many simultaneous events we would live in great danger, and tasks like driving a car would be impossible. The fact that we can do things which require processing massive amounts of parallel information suggests that we are equipped with perceptual mechanisms which allow us to intuitively understand concurrency without consciously thinking about it.*

*When it comes to computer programming things suddenly become inverted. Programming a sequential chain of activities is viewed the norm, and in some sense is thought of as being easy, whereas programming collections of concurrent activities is avoided as much as possible, and is generally perceived as being difficult.*

*I believe that this is due to the poor support which is provided for concurrency in virtually all conventional programming languages. The vast majority of programming languages are essentially sequential; any concurrency in the language is provided by the underlying operating system, and not by the programming language.*

So the world (and agentic software) is made of concurrent processes that communicate with each other by passing messages. When I read that, I was fascinated. I had never stopped to see the world that way, but I was hooked by the idea.

Processes in Erlang are lightweight and CPU/memory-isolated runtime elements that can communicate by passing messages and form more complex structures holding state, build supervised trees, define error boundaries, and work across environments (among others). This might sound too abstract at this point, but throughout the blog post I'll make it more concrete with examples of how this materializes.

## Parallelism

Modern CPU architecture comprises multiple cores, which presents programming languages with the challenge of using them in the most efficient way possible. Every programming language solves this problem differently, each with its own approach and philosophy.

Swift has introduced a novel approach with its structured concurrency model. Apple continues to iterate on this model to make concurrent programming safer and more intuitive. The introduction of async/await, actors, and task groups represents a thoughtful evolution in how we think about concurrent code. What's particularly exciting is seeing Swift adopt the actor model—a concept that has proven itself in distributed systems for decades.

Erlang's process-based mental model resonated particularly well with us. The idea that you can write concurrent code without constantly thinking about concurrency felt magical. Processes are isolated by default, communicate through message passing, and the runtime handles the scheduling across available cores. This approach means you can focus on solving your problem rather than managing concurrency primitives.

But what truly captured our imagination was how Erlang takes actors beyond just a concurrency model and makes them an architectural foundation. Tools like [GenServer](https://hexdocs.pm/elixir/GenServer.html) (Generic Server) provide a standard way to implement stateful processes with clean APIs, while [Supervisors](https://hexdocs.pm/elixir/Supervisor.html) create hierarchical structures that define how your system starts, stops, and recovers from failures.

We'd love to see Apple explore expanding actors from a concurrency primitive to a fuller architectural pattern. Imagine Swift actors that could:
- Define standard patterns for stateful services (like GenServer)
- Build supervision trees that handle failure and recovery
- Provide built-in patterns for common architectural needs

Swift's actor model already provides excellent isolation and state management. Taking inspiration from Erlang's OTP (Open Telecom Platform), Swift could evolve to offer similar architectural patterns that make building resilient, distributed systems as natural as building a single-threaded application. The foundation is there—Swift's actors are already a powerful abstraction. The opportunity lies in building the architectural patterns on top.

## Welcome Elixir

How does Elixir connect to all of this, you might wonder? [José Valim](https://twitter.com/josevalim), creator of Elixir, came from the Ruby & Ruby on Rails community motivated by making Ruby use all the CPU cores available. He came across Erlang and fell in love with its principles and foundation, but he realized that the language, the toolchain, and the ecosystem could benefit from modernization. He decided to build [Elixir](https://elixir-lang.org/), a programming language that compiles to Erlang bytecode to run in the Erlang runtime. So in other words, Erlang and Elixir are two programming languages that compile to run on the Erlang VM. As you can imagine, the language draws a lot of inspiration from Ruby, and in many ways, it feels like writing Ruby but with a more functional touch to it. If you've used [SwiftPM](https://www.swift.org/documentation/package-manager/) or [Cargo (Rust)](https://doc.rust-lang.org/cargo/), the developer experience is similar. You have a build system, `mix`, which takes care of managing your dependencies, building the project, spawning the test runner, or formatting the code, among others.

So with Elixir, you get the power and the simplicity of a battle-tested runtime (Erlang's) with a modern toolchain, language, and ecosystem that makes building for Erlang a true joy.

## Tuist Meets Elixir

Having talked about Elixir, Erlang, and processes, it's time to talk about the patterns and experiences we discovered that we'd love to see inspire Swift's evolution. Note that some of the value that I'll touch on is a shared responsibility between Elixir as a programming language and Erlang as a runtime and framework, but I'll refer to it as just Elixir value. Let's dive into some day-to-day real impacts on how we are building Tuist.

### A Build System That Doesn't Get in Your Way

The Elixir build system is absolutely amazing and represents a pinnacle of developer experience. Like any other build system, it'll take some time initially to build your project (i.e., clean build), but once it's built, it magically hot-reloads your changes, making the feedback loops incredibly short. Is there a bug in one of the web app routes? I change one line of code, and the change is picked up automatically. This developer experience has spoiled us—the ability to see changes instantly keeps the creative momentum going.

Additionally, because Elixir is functional, the reconciliation of the changes at runtime leads to expected results. The build system feels invisible in the best possible way—it's there when you need it but never gets in your way.

Swift has taken the first steps to unify the build system across SwiftPM and Xcode, and we're optimistic that it'll reach a similar level of developer experience that spans across layers. The potential for Swift to adopt hot-reloading capabilities, especially for server development, would be transformative. Imagine the productivity gains if Swift developers could experience the same instant feedback loops we enjoy with Elixir.

### Read-Eval-Print Loop

Being able to open a console with access to your codebase symbols and the history of executed instructions can make a huge productivity difference in development. For example, locally we can just do the following to debug a particular organization:

```elixir
Tuist.Accounts.get_organization_by_handle("tuist") 
  |> Tuist.Accounts.get_organization_members()
```

One could say that you can come up with a similar query yourself with the help of an LLM, but if we are talking about a function that encapsulates more business logic, then things get trickier. You are forced to either write an entry point to that piece of logic when all you want is to iterate on a new idea that you came up with. The console is also able to hot-reload changes automatically for you, so you can keep typing, always assuming you'll be using the latest version of your code.

This tool can also be used in production, but we use it sparingly only in very exceptional cases and with read-only operations.

### Server-Driven Interactive UI

I talked a lot about processes earlier, and if there's a good example of how cool they are, we need to talk about [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html). [Phoenix](https://www.phoenixframework.org/) is the Ruby on Rails of Elixir. It's the web framework that most Elixir projects use to build web apps. When it comes to doing UI, Phoenix proposes a quite unique model, LiveView, which allows us to build dynamic UIs without having to worry about managing API-provided client-side state or dealing with the cost of a JavaScript runtime setup (and its ecosystem).

Phoenix LiveView's model is absolutely brilliant. When you open a page, a process is created and bound to your connection, with a state that's then mapped to HTML that's presented in your browser. Since the state is on the server, you don't need to deal with syncing state between client and server. Any action that requires UI change is sent to the server, the new state is calculated, mapped to a new representation, and Phoenix LiveView takes care of sending the diff to the client. In our particular context, having a single source of truth for UI state was crucial, and LiveView delivered this beautifully.

The Swift community is pushing Swift to new environments like the browser using WebAssembly, and we can't wait to see the answer the community comes up with to build dynamic UIs. Perhaps we'll see Swift-native solutions that bring similar server-driven UI capabilities, combining Swift's type safety with real-time reactivity.

For example, our [preview](https://github.com/tuist/tuist/blob/main/server/lib/tuist_web/live/preview_live.ex) page uses LiveView. You'll notice that we fetch the state, assign it to the socket connection, and then [use it in the template](https://github.com/tuist/tuist/blob/main/server/lib/tuist_web/live/preview_live.html.heex). Because templates are compiled, the runtime has all the information it needs to optimize the diff that's sent to the client. The mental model is refreshingly simple yet powerful.

### Real-Time UI

People are expecting more and more UIs to update in real-time as new data comes in. In the context of Tuist, we'll have a lot of things happening, from a new build that's pushing logs to our server, to a preview that's being built to be shared with other users.

Phoenix provides [PubSub](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html), whose default adapter leverages Erlang capabilities to discover and distribute messages across nodes. Let's say you are seeing the builds page, and a new build comes in. Erlang could receive a message saying that a new build has been created, and we can have LiveViews subscribed to those events updating their internal state accordingly and sending the diffs to the client.

Swift's distributed actors model draws a lot of inspiration from similar actor-based systems, and we believe it could be a great foundation to build real-time applications in Swift too. The conceptual similarities between Erlang's processes and Swift's actors suggest that Swift could evolve to provide similar built-in real-time capabilities.

This capability of Erlang is so powerful that companies like [Discord](https://discord.com/blog/how-discord-scaled-elixir-to-5-000-000-concurrent-users) and [WhatsApp](https://www.erlang-solutions.com/blog/20-years-of-open-source-erlang-openerlang-interview-with-anton-lavrik-from-whatsapp/) have built their infrastructure on it. At Tuist, we're investing more in making our features real-time, and this foundation also enables collaborative features where multiple people can interact with the same state—think of experiences like Figma.

### Ease of Scaling

We are a small team, so it's important that as the need for scaling comes, we don't need to invest many resources into it. Both Swift and Elixir excel in this area—they're languages designed to scale elegantly.

With Elixir, we can build powerful solutions like real-time capabilities and collaborative experiences without complex setup. Most of our surfaces are a database schema, a small piece of business logic in between, and a LiveView. The simplicity is refreshing.

Testing is another area where scalability matters. Every test in Elixir is a different process, scheduled to run in parallel. If you want to run your test suite faster, you can throw more CPU cores at the problem. But what's particularly elegant is how Elixir's functional nature encourages writing tests that are naturally isolated. Since most of the time you're testing pure functions that take inputs and return outputs, there's little opportunity for shared state to cause flakiness. When you do need stateful processes in tests, you can spawn them in isolation.

This got us thinking about how powerful it would be if foundation APIs were designed with this principle in mind—actively discouraging global state that might leak across concurrent tests. Swift already has tools like [TaskLocal](https://developer.apple.com/documentation/swift/tasklocal) that could play a role in scoping state to tests, but we don't see this being actively promoted as a pattern the community should adopt for test isolation. Imagine if Swift's testing frameworks and foundation libraries were architected to make the isolated approach the path of least resistance, with clear patterns and best practices for state isolation. The functional model guides this good behavior in Elixir, but similar outcomes could be achieved through thoughtful API design and community conventions that make shared mutable state difficult to accidentally introduce.

In Elixir, you can even define mocks scoped to each test's process tree, ensuring complete isolation. This pattern—where the foundation actively guides you toward scalable, flake-free testing—is something we'd love to see more broadly adopted.

In production, Elixir's concurrent nature allows scaling vertically by simply adding more memory and CPU. Erlang's scheduler ensures those resources are used optimally. We run our app on [Fly.io](https://fly.io/), which makes it trivial to add machines in different regions to reduce latency for global users.

The beauty of both Swift and Elixir is that they make scaling feel natural rather than an afterthought. Swift's performance characteristics and Elixir's concurrency model are different approaches to the same goal: building systems that grow with your needs.

### The Ecosystem

When comparing ecosystems, it's important to acknowledge that it's not quite a fair comparison—Erlang has been battle-tested in production since the 1980s, giving it decades to mature and develop specialized solutions. The Elixir ecosystem benefits from this foundation, with focused, well-established libraries for most server-side needs.

Swift's server ecosystem, by contrast, is young and vibrant. What excites us is the momentum we're seeing—more companies are investing in Swift on the server, bringing fresh perspectives and innovative solutions. The community's energy around pushing Swift beyond Apple platforms is palpable, and we're optimistic that this ecosystem will become increasingly diverse and robust.

For our current needs, we found everything required in the Elixir ecosystem. When we added [ClickHouse](https://clickhouse.com/) to our infrastructure, [Plausible](https://plausible.io/) had already built an adapter. When we needed OpenID Connect, [Boruta](https://github.com/malach-it/boruta_auth) was ready to go. This maturity meant we could focus on building rather than filling gaps.

But we're watching Swift's server ecosystem with great interest. As more teams adopt Swift on the server and share their solutions, we expect to see similar depth emerge. The quality of what's already available—from web frameworks to database drivers—shows that Swift's server future is bright. In a few years, we believe Swift developers will enjoy the same rich ecosystem that makes Elixir development so productive today.

The excellent documentation quality across the Elixir ecosystem has been crucial for our productivity, especially in an age of AI-assisted development. This is something the Swift community has always excelled at, and we're confident this tradition will continue as the server ecosystem grows.

## Trade-offs and What We Miss

Choosing Elixir meant accepting certain trade-offs, and there are definitely things we miss from the Swift world:

**Shared code between CLI and server**: One of the most significant trade-offs is not being able to share models and business logic between our Swift CLI and Elixir server. In an all-Swift setup, we could have a single source of truth for our domain models, reducing duplication and potential inconsistencies.

**Memory control for resource-intensive tasks**: While Elixir excels at concurrent I/O-bound operations, Swift's more direct memory control would be advantageous for potential future resource-intensive tasks. If we ever need to do heavy computational work, Swift's performance characteristics would be ideal.

**Compile-time guarantees**: Swift's compiler catches entire categories of errors through static type checking. While Elixir's dynamic nature enables certain patterns like hot-reloading, we do miss the confidence that comes from Swift's type system, especially during large refactorings.

These are genuine trade-offs that we considered carefully. For our current needs—building a real-time, collaborative platform—Elixir's benefits outweighed these costs, but we remain excited about Swift's evolution in the server space.

## Closing Words

In hindsight, Elixir was the right bicycle for the job of building the Tuist platform today. Our 4-person team feels incredibly productive, and the patterns we've discovered—from hot-reloading to server-driven UI to built-in real-time capabilities—have shaped how we think about building software.

But we're equally excited about Swift's future. As Swift continues to evolve beyond Apple platforms, we hope to see it adopt some of the patterns that make Elixir such a joy to work with. Imagine Swift with hot-reloading, built-in real-time primitives, or Phoenix LiveView-style server-driven UI capabilities. The combination of Swift's type safety and performance with Elixir's developer experience would be incredible.

We're keeping a close eye on Swift's evolution, and who knows? As the ecosystem matures and new capabilities emerge, we might revisit this decision in the future. For now, we're grateful for what both languages bring to the table and excited to see how they'll continue to inspire each other.

Thank you to both José Valim and the Elixir community, and to Chris Lattner and the Swift community, for gifting us with such wonderful tools for expression.

**Grammar corrections provided by Claude Opus 4.**
