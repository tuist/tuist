---
{
  "title": "Technologies",
  "titleTemplate": ":title | Engineering | Tuist Handbook",
  "description": "This document includes a list of technologies that are approved for use in Tuist projects along with the rationale behind each decision."
}
---
# Technologies

When deciding a technology to use in a new project, we try to be pragmatic ensuring we prevent technology fragmentation.
This document includes a list of technologies that are approved for use in Tuist projects along with the rationale behind each decision. If you believe a technology should be added or removed from this list, please [open a pull request](https://github.com/tuist/handbook/compare).

## How we choose technologies

One of our core principles in technology selection is adhering to [standards](/engineering/standards) that strike a perfect balance between simplicity and power. Many **widely adopted technologies hide underlying complexities resulting from poor foundational design.** This hidden complexity eventually surfaces, making software maintenance and evolution more challenging.

A prime example of achieving simplicity through robust design is found in [Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language)) and [Elixir](https://en.wikipedia.org/wiki/Elixir_(programming_language)). These technologies provide primitives that effectively model the real world, eliminating the need for endless layers of abstractions that are common in other ecosystems.

We are also mindful of cutting-edge technologies. While they often bring innovation and spark valuable debates, their premature adoption can divert us from our primary mission: building a world-class productivity platform for app developers. By focusing on well-designed, standard-based technologies, we ensure our platform remains robust, maintainable, and aligned with our long-term goals.

## Programming languages

### Swift

Tuist started as a [Swift](https://www.swift.org/)-based CLI tool. We chose Swift because it was important that the technology we used to build our tool was the same as the technology we were building the tool for. That way, **developers would be more likely to contribute to the project.**

If you are building a command line interface or an application for any of the Apple platforms, it must be written in Swift, a language the organization is very familiar with.

> [!TIP] MULTI-PLATFORM CLI TOOLS
> If you come across a situation where you need to build a multi-platform CLI tool, we might accept the usage of other languages like [Rust](https://www.rust-lang.org/), whose standard library has been better designed and battle-tested to work across different platforms.

Note that despite we like Swift, and we try to push it as much as possible,
we acknowledge domains where Swift is not the best fit, and choose other technologies accordingly.

### Elixir

[Elixir](https://elixir-lang.org/) is our go-to language for **building backend services and apps.** We chose Elixir because it is a functional language that runs on the [Erlang VM](https://en.wikipedia.org/wiki/BEAM_(Erlang_virtual_machine)), which is known for its fault-tolerance and scalability. Elixir is also a language that is easy to learn and has a great community.

It's common for organizations and developers to see Elixir as a risk since its ecosystem is not as large and diverse as others (e.g. JavaScript). However, it has something unique that often goes unnoticed. Its approach to programming and the battle-tested runtime, Erlang, **make it extremely easy and cheap to scale, both development and also production-runnin applications.** While Erlang and Elixir can go a very long way with few resources (e.g. engineers, infrastructure complexity), other runtimes require earlier "throwing money at the problem" or "relying on costly external services that abstract the complexity away".

> [!NOTE] A NOTE ON LEARNING ELIXIR
> Since it's not as popular as other languages, it might be harder to find Elixir developers. However, our aim is to have a team that is capable of learning new technologies and languages. We believe that the benefits of using Elixir outweigh the costs of learning it.

## Standards

### OpenAPI

[OpenAPI](https://swagger.io/specification/) is a standard for defining APIs. We use it to define the APIs of our services. It allows us to generate documentation, client SDKs, and server stubs, which makes it easier to maintain and evolve our services.

> [!NOTE] GRAPHQL
> Although GraphQL has been gaining popularity, we have decided to stick with REST APIs for now. We believe that REST APIs are more straightforward and easier to understand for developers who are not familiar with GraphQL. Moreover, we don't have the need for giving clients the flexibility to request only the data they need, which is one of the main benefits of GraphQL. So we'd end up having to deal with [their challenges](https://www.magiroux.com/eight-years-of-graphql) early, distracting us from our primary mission.

## Technologies

### Scalar

We generate documentation for [OpenAPI](#openapi) using [Scalar](https://github.com/scalar/scalar). It's open-source, and it allows us to generate beautiful documentation websites from OpenAPI specifications. If you are serving it from an [Elixir](#elixir) project, you can use our [scalar_plug](https://github.com/tuist/scalar_plug) library to serve the documentation from your Phoenix application.

## Project types

### Statically-generated documentation websites

Our go-to framework for building statically-generated documentation websites is [VitePress](https://vitepress.dev/).
It's maintained by the minds behind [Vue.js](https://vuejs.org/) and [Vite](https://vitejs.dev/), and can generate beautiful documentation website out of the box with all the features we need, including internationalization, search, and more.

### Statically-generated websites

When building statically-generated websites, we use [11ty](https://www.11ty.dev/). Unlike other frameworks whose development is is heavily reliant on external investment or that build on layers of abstractions, making them not future-proof, 11ty is a simple, flexible, and powerful static site generator that embraces the platform rather than abstracting it.
