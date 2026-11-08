# Getting Started

Condukt is a framework for building AI agents in Elixir. Agents are OTP
processes that can reason with an LLM, call tools, and delegate work.

This guide walks through installing Condukt, defining your first agent, and
running a prompt end to end.

## Install

Add `:condukt` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:condukt, "~> 1.5"}
  ]
end
```

Then fetch dependencies:

```sh
mix deps.get
```

## Configure an API key

Condukt uses [ReqLLM](https://github.com/agentjido/req_llm), which auto
discovers provider keys from the environment:

```sh
export ANTHROPIC_API_KEY="sk-ant-..."
```

You can also pass `:api_key` per agent or set it in `config :condukt`. See
the [Providers](providers.md) guide for the full list of supported backends.

## Define an agent

```elixir
defmodule MyApp.CodingAgent do
  use Condukt

  @impl true
  def tools do
    Condukt.Tools.coding_tools()
  end
end
```

`use Condukt` wires the module to a `GenServer` backed by `Condukt.Session`
and provides defaults for `system_prompt/0`, `model/0`, `thinking_level/0`,
`init/1`, and `handle_event/2`. Override what you need.

## Run the agent

For one prompt, pass the agent module directly to `Condukt.run/3`:

```elixir
{:ok, response} =
  Condukt.run(MyApp.CodingAgent, "Create a GenServer that manages a counter.",
    api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
    system_prompt: "You are an expert software engineer."
  )
```

Condukt starts a transient session, runs the agent loop synchronously, returns
the final assistant message, and stops the session. The `GenServer` remains an
implementation detail for this one-shot form.

Common options to module-defined one-shot runs:

* `:api_key` overrides `config :condukt, :api_key`
* `:model` accepts the ReqLLM `provider:model` format
* `:cwd` sets the working directory used by file and shell tools
* `:timeout` caps the synchronous call timeout in milliseconds
* `:max_turns` caps tool-use loops
* `:output` enables structured output with a JSON Schema

## Start a persistent agent

Use `start_link/1` when you want conversation history, streaming, persistence,
compaction, or supervision across multiple prompts:

```elixir
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
    system_prompt: "You are an expert software engineer."
  )
```

Common options to `start_link/1`:

* `:api_key` overrides `config :condukt, :api_key`
* `:model` accepts the ReqLLM `provider:model` format
* `:cwd` sets the working directory used by file and shell tools
* `:session_store` enables conversation persistence (see [Sessions and Persistence](sessions-and-persistence.md))
* `:compactor` keeps context bounded over long runs (see [Compaction](compaction.md))
* `:redactor` strips secrets from outbound messages (see [Redaction](redaction.md))

## Run against a persistent agent

```elixir
{:ok, response} = Condukt.run(agent, "Create a GenServer that manages a counter.")
```

`Condukt.run/3` runs the agent loop until the model stops calling tools and
returns the final assistant message.

## Stream events

```elixir
agent
|> Condukt.stream("Add docs to the counter module.")
|> Stream.each(fn
  {:text, chunk} -> IO.write(chunk)
  {:tool_call, name, _id, _args} -> IO.puts("\nUsing tool: #{name}")
  :done -> IO.puts("\nDone")
  _ -> :ok
end)
|> Stream.run()
```

The full event vocabulary is described in [Streaming and Events](streaming-and-events.md).

## Add it to a supervision tree

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {MyApp.CodingAgent,
        api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
        system_prompt: "You are a helpful coding assistant."}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

From here, browse the rest of the guides for deeper coverage of each feature.
