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
reserved for the sub-agent contract.

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

A parent session with sub-agents starts a linked `DynamicSupervisor`.
Sub-agent sessions are started on demand under that supervisor with
`restart: :temporary`.

Properties:

- Stopping the parent session stops the sub-agent supervisor and its children.
- A child that fails to start or crashes returns an error to the parent tool
  call. The parent session keeps running.
- Child sessions are one-shot in this version. They are started for one task
  and terminated after `Condukt.run/2` returns.
- When a model emits multiple tool calls in one turn, Condukt executes them
  concurrently and preserves result order in the conversation history.

## Events

Condukt emits `[:condukt, :subagent, :start]` and
`[:condukt, :subagent, :stop]` telemetry events around each delegation. The
metadata identifies the parent agent, role, child agent, whether structured
input and output contracts are configured, and the final `:status`.

The telemetry never includes task text, structured input values, or structured
output values.

For now, child stream events are not forwarded to the parent stream. The parent
stream observes the `subagent` tool call and the matching tool result.
Forwarding child events as tagged parent events can be added later without
changing the declaration API.

## Errors

Unknown roles return:

```elixir
{:error, "no sub-agent registered as writer"}
```

Child start failures and child crashes return `{:error, reason}` from the
tool call. The model receives that error as the tool result and can recover in
the next turn.
