# Elixir library

Condukt is an Elixir library for building reliable AI agents.

It treats agents as OTP-native processes with first-class support for tools,
sandboxes, structured output, sub-agents, MCP servers, streaming, secrets, and
telemetry.

## Why Condukt

Condukt grew out of practical work building agent systems in Elixir. We needed
a framework that:

* Integrates naturally with OTP supervision trees
* Supports streaming for responsive user experiences
* Works with multiple LLM providers without vendor lock-in
* Provides extensible tooling for domain-specific capabilities

Rather than wrapping JavaScript agent frameworks, Condukt is built from scratch
using idiomatic Elixir patterns.

## Capabilities

* OTP-native agents that integrate with supervision trees
* Real-time event streaming for responsive UIs
* Project instruction discovery from `AGENTS.md`, `CLAUDE.md`, and local skills
* Scoped command tools for trusted executables such as `git`, `gh`, or `mix`
* File, shell, editing, and custom domain tools
* Compile-time typed operations with JSON Schema input and output validation
* One-shot runs with inline tools and optional structured output
* Sub-agents for delegated child sessions with optional structured contracts
* Multi-provider LLM support through ReqLLM
* Pluggable redaction, session secrets, compaction, persistence, and telemetry

## Where to start

| You want to | Read |
| --- | --- |
| Add the library to a project | [Installation](installation.md) |
| Define and run your first agent | [Getting Started](getting-started.md) |
| Give an agent capabilities | [Tools](tools.md) and [Sandbox](sandbox.md) |
| Delegate work to child agents | [Sub-agents](subagents.md) |
| Run an agent as an endpoint | [HTTP Routes](http-routes.md) |
| Keep a conversation alive over time | [Sessions and Persistence](sessions-and-persistence.md) |


