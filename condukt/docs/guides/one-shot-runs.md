# One-Shot Runs

One-shot runs are single-call agent sessions. They are useful for scripts,
notebooks, jobs, CI tasks, and callbacks where defining or supervising a
long-lived agent process would add ceremony without adding useful state.

`Condukt.run/2` accepts a prompt as the first argument:

```elixir
{:ok, text} =
  Condukt.run("Summarize README.md in three bullets.",
    model: "anthropic:claude-sonnet-4-20250514",
    tools: [Condukt.Tools.Read]
  )
```

Condukt starts a transient `Condukt.Session`, runs the prompt, returns the
final text, and stops the session. No conversation history is kept across
calls.

If you already have an agent module and want its callbacks without managing a
long-lived process, pass the module as the first argument instead:

```elixir
{:ok, text} =
  Condukt.run(MyApp.ReviewAgent, "Review the current branch.",
    timeout: 120_000
  )
```

This module-defined one-shot form uses the agent's `system_prompt/0`,
`tools/0`, `model/0`, sandbox, secrets, and sub-agent defaults. It also
supports typed input and structured output through the same options described
below.

## Runtime options

Anonymous runs accept the same run options as agent runs:

* `:timeout` caps the synchronous call timeout in milliseconds
* `:max_turns` caps tool-use loops
* `:images` attaches images to the user message

They also accept the same session options you would pass to an agent's
`start_link/1`, including `:model`, `:api_key`, `:base_url`,
`:system_prompt`, `:thinking_level`, `:tools`, `:sandbox`, `:cwd`,
`:subagents`, `:session_store`, `:compactor`, `:redactor`, and
`:load_project_instructions`.

Anonymous runs default `:load_project_instructions` to `false`. Pass
`load_project_instructions: true` when you want `AGENTS.md`, `CLAUDE.md`, and
local skills to shape the transient run.

## Typed input

Use `:input` when you want the prompt to be instructions and the arguments to
be a separate JSON payload:

```elixir
{:ok, text} =
  Condukt.run("Review the supplied pull request metadata.",
    input: %{repo: "tuist/condukt", pr_number: 42},
    input_schema: %{
      type: "object",
      properties: %{
        repo: %{type: "string"},
        pr_number: %{type: "integer"}
      },
      required: ["repo", "pr_number"]
    }
  )
```

When `:input_schema` is present, Condukt validates the input with JSV before
making an LLM request. Input must be a map.

## Structured output

Use `:output` to require a JSON Schema-shaped result:

```elixir
{:ok, %{verdict: "approve", summary: summary}} =
  Condukt.run("Decide a review verdict.",
    input: %{repo: "tuist/condukt", pr_number: 42},
    output: %{
      type: "object",
      properties: %{
        verdict: %{type: "string", enum: ["approve", "request_changes", "comment"]},
        summary: %{type: "string"}
      },
      required: ["verdict", "summary"]
    }
  )
```

Structured mode appends a synthetic `submit_result` tool. The model calls that
tool with the final result, Condukt validates the submitted map with JSV, and
the validated value is returned.

If the schema's top-level `properties` keys are atoms, Condukt atomizes the
matching top-level result keys after validation.

## Inline tools

For small run-specific tools, use `Condukt.tool/1`:

```elixir
ls =
  Condukt.tool(
    name: "ls",
    description: "Lists files under a glob.",
    parameters: %{
      type: "object",
      properties: %{pattern: %{type: "string"}},
      required: ["pattern"]
    },
    call: fn %{"pattern" => pattern}, context ->
      Condukt.Sandbox.glob(context.sandbox, pattern)
    end
  )

{:ok, text} =
  Condukt.run("List Elixir files under lib/.",
    tools: [ls]
  )
```

Inline tool callbacks receive the same context map as module tools:
`:agent`, `:sandbox`, `:cwd`, and `:opts`. `:opts` is always `[]` for inline
tools.

## Anonymous sub-agents

Anonymous runs can register sub-agents inline with `:subagents`. Use
`role: [opts]` when the child does not need a named module:

```elixir
{:ok, text} =
  Condukt.run("Plan the release notes.",
    subagents: [
      researcher: [
        model: "anthropic:claude-haiku-4-5",
        system_prompt: "Find facts and return concise notes.",
        tools: [Condukt.Tools.Read]
      ]
    ]
  )
```

Inline sub-agent opts are normal session opts plus the optional `:input` and
`:output` schemas documented in the sub-agents guide. Anonymous sub-agents
default `:load_project_instructions` to `false`; set it to `true` in the role
opts when the child should load project instructions.

## Errors

Anonymous runs return `{:error, reason}` for validation failures, LLM
errors, and session startup failures.

Common structured run reasons include:

* `{:invalid_input, %JSV.ValidationError{}}`
* `{:invalid_output, %JSV.ValidationError{}}`
* `{:invalid_input, :input_must_be_a_map}`
* `:no_result_submitted`

## Choosing an API

Use `Condukt.run("prompt", opts)` when the task fits in one call and no
module-level agent identity is useful.

Use `Condukt.run(MyApp.Agent, prompt, opts)` when the task fits in one call
but the agent module's callbacks are useful.

Use `operation/2` when you want a named compile-time entrypoint on an agent
module.

Use a supervised agent process when you need long-lived state, conversation
history, streaming interaction, or OTP supervision.
