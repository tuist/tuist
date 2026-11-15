# Sub-agents

A sub-agent is a specialized agent that a parent agent can delegate work to.
The parent model picks a registered role, sends it a task, and receives the
child agent's final answer as a tool result. Each sub-agent is a full
`Condukt.Session` with its own model, system prompt, tools, and conversation
history.

Use a sub-agent when work needs several reasoning steps, but should stay out
of the parent agent's conversation history. Use a normal tool when the work is
a single function call.

## Declaring sub-agents

Agents declare sub-agents with `subagents/0`. The callback mirrors `tools/0`:

```elixir
defmodule MyApp.LeadAgent do
  use Condukt

  @impl true
  def tools, do: Condukt.Tools.read_only_tools()

  @impl true
  def subagents do
    [
      researcher: MyApp.ResearchAgent,
      coder:
        {MyApp.CoderAgent,
         model: "anthropic:claude-sonnet-4-20250514",
         input: %{
           type: "object",
           properties: %{
             files: %{type: "array", items: %{type: "string"}},
             focus: %{type: "string"}
           },
           required: ["files"]
         },
         output: %{
           type: "object",
           properties: %{
             summary: %{type: "string"},
             changed_files: %{type: "array", items: %{type: "string"}}
           },
           required: ["summary", "changed_files"]
         }},
      summarizer: [
        model: "anthropic:claude-haiku-4-5",
        system_prompt: "Summarize delegated context into concise notes."
      ]
    ]
  end
end
```

Each entry is `role: AgentModule`, `role: {AgentModule, opts}`, or
`role: opts` for an anonymous child agent. The role atom is the identifier the
parent model uses. Most registration opts are passed to the child session
startup call. `:input`, `:input_schema`, `:output`, and `:output_schema` are
reserved for the sub-agent contract, and `:background` makes the role a
[background sub-agent](#background-sub-agents).

Anonymous child agents use the internal anonymous agent module, so you can
configure the child inline with session options such as `:model`,
`:system_prompt`, `:tools`, `:sandbox`, and structured contract options.
They default `:load_project_instructions` to `false`; set it to `true` in the
role opts if the child should load project instructions.

You can also override registrations when starting a session:

```elixir
{:ok, agent} =
  MyApp.LeadAgent.start_link(
    subagents: [
      reviewer: {MyApp.ReviewerAgent, model: "openai:gpt-5.2"},
      summarizer: [model: "anthropic:claude-haiku-4-5"]
    ]
  )
```

## The subagent tool

When `subagents/0` returns at least one role, Condukt injects one built-in
tool into the parent agent:

```json
{
  "name": "subagent",
  "parameters": {
    "type": "object",
    "oneOf": [
      {
        "type": "object",
        "properties": {
          "role": {"type": "string", "enum": ["researcher"]},
          "task": {"type": "string"}
        },
        "required": ["role", "task"]
      },
      {
        "type": "object",
        "properties": {
          "role": {"type": "string", "enum": ["coder"]},
          "task": {"type": "string"},
          "input": {
            "type": "object",
            "properties": {
              "files": {"type": "array", "items": {"type": "string"}},
              "focus": {"type": "string"}
            },
            "required": ["files"]
          }
        },
        "required": ["role", "task", "input"]
      }
    ]
  }
}
```

The model sees a role-specific schema. Fields listed in the JSON Schema
`required` list are required. Properties omitted from `required` stay optional.
When the model calls the tool, Condukt validates the optional structured input,
starts a child session, runs the task, returns the final result as the tool
result, and then terminates the child session.

## Ownership and cancellation

Ownership follows the process tree. Each turn runs in its own process under
the parent session, each tool call in a process linked to the turn, and a
`subagent` call starts a supervisor linked to itself and runs its child session
under it. The child's turn and tool calls hang below the child the same way.

- `Condukt.abort/1` on the parent, a `{:stop, reason, state}` from its
  `handle_event/2`, and `Condukt.clear/1` shut the turn's process down before
  they return. Its tool calls go down with it through their links. When a
  `subagent` call goes down, its supervisor shuts the child session down,
  which takes the child's own turn, tool calls, and sub-agents with it, all
  the way down the tree.
- The parent's turn ends only once its tool calls have returned, so it is
  never idle while a foreground child still runs.
- A tool that must not stop halfway opts out with `c:Condukt.Tool.on_abort/1`
  returning `:finish`, and runs to the end with its result discarded. See
  "Aborts" in `Condukt.Tool`.

Background sub-agents are owned by the parent session, not a turn, and keep
working through an abort. The `background_subagent` tool asks to finish, so an
abort never leaves a sub-agent started but unregistered. A `wait` in progress
ends with `{:error, :aborted}`.

## Streaming child events

When the parent streams, a foreground child streams too, and each of its
events reaches the parent's stream and notifier tagged with the parent's tool
call:

```elixir
{:subagent, tool_call_id, event}
```

`event` is any event from the
[event vocabulary](streaming-and-events.md#event-vocabulary), including the
child's `:done`. The `tool_call_id` matches the `{:tool_call, "subagent", id,
args}` event the parent emitted, so a UI can render the child's work under the
call that started it:

```elixir
parent
|> Condukt.stream("Research the release notes")
|> Enum.each(fn
  {:tool_call, "subagent", id, %{"role" => role}} -> IO.puts("[#{id}] #{role} started")
  {:subagent, id, {:text, chunk}} -> IO.write("[#{id}] " <> chunk)
  {:tool_result, id, _result} -> IO.puts("\n[#{id}] finished")
  {:text, chunk} -> IO.write(chunk)
  _event -> :ok
end)
```

Forwarded events are not passed to the parent's `handle_event/2`. When the
parent uses `Condukt.run/3`, children run without streaming and nothing is
forwarded. A child whose runtime cannot stream runs without streaming too.

## Background sub-agents

A role registered with `background: true` is a persistent sub-agent: a named
session that keeps its conversation, works while the parent answers, and
reports back when it is done.

```elixir
def subagents do
  [
    researcher: MyApp.ResearchAgent,
    reader: {MyApp.ReaderAgent, background: true}
  ]
end
```

Background roles are offered through a second built-in tool,
`background_subagent`, and one-shot roles through `subagent`; an agent with
both kinds gets both tools. The parent model calls `background_subagent` with
an `action`:

| Action | Arguments | Effect |
| ------ | --------- | ------ |
| `spawn` | `name`, `role`, `message`, optional `input` | Starts a sub-agent called `name` and gives it its first task. |
| `send` | `name`, `message`, optional `follow_up` | Steers the sub-agent's current work, or with `follow_up: true` queues the message after its current answer. An idle sub-agent starts on it at once. |
| `wait` | `name` | Returns the sub-agent's latest answer once it is idle. |
| `stop` | `name` | Aborts its current work and drops its queued messages. The sub-agent stays usable. |
| `list` | | Every sub-agent with its role, session id, and `working` or `idle` status. |

Every answer the parent did not `wait` for is posted back to the parent as a
user message, such as `[subagent reader answered] ...`, or
`[subagent reader failed: ...]` when its turn failed. It starts a parent turn
when the parent is idle, or waits behind the current one and any queued input.
A report still waiting when `wait` returns the same answer is withdrawn, so
the parent hears each answer once. Aborting the parent's turn keeps waiting
reports: an answer already given still arrives. A stopped turn reports
nothing. With an `:output` schema, the report and `wait` carry the validated
structured result.

Ownership works differently from foreground calls:

- A background sub-agent belongs to the parent session. Aborting a parent turn
  does not stop it; only `stop`, or stopping the parent session, does.
- It is registered under its parent and name. Host code finds it with
  `Condukt.Tools.BackgroundSubagent.whereis(parent, name)` and drives it with
  the usual functions, such as `Condukt.history/1`, `Condukt.steer/2`, or
  `Condukt.abort/1`. Two spawns cannot take the same name.
- A `wait` call belongs to the turn that made it, like any tool call. Aborting
  that turn ends the wait, and the answer is reported as a follow-up instead.
- The sub-agent's events are forwarded to the parent's notifier, tagged with
  the `spawn` call's id, for as long as it lives. They do not go to a parent
  stream, which ends with its turn. A viewer of the parent sees each
  sub-agent under its name in the view's `background`, with its status and
  current turn; see [Watching a session](streaming-and-events.md#watching-a-session).
  A `:notifier` set on the role still receives the sub-agent's own events.

Background sub-agents live only in memory: they end with the parent session
and are not restored with its conversation. Their roles must use the native
runtime, because their turns start from queued input and stream to the
manager that tracks them; `spawn` returns
`{:error, {:background_subagent_requires_native_runtime, agent}}` otherwise.

## Structured input and output

Sub-agent input and output schemas are optional:

- `:input` or `:input_schema` validates the `input` argument on the `subagent`
  tool call before the child starts.
- `:output` or `:output_schema` adds a `submit_result` tool to the child
  session and validates the submitted value before returning it to the parent.
- If no output schema is declared, the child returns free-form text.

Example:

```elixir
def subagents do
  [
    reviewer:
      {MyApp.ReviewerAgent,
       input: %{
         type: "object",
         properties: %{
           path: %{type: "string"},
           severity: %{type: "string", enum: ["low", "medium", "high"]}
         },
         required: ["path"]
       },
       output: %{
         type: "object",
         properties: %{
           findings: %{type: "array", items: %{type: "object"}},
           summary: %{type: "string"}
         },
         required: ["findings", "summary"]
       }}
  ]
end
```

In this example `path` is required and `severity` is optional. The parent
receives a validated map with `findings` and `summary` instead of parsing text.

## Inheritance

By default a child sub-agent inherits these parent session values:

- `:sandbox`
- `:cwd`
- `:model`
- `:thinking_level`
- `:api_key`
- `:base_url`
- `:secrets`

Registration opts override inherited values:

```elixir
def subagents do
  [
    researcher: {MyApp.ResearchAgent, sandbox: Condukt.Sandbox.Local}
  ]
end
```

The default shared sandbox keeps file operations consistent. A sub-agent that
reads `lib/foo.ex` sees the same filesystem view as the parent unless the
registration overrides `:sandbox` or `:cwd`.

Tool surfaces are not inherited. Each sub-agent declares its own `tools/0`,
and MCP servers behave the same way: a child does not see MCP servers
declared on the parent. Declare them per role:

- Named sub-agent modules expose their own `mcp_servers/0` callback. See
  [MCP](mcp.md).
- Anonymous sub-agents can opt in inline with `:mcp_servers` in the role
  opts:

  ```elixir
  def subagents do
    [
      researcher: [
        model: "anthropic:claude-haiku-4-5",
        mcp_servers: [
          %Condukt.MCP.Server{
            name: "docs",
            transport: {:stdio, command: "docs-mcp", args: []}
          }
        ]
      ]
    ]
  end
  ```

This keeps each role's tool surface deliberate and avoids sharing live MCP
connections across agents.

## Supervision

A foreground child runs under a `DynamicSupervisor` its tool call starts and
stops, with `restart: :temporary`. A parent session with sub-agents also starts
a linked `DynamicSupervisor` for its background sub-agents and their manager.

Properties:

- Stopping the parent session stops the sub-agent supervisor and its children,
  background ones included.
- A child that fails to start or crashes returns an error to the parent tool
  call. The parent session keeps running. A background sub-agent that crashes
  is removed, and its failure is reported like an answer.
- Foreground child sessions are one-shot. They are started for one task and
  terminated once it finishes or is aborted.
- When a model emits multiple tool calls in one turn, Condukt executes them
  concurrently and preserves result order in the conversation history.

## Events

Condukt emits `[:condukt, :subagent, :start]` and
`[:condukt, :subagent, :stop]` telemetry events around each delegation. The
metadata identifies the parent agent, role, child agent, whether structured
input and output contracts are configured, and the final `:status`.

The telemetry never includes task text, structured input values, or structured
output values. Background sub-agents emit the child sessions' own telemetry,
and no `[:condukt, :subagent, ...]` span.

Child stream events reach the parent as `{:subagent, tool_call_id, event}`; see
[Streaming child events](#streaming-child-events).

## Errors

Unknown roles return:

```elixir
{:error, "no sub-agent registered as writer"}
```

Child start failures and child crashes return `{:error, reason}` from the
tool call. The model receives that error as the tool result and can recover in
the next turn. An aborted call returns nothing; the parent's caller gets
`{:error, :aborted}`.
