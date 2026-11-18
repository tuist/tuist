<p align="center">
  <img src="docs/assets/readme-header.png" alt="Condukt header" width="300" />
</p>

<p align="center">
  <a href="https://hex.pm/packages/condukt"><img src="https://img.shields.io/hexpm/v/condukt.svg" alt="Hex.pm" /></a>
  <a href="https://hexdocs.pm/condukt/"><img src="https://img.shields.io/badge/docs-hexdocs-blue.svg" alt="HexDocs" /></a>
  <a href="https://github.com/tuist/tuist/actions/workflows/condukt.yml"><img src="https://github.com/tuist/tuist/actions/workflows/condukt.yml/badge.svg" alt="CI" /></a>
  <a href="https://hex.pm/packages/condukt"><img src="https://img.shields.io/hexpm/dt/condukt.svg" alt="Hex.pm downloads" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/hexpm/l/condukt.svg" alt="License" /></a>
</p>

Condukt is an Elixir framework for building agents that do real work on your
infrastructure.

Its source lives in [`condukt/` in the Tuist monorepo](https://github.com/tuist/tuist/tree/main/condukt).
It remains independently published as [`condukt` on Hex](https://hex.pm/packages/condukt).

The agent loop is the easy part of that and the least of what this gives you.
Every session is a supervised process whose tools run in a sandbox, on a
network you decide, with secrets it never gets to print:

- **Sandboxes** so tools run somewhere other than your filesystem: in memory,
  in a microVM, or in a dedicated Kubernetes pod per session, behind one
  interface.
- **Network policy** per session, audited and enforced outside the agent, with
  allow and deny rules by host and a decider agent for the cases a rule cannot
  settle.
- **Secrets** resolved separately from the conversation and redacted from
  transcripts.
- **OTP** doing what it is good at: supervision, streaming, backpressure,
  cancellation, and sub-agents as children with typed inputs and outputs.

Agents are the imperative half of the picture. They compose with a declarative
workflow engine rather than replacing one: let the workflow own the steps you
can name, and give an agent the ones you cannot.

## Library

Use Condukt when agents should live inside your OTP system. Add it to
`mix.exs`:

```elixir
def deps do
  [
    {:condukt, "~> 1.5"}
  ]
end
```

```elixir
defmodule MyApp.ProjectAgent do
  use Condukt

  @impl true
  def model, do: "anthropic:claude-sonnet-4-20250514"

  @impl true
  def system_prompt do
    "You help maintain this repository. Prefer concrete findings and patches."
  end

  @impl true
  def tools, do: Condukt.Tools.coding_tools()

  operation :release_notes,
    input: %{
      type: "object",
      properties: %{version: %{type: "string"}},
      required: ["version"]
    },
    output: %{
      type: "object",
      properties: %{
        title: %{type: "string"},
        highlights: %{type: "array", items: %{type: "string"}}
      },
      required: ["title", "highlights"]
    },
    instructions: "Draft release notes from the git history and project files."
end
```

Read the [library documentation on HexDocs](https://hexdocs.pm/condukt/overview.html).

## Repository layout

```
condukt/
├── lib/                  # Elixir library
├── native/               # Rust NIFs (bashkit, microsandbox, egress)
└── docs/guides/          # Library guides published with ExDoc
```

CI and releases live in the monorepo's `.github/workflows/condukt*.yml`.

## Documentation

Library guides live in [`docs/guides/`](docs/guides/) and are published to
[HexDocs](https://hexdocs.pm/condukt/overview.html) alongside the API reference.

## License

The library and native code are MIT. See [LICENSE](LICENSE).
The library guides retain their [MIT license](docs/guides/LICENSE).
