# Agents

An agent is a module that does `use Condukt`. Each agent runs as its own
`GenServer` backed by `Condukt.Session`, which manages the conversation
history, the tool loop, and any optional features (sessions, compaction,
redaction).

## The behaviour

`use Condukt` exposes the following optional callbacks, all with defaults:

| Callback | Default | Purpose |
| -------- | ------- | ------- |
| `runtime/0` | `Condukt.AgentRuntimes.Native` | Component that owns the agent loop. |
| `system_prompt/0` | `nil` | Static system prompt for the agent. |
| `tools/0` | `[]` | List of tool modules, `{module, opts}` tuples, or inline tools. |
| `model/0` | `"anthropic:claude-sonnet-4-20250514"` | ReqLLM `provider:model` identifier. |
| `thinking_level/0` | `:medium` | One of `:off`, `:minimal`, `:low`, `:medium`, `:high`. |
| `init/1` | identity | Called with the keyword opts at startup. |
| `handle_event/2` | no op | Receives events as they happen during a run. |

These callbacks describe the native Condukt agent loop: `Condukt.Session`
builds a ReqLLM request from the agent's messages, model, system prompt, and
tools, then repeats while the model asks for tools.

You only override what you need:

```elixir
defmodule MyApp.ResearchAgent do
  use Condukt

  @impl true
  def system_prompt do
    "You are a careful research assistant. Always cite sources."
  end

  @impl true
  def tools do
    [Condukt.Tools.Read, Condukt.Tools.Bash]
  end

  @impl true
  def model, do: "anthropic:claude-sonnet-4-20250514"
end
```

## Agent runtimes

Some agent implementations are not just model backends. Coding agents such as
Codex SDK or Claude Code SDK own their own execution loop: they may plan,
inspect files, edit code, invoke their own tools, stream intermediate events,
and decide when the task is complete. Those systems should be integrated as
agent runtimes, not as ReqLLM model providers.

An agent runtime is the component that owns the loop for a run. The default
runtime is the native Condukt session runtime described above. A
runtime-backed agent can be declared like this:

```elixir
defmodule MyApp.Implementer do
  use Condukt.Agent, runtime: Condukt.AgentRuntimes.Codex

  def system_prompt do
    "Implement the requested change and leave the working tree ready for review."
  end

  def sandbox do
    {Condukt.Sandbox.Local, cwd: "/path/to/repo"}
  end

  def secrets do
    [github_token: {:env, "GITHUB_TOKEN"}]
  end
end
```

Passing a runtime changes the meaning of the agent module. The module is still
addressable by Condukt, so it can be used in one-shot runs and
sub-agent registrations. Internally, however, Condukt delegates the loop to the
runtime adapter instead of driving every LLM turn itself.

### Callback implications

Runtime-backed agents have a smaller common callback surface than native
agents. These callbacks remain generally meaningful:

- `runtime/0`: selects the execution engine.
- `system_prompt/0`: passes durable guidance to the runtime. Project
  instructions are composed into this prompt when enabled.
- `sandbox/0`: defines where filesystem and subprocess side effects may happen.
- `secrets/0`: declares credentials available to the runtime adapter.
- `init/1`: prepares per-session state.
- `handle_event/2`: observes normalized lifecycle and streaming events.
- `subagents/0`: composes the runtime-backed agent with other Condukt agents.

These native callbacks are runtime-specific and should not be treated as
portable configuration:

- `model/0`: only applies when Condukt owns the ReqLLM call. A coding-agent SDK
  may choose its model internally or expose a different option.
- `thinking_level/0`: only applies if the runtime adapter maps it deliberately.
- `tools/0`: describes Condukt-native LLM tools. External coding agents often
  have their own tool protocol, so the adapter must decide whether and how to
  expose Condukt tools.
- `mcp_servers/0`: applies only when the runtime adapter can pass MCP servers
  through to the external SDK.

The rule is: callbacks are not silently universal. If a runtime does not
support a callback, Condukt should either reject that configuration or document
the runtime-specific mapping. This keeps an agent definition from looking
portable while relying on behavior that only exists in one SDK.

### Runtime boundary

Runtime adapters should preserve Condukt's orchestration boundary:

- Condukt owns session identity, sandbox selection, secret resolution,
  sub-agent registration, and normalized telemetry.
- The runtime owns the internal loop, SDK-specific model configuration,
  SDK-specific tools, and final result extraction.
- Structured input and output should be enforced at the Condukt boundary, not
  by asking callers to parse free-form SDK output.
- Streaming should be normalized into Condukt events where possible, while
  allowing runtime-specific event details to remain opt in.

This boundary lets external coding agents compose with Condukt sessions without
pretending they are ordinary chat-completion providers.

### Built-in SDK runtimes

Condukt ships runtime adapters for local coding-agent CLIs:

- `Condukt.AgentRuntimes.Codex`: shells out to `codex exec`.
- `Condukt.AgentRuntimes.Claude`: shells out to `claude --print`.

Both adapters run through `MuonTrap`, use the session cwd as the subprocess
working directory, merge resolved session secrets into the subprocess
environment, and pass the composed system prompt to the external agent.

Example:

```elixir
defmodule MyApp.CodexImplementer do
  use Condukt.Agent,
    runtime: {Condukt.AgentRuntimes.Codex, sandbox: "workspace-write"}

  def system_prompt do
    "Implement the requested change and leave the working tree ready for review."
  end
end

defmodule MyApp.ClaudeReviewer do
  use Condukt.Agent,
    runtime: {Condukt.AgentRuntimes.Claude, permission_mode: "acceptEdits"}

  def system_prompt do
    "Review the working tree and report actionable findings."
  end
end
```

Codex runtime options:

- `:command`: executable name or path. Defaults to `"codex"`.
- `:model`: passed as `--model`.
- `:profile`: passed as `--profile`.
- `:sandbox`: passed as `--sandbox`. Defaults to `"workspace-write"`.
- `:approval_policy`: passed as `--ask-for-approval`. Defaults to `"never"`.
- `:extra_args`: appended before the prompt.
- `:env`: trusted environment overrides merged with session secrets.

Claude runtime options:

- `:command`: executable name or path. Defaults to `"claude"`.
- `:model`: passed as `--model`.
- `:permission_mode`: passed as `--permission-mode`. Defaults to
  `"acceptEdits"`.
- `:output_format`: passed as `--output-format`. Defaults to `"text"`.
- `:extra_args`: appended before the prompt.
- `:env`: trusted environment overrides merged with session secrets.

## Running an agent once

For one-shot work, pass the agent module directly to `Condukt.run/3`:

```elixir
{:ok, answer} =
  Condukt.run(MyApp.ResearchAgent, "Summarize this project.",
    api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
    cwd: "/path/to/project"
  )
```

Condukt starts an unlinked transient session, runs the prompt synchronously,
returns the final response, and stops the session. The agent module still
supplies its callbacks and defaults:

1. Options passed to `Condukt.run/3`
2. `config :condukt, ...`
3. Module callback defaults

Module-defined one-shot runs are the default fit for scripts, jobs, request
handlers, and CI tasks where the process should not outlive the call.

## Starting a persistent agent

Start an agent process when you need conversation history, streaming,
persistence, compaction, or supervision across multiple prompts:

```elixir
{:ok, agent} =
  MyApp.ResearchAgent.start_link(
    api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
    cwd: "/path/to/project"
)
```

Resolution order for persistent session configuration is:

1. Options passed to `start_link/1`
2. `config :condukt, ...`
3. Module callback defaults

## Common options

```elixir
MyApp.ResearchAgent.start_link(
  api_key: "sk-ant-...",                        # Provider key
  model: "anthropic:claude-sonnet-4-20250514",  # ReqLLM model id
  base_url: "http://localhost:11434/v1",        # Override provider URL
  llm_request_options: [                         # Extra ReqLLM request options
    req_http_options: [headers: [{"x-tenant", "acme"}]]
  ],
  system_prompt: "You are helpful.",            # Static prompt
  thinking_level: :medium,                      # Thinking budget
  load_project_instructions: true,              # See Project Instructions guide
  cwd: "/path/to/project",                      # Tool working directory
  session_store: Condukt.SessionStore.Memory,   # See Sessions guide
  compactor: {Condukt.Compactor.Sliding, keep: 40}, # See Compaction guide
  redactor: Condukt.Redactors.Regex,            # See Redaction guide
  name: MyApp.ResearchAgent                     # GenServer name
)
```

## Public API

### Trace context and request headers

Set `:llm_request_options` when every native provider call needs extra ReqLLM
options, including trusted gateway headers. Condukt retains these options for
ordinary and streaming calls. It merges trace headers with existing headers,
so adding distributed tracing never drops application metadata.

To opt into [World Wide Web Consortium Trace Context](https://www.w3.org/TR/trace-context/)
propagation for one run, pass `:trace_context`:

```elixir
context = Condukt.TraceContext.new()
Condukt.run(agent, "Review this change.", trace_context: context)
```

Declared operations accept the same `:trace_context` and
`:llm_request_options` call options.

Pass `true` to create a new trace when no context is bound to the calling
process. Omitting the option captures `Condukt.TraceContext.current/0`.
Condukt forwards `traceparent`, optional `tracestate`, and `baggage`, adding
opaque session grouping through `condukt.session.id` baggage. It does not require or configure an
OpenTelemetry software development kit.

`Condukt.run/2` and `Condukt.run/3` support three call shapes:

* `Condukt.run("prompt", opts)` runs an anonymous one-shot run
* `Condukt.run(MyApp.Agent, "prompt", opts)` runs a module-defined one-shot agent
* `Condukt.run(agent_pid_or_name, "prompt", opts)` runs against a persistent session

Since Elixir modules and registered process names are both atoms,
`Condukt.run/3` treats atoms that look like Condukt agent modules as
module-defined one-shot runs. Use a pid or a non-module atom when targeting a
persistent registered session.

For a running agent process, the `Condukt` module also forwards these calls to
`Condukt.Session`:

* `Condukt.run/3` runs a prompt to completion
* `Condukt.stream/3` returns a lazy stream of events
* `Condukt.history/1` returns the current conversation history
* `Condukt.clear/1` clears history
* `Condukt.abort/1` aborts the current operation
* `Condukt.compact/1` runs the configured compactor
* `Condukt.steer/2` injects a message mid run, skipping remaining tool calls
* `Condukt.follow_up/2` queues a message to be delivered after the current run

See the [One-Shot Runs guide](one-shot-runs.md) for prompt-first one-shot runs
without an agent module.

## Handling events in the agent module

Override `handle_event/2` to react to events without subscribing to the stream:

```elixir
@impl true
def handle_event({:tool_call, name, _id, _args}, state) do
  Logger.info("Calling tool: #{name}")
  {:noreply, state}
end

def handle_event(_event, state), do: {:noreply, state}
```

This is the easiest way to add logging, metrics, or pubsub broadcasts.

## Custom `init/1`

`init/1` lets you build per session state when the agent starts. The return
value is stored on the session and passed to `handle_event/2`:

```elixir
@impl true
def init(opts) do
  {:ok, %{started_at: System.monotonic_time(), opts: opts}}
end
```
