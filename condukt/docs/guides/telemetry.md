# Telemetry

Condukt emits `:telemetry` events for the major phases of an agent run.
Attach handlers to feed your existing observability stack: Logger,
`telemetry_metrics`, Prometheus, OpenTelemetry, or anything else.

## Events

| Event | Measurements | Metadata |
| ----- | ------------ | -------- |
| `[:condukt, :agent, :start]` | `system_time` | `:agent`, `:session_id` |
| `[:condukt, :agent, :stop]` | `duration` | `:agent`, `:session_id` |
| `[:condukt, :llm_turn, :start]` | `system_time` | `:agent`, `:session_id`, `:model`, `:turn`, `:streaming?`, `:messages`, `:tool_count` |
| `[:condukt, :llm_turn, :stop]` | `duration` | same as `:start` plus `:status`, `:assistant_message`, `:usage`, `:finish_reason`, `:error` |
| `[:condukt, :tool_call, :start]` | `system_time` | `:tool`, `:tool_call_id`, `:args`, `:agent`, `:session_id` |
| `[:condukt, :tool_call, :stop]` | `duration` | `:tool`, `:tool_call_id`, `:args`, `:agent`, `:session_id`, `:status`, `:result` |
| `[:condukt, :subagent, :start]` | `system_time` | `:agent`, `:role`, `:child_agent`, `:input?`, `:output?`, `:parent_session_id` |
| `[:condukt, :subagent, :stop]` | `duration` | `:agent`, `:role`, `:child_agent`, `:input?`, `:output?`, `:status`, `:error`, `:parent_session_id`, `:session_id` |
| `[:condukt, :subagent, :exception]` | `duration` | `:agent`, `:role`, `:child_agent`, `:input?`, `:output?`, `:parent_session_id`, `:kind`, `:reason`, `:stacktrace` |
| `[:condukt, :operation, :start]` | `system_time` | `:agent`, `:operation`, `:session_id` |
| `[:condukt, :operation, :stop]` | `duration` | `:agent`, `:operation`, `:session_id` |
| `[:condukt, :run, :start]` | `system_time` | `:structured?`, `:input?`, `:session_id` |
| `[:condukt, :run, :stop]` | `duration` | `:structured?`, `:input?`, `:session_id` |
| `[:condukt, :compact, :stop]` | `duration`, `before`, `after` | `:agent`, `:session_id` |
| `[:condukt, :secrets, :resolve]` | `count` | `:agent`, `:names`, `:session_id` |
| `[:condukt, :secrets, :access]` | `count` | `:agent`, `:tool`, `:tool_call_id`, `:names`, `:session_id` |

The exact set may grow over time. Attach broadly with `attach_many/4` so
new events surface in your handlers without code changes.

## Telemetry payloads

Every iteration of the agent loop emits a `[:condukt, :llm_turn, :start]`
and a `[:condukt, :llm_turn, :stop]`. The start event includes the conversation
context in `:messages`, and the stop event includes the model response in
`:assistant_message`. Tool events include the model-supplied `:args`,
`:tool_call_id`, `:status`, and `:result` after session-secret redaction.

`:turn` starts at 0 and increments by one per loop iteration.
`:streaming?` is `true` when the call went through `ReqLLM.stream_text`,
`false` when it went through `ReqLLM.generate_text`. `:usage` is the
provider-reported token usage map when available, `nil` otherwise.

Exception events include `:kind`, `:reason`, and `:stacktrace`. Telemetry
consumers that export metadata outside the application should redact, filter,
or sample these payloads to match their data-handling policy.

## Distributed trace propagation

Condukt can propagate [World Wide Web Consortium Trace Context](https://www.w3.org/TR/trace-context/)
headers to provider requests without requiring an OpenTelemetry software
development kit or exporting telemetry. Pass `trace_context: true` to start a
new trace for one run, pass a `Condukt.TraceContext`, or bind a context in the
calling process:

```elixir
context = Condukt.TraceContext.new()

Condukt.run(MyApp.Agent, "Summarize this report.",
  trace_context: context
)
```

For an inbound request, extract the headers at the request boundary and bind
the result before calling Condukt:

```elixir
with {:ok, context} <- Condukt.TraceContext.from_headers(conn.req_headers) do
  Condukt.TraceContext.put_current(context)
end
```

Applications that already use the [OpenTelemetry](https://opentelemetry.io/)
Elixir API can bind its current trace in one line instead:

```elixir
Condukt.TraceContext.put_current_from_otel!()
```

The bridge dynamically uses OpenTelemetry's configured text-map propagator to
read the current trace and baggage, so Condukt does not add OpenTelemetry as a
dependency. Call it at the request or job boundary before `Condukt.run/2`.

Native provider requests receive `traceparent`, optional `tracestate`, and
`baggage`. Condukt adds its opaque `condukt.session.id` baggage value. This makes a gateway able to attribute each
request to both a distributed trace and its Condukt session without coupling
the application to a particular gateway.

Context is captured at every public run or stream boundary and carried through
the session task, concurrent tool calls, sub-agent tasks, and child sessions.
Each provider attempt gets a fresh child span identifier, including retries. Existing
`:llm_request_options`, including request headers and baggage, are preserved;
Condukt only owns the trace header names and its session grouping value.

```elixir
MyApp.Agent.start_link(
  llm_request_options: [
    req_http_options: [headers: [{"x-tenant", "acme"}]]
  ]
)
```

ReqLLM 1.21.0 and later forwards these request headers for both ordinary and
streaming OpenAI-compatible calls.

## Session ids

Every event emitted from a `Condukt.Session` (or a runtime entry point that
spins up a transient one) carries a `:session_id` in metadata. Sessions
generate a UUIDv7 at startup unless the caller passes an explicit `:id`
option to `Condukt.start_link/2` or `Condukt.run/2`. UUIDv7 ids are
time-ordered, so persisting them keeps storage and indexes aligned with
chronological order.

Use `:session_id` to group all events emitted by a single agentic run, for
example to persist a per-run audit trail. `Condukt.run/2` and
`Condukt.Operation.run/4` generate the id once and reuse it for both their
wrapping `:run` / `:operation` events and the inner agent and tool events.

Sub-agent delegation events expose both ids: `:parent_session_id` is the
session that called the subagent tool, and `:session_id` (on `:stop`) is
the child session created by the delegation. This lets observability tools
reconstruct full parent/child traces.

Secret events are value-free. `:names` contains environment variable names
such as `["GH_TOKEN"]`, never the resolved secret values. `:tool_call_id` is
present when the access comes from a provider-returned tool call.

Sub-agent events are value-free too. They identify the parent agent module,
the delegated role, the child agent module, whether structured input and output
contracts are configured, and whether delegation ended with `:ok` or `:error`.
The `:error` metadata is an atom such as `:invalid_input`, not the rejected
input or output payload. Delegation also uses the standard telemetry span
lifecycle, so an unexpected exception emits `[:condukt, :subagent, :exception]`.

## Attaching a handler

```elixir
:telemetry.attach_many(
  "condukt-logger",
  [
    [:condukt, :agent, :start],
    [:condukt, :agent, :stop],
    [:condukt, :tool_call, :start],
    [:condukt, :tool_call, :stop],
    [:condukt, :subagent, :start],
    [:condukt, :subagent, :stop],
    [:condukt, :operation, :start],
    [:condukt, :operation, :stop],
    [:condukt, :run, :start],
    [:condukt, :run, :stop],
    [:condukt, :compact, :stop],
    [:condukt, :secrets, :resolve],
    [:condukt, :secrets, :access]
  ],
  fn event, measurements, metadata, _config ->
    Logger.info("#{inspect(event)} #{inspect(measurements)} #{inspect(metadata)}")
  end,
  nil
)
```

Attach this once at application start.

## With `telemetry_metrics`

```elixir
def metrics do
  [
    summary("condukt.agent.stop.duration",
      unit: {:native, :millisecond}
    ),
    summary("condukt.tool_call.stop.duration",
      tags: [:tool],
      unit: {:native, :millisecond}
    ),
    counter("condukt.tool_call.stop.count", tags: [:tool]),
    summary("condukt.subagent.stop.duration", tags: [:agent, :role, :child_agent, :status]),
    counter("condukt.subagent.stop.count", tags: [:agent, :role, :child_agent, :status]),
    counter("condukt.secrets.access.count", tags: [:agent, :tool])
  ]
end
```

## Tracing tool calls

Tool call start and stop events share an implicit span via the `:telemetry`
span helpers. With OpenTelemetry you can wrap them with a span processor
that turns each `[:condukt, :tool_call, :*]` pair into a span keyed by the
`:tool` metadata.
