# Compaction

Long-running agents accumulate messages that grow past the model's context
window. A compactor keeps the history bounded by dropping or summarising
older messages. Condukt applies the configured compactor before every native model request,
including tool-loop iterations and restored sessions, and after run completion
before persisting history. Both buffered and streaming runs use the compacted
messages for inference and per-turn telemetry. `Condukt.compact/1` triggers it
manually. Custom compactors should be safe to apply repeatedly: not every
invocation needs to change history.
For expensive compactors, opt into background compaction in native sessions.

## Configuring a compactor

```elixir
# Keep only the last 40 messages
MyApp.CodingAgent.start_link(
  compactor: {Condukt.Compactor.Sliding, keep: 40}
)

# Replace large old tool result payloads with placeholders
MyApp.CodingAgent.start_link(
  compactor:
    {Condukt.Compactor.ToolResultPrune, keep_recent: 5, max_size: 4_000}
)
```

A bare module is also accepted when the defaults are fine:

```elixir
MyApp.CodingAgent.start_link(compactor: Condukt.Compactor.Sliding)
```

## Background compaction

Background compaction runs the same `compact/2` callback in a supervised task
while the conversation continues. It does not cancel an active response or
rewrite the input of an in-flight inference request.

```elixir
MyApp.CodingAgent.start_link(
  compactor: MyApp.SummarisingCompactor,
  background_compaction: [
    context_window: 200_000,
    background_threshold: 0.65,
    blocking_threshold: 0.9,
    keep_recent_tokens: 20_000,
    timeout: 60_000
  ]
)
```

`background_compaction: true` uses these defaults and the context window
from the effective model's ReqLLM metadata, including a model restored from
the session snapshot. Supply `:context_window` to override that window or for
models without metadata. `nil` and `false` preserve synchronous compaction
before each native request and after turn completion. The option requires
a configured `:compactor`.

At the background threshold, Condukt captures an older prefix and keeps
approximately `:keep_recent_tokens` of recent messages outside the task.
The active user prompt and every message appended during that turn are always
protected, even when they exceed this retention budget. Prefix adoption shifts
that boundary without changing the protected suffix.
The callback receives **only that prefix**, and returns its replacement.
The session adds the unchanged recent messages and everything appended since
the task started. A compactor must preserve any information needed from its
input and return a provider-valid replacement, usually a user-message summary.

Only one compaction runs per session. Both `run` and `stream` adopt ready
results before the next inference request, after a tool batch has completed,
or while the session is idle. Prefix selection never splits an assistant's
tool calls from their results. Clearing history cancels pending work; a
completed task cannot restore cleared history. Aborting a turn releases its
wait without cancelling a background task that can still be reused. Returning
`{:stop, reason, state}` from `handle_event/2` cancels the turn the same way.
Late responses and stream events from a cancelled turn cannot dispatch tools,
overwrite an adopted summary, or affect a replacement turn. Cancellation does
not stop provider requests already in flight or roll back tools already admitted
to execution. The cancelled caller finishes without waiting for that work;
native retry backoff wakes and later provider attempts are rejected.

### Blocking fallback

Before each inference request, reaching `:blocking_threshold` makes the
agent loop wait for pending compaction. The session process still serves
history reads, aborts, and other control calls. If background work fails or
its result leaves too much context, Condukt tries one fresh compaction over
a larger prefix, retaining the active prompt and its entire suffix. This budget
is per blocking checkpoint; a new turn after cancellation gets a new budget.

If that attempt fails, crashes, times out, or still cannot fit the request,
the run returns `{:error, {:compaction_failed, reason}}`; a stream emits the
same error. `:context_limit` means the remaining context is too large.
Condukt does not silently discard the newest prompt or send a request it
already estimates as oversized. Background compaction reduces pauses; it
does not guarantee that the next request will never wait.

Threshold accounting uses the last provider-reported input usage, including
cache reads and writes when those are reported separately, plus estimates for
appended messages. Cached tokens are not counted twice when already included
in `:input_tokens`. Before usage is available, and after history changes, it
estimates message content, system instructions, and tool schemas at roughly
four bytes per token plus message overhead. An explicitly set
`:max_tokens` is also reserved for output, taking the top-level option first
and then `llm_request_options[:max_tokens]`. Structured tool results are counted
as their rendered provider text, including JSON structure and rendered errors;
tool arguments and schemas include their serialized structure too.
These are heuristics, not exact tokenization, especially for images and
non-English text. Leave headroom and
bound large tool outputs for your model and workload.

Successful replacements are persisted through the existing session store.
Pending tasks are not persisted and are recomputed after a restart.
`Condukt.compact/1` still waits for completion; with background mode enabled,
it uses a task without blocking the session process and requires an idle
session. It returns `{:error, :already_streaming}` when a turn or another manual
compaction is active. The callback receives the full history for this manual
operation, rather than a selected prefix.

Manual compaction retains exclusivity if its caller disconnects, until it
finishes, reaches its worker timeout, or is explicitly aborted or cleared.
The public manual call has a 300-second deadline, so use a shorter worker
timeout when its caller must receive the result rather than time out first.

## Built-in compactors

### `Condukt.Compactor.Sliding`

Keeps the most recent N messages and drops everything older. Orphaned tool
result messages (whose paired tool call was dropped) are removed so the
conversation stays valid.

### `Condukt.Compactor.ToolResultPrune`

Replaces oversized historical tool result payloads with a short placeholder.
The surrounding reasoning, user messages, and recent tool results are left
intact. This is the right choice when tool output is large but the model
still benefits from seeing what it asked and what it concluded.

## Implementing a compactor

```elixir
defmodule MyApp.SummarisingCompactor do
  @behaviour Condukt.Compactor

  @impl true
  def compact(messages, _opts) do
    {older, recent} = Enum.split(messages, -10)
    summary = MyApp.Summariser.summarise(older)

    {:ok, [summary | recent]}
  end
end

MyApp.CodingAgent.start_link(compactor: MyApp.SummarisingCompactor)
```

`compact/2` returns `{:ok, messages}` on success or `{:error, reason}` to
abort compaction (the original history is kept).

In background mode, recent-history retention belongs to the session instead.
A summarising callback can summarise its entire input prefix:

```elixir
def compact(prefix, _opts) do
  summary = MyApp.Summariser.summarise(prefix)
  {:ok, [Condukt.Message.user(summary)]}
end
```

## Telemetry

Each configured compaction attempt emits `[:condukt, :compact, :start]` with
`system_time` and `[:condukt, :compact, :stop]` with measurements:

* `:duration` (native time)
* `:before` (message count before)
* `:after` (message count after)
* `:before_bytes` and `:after_bytes` (Erlang external-term sizes, not token counts)

Both events identify `:agent` (the agent module) and `:session_id`. Stop metadata
also contains `:status` (`:ok` or `:error`) and `:changed` (whether the messages
actually changed). Pruning payloads can reduce bytes without changing the message
count. No message content is included. Failed compactors preserve the original
history and emit `status: :error, changed: false`.

Use start/stop to show activity, and only report successful pruning when
`changed: true`. A no-op is not a context summary. Manual compaction and completion
persistence use the same telemetry contract.

For background work, counts and byte sizes describe the captured prefix and
its replacement. The stop event reports callback completion, even if the
session later discards that result. It does not report adoption.
