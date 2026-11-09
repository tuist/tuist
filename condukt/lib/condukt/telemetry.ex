defmodule Condukt.Telemetry do
  @moduledoc """
  Telemetry integration for Condukt.

  Condukt emits telemetry events that can be used for monitoring,
  logging, and observability.

  ## Events

  Every event emitted from a `Condukt.Session` (and the runtime entry points
  that spin one up) carries a `:session_id` field in metadata. Sessions
  generate a UUIDv7 on start unless the caller supplies an `:id` option;
  downstream consumers can use it to correlate every event for a single run
  in their observability stack. See `docs/guides/telemetry.md` for details.

  ### Agent Events

  - `[:condukt, :agent, :start]` - Agent started processing a prompt
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{agent: module, session_id: String.t()}`

  - `[:condukt, :agent, :stop]` - Agent finished processing
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module, session_id: String.t()}`

  - `[:condukt, :agent, :exception]` - Agent raised an exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module, session_id: String.t(), kind: atom, reason: term, stacktrace: list}`

  ### LLM Turn Events

  Wrap a single LLM round-trip inside an agent loop iteration. One
  `:llm_turn` pair fires per call to the underlying provider, so
  multi-turn agent runs emit one pair per turn (the same `:session_id`
  appears on each pair, with `:turn` increasing).

  - `[:condukt, :llm_turn, :start]` - LLM call started
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{agent: module, session_id: String.t(), model: term, turn: non_neg_integer, streaming?: boolean, messages: [Condukt.Message.t()], tool_count: non_neg_integer}`

  - `[:condukt, :llm_turn, :stop]` - LLM call returned
    - Measurements: `%{duration: integer}`
    - Metadata: same as `:start` plus `%{status: :ok | :error, assistant_message: Condukt.Message.t() | nil, usage: map | nil, finish_reason: atom | nil, error: term | nil}`

  - `[:condukt, :llm_turn, :exception]` - LLM call raised an exception
    - Measurements: `%{duration: integer}`
    - Metadata: same as `:start` plus `%{kind: atom, reason: term, stacktrace: list}`

  `:messages` is the conversation context handed to the model for this
  turn. `:assistant_message` is the model's response, including any
  tool calls it issued. Together they let downstream consumers persist
  a complete transcript of an agentic run.

  ### Tool Events

  - `[:condukt, :tool_call, :start]` - Tool call started
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{tool: string, tool_call_id: string, args: map, agent: module, session_id: String.t()}`

  - `[:condukt, :tool_call, :stop]` - Tool call completed
    - Measurements: `%{duration: integer}`
    - Metadata: `%{tool: string, tool_call_id: string, args: map, agent: module, session_id: String.t(), status: :ok | :error, result: term}`

  - `[:condukt, :tool_call, :exception]` - Tool call raised an exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{tool: string, tool_call_id: string, args: map, agent: module, session_id: String.t(), kind: atom, reason: term, stacktrace: list}`

  `:args` is the parsed argument map the model passed to the tool. `:result`
  on `:stop` is the tool's return value after session-secret redaction; on
  errors it is the `{:error, reason}` tuple. Consumers that ship payloads to
  external systems should size-limit or sample these fields themselves.

  ### Sub-agent Events

  These events wrap the explicit sub-agent delegation lifecycle. They do not
  include task text, structured input values, or structured output values.

  - `[:condukt, :subagent, :start]` - Sub-agent delegation started
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{agent: module | pid, role: atom, child_agent: module, input?: boolean, output?: boolean, parent_session_id: String.t() | nil}`

  - `[:condukt, :subagent, :stop]` - Sub-agent delegation finished
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module | pid, role: atom, child_agent: module, input?: boolean, output?: boolean, status: :ok | :error, parent_session_id: String.t() | nil, session_id: String.t() | nil}`
    - Error metadata: `%{error: atom}`

  - `[:condukt, :subagent, :exception]` - Sub-agent delegation raised an exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module | pid, role: atom, child_agent: module, input?: boolean, output?: boolean, parent_session_id: String.t() | nil, kind: atom, reason: term, stacktrace: list}`

  `:parent_session_id` is the calling session's id; `:session_id` (only on
  `:stop`) is the child session's id, present when the child started
  successfully.

  ### Secret Events

  These events never include secret values.

  - `[:condukt, :secrets, :resolve]` - Session secrets resolved
    - Measurements: `%{count: non_neg_integer}`
    - Metadata: `%{agent: module, names: [String.t()], session_id: String.t()}`

  - `[:condukt, :secrets, :access]` - A tool received resolved session secrets
    - Measurements: `%{count: non_neg_integer}`
    - Metadata: `%{agent: module, tool: String.t(), names: [String.t()], session_id: String.t()}`
    - Optional metadata: `%{tool_call_id: String.t()}`

  ### Operation Events

  Wrap a full `Condukt.Operation.run/4` call (input validation, transient
  session run, output validation). The inner LLM loop still emits the
  `[:condukt, :agent, ...]` events for free.

  - `[:condukt, :operation, :start]` - Operation invocation started
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{agent: module, operation: atom, session_id: String.t()}`

  - `[:condukt, :operation, :stop]` - Operation invocation finished
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module, operation: atom, session_id: String.t()}`

  - `[:condukt, :operation, :exception]` - Operation raised an exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module, operation: atom, session_id: String.t(), kind: atom, reason: term, stacktrace: list}`

  ### Anonymous Run Events

  Wrap a `Condukt.run/2` call (the runtime entry point that does not require
  an agent module). The inner agent and tool events still fire for free.

  - `[:condukt, :run, :start]` - Anonymous run started
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{structured?: boolean, input?: boolean, session_id: String.t()}`

  - `[:condukt, :run, :stop]` - Anonymous run finished
    - Measurements: `%{duration: integer}`
    - Metadata: `%{structured?: boolean, input?: boolean, session_id: String.t()}`

  - `[:condukt, :run, :exception]` - Anonymous run raised an exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{structured?: boolean, input?: boolean, session_id: String.t(), kind: atom, reason: term, stacktrace: list}`

  ## Example: Attaching Handlers

      :telemetry.attach_many(
        "my-agent-handler",
        [
          [:condukt, :agent, :start],
          [:condukt, :agent, :stop],
          [:condukt, :tool_call, :stop],
          [:condukt, :subagent, :start],
          [:condukt, :subagent, :stop],
          [:condukt, :secrets, :resolve],
          [:condukt, :secrets, :access]
        ],
        &MyApp.Telemetry.handle_event/4,
        nil
      )
  """

  @doc """
  Executes a function within a telemetry span.

  Emits start, stop, and exception events for the given event name.

  An optional `augment_stop` function receives the result of `fun` and returns
  a map of extra metadata to merge into the `:stop` event. Use it to attach
  result-derived fields (status, payload, …) that are only known once the
  wrapped work has finished.
  """
  def span(event, metadata, fun, augment_stop \\ fn _result -> %{} end)
      when is_atom(event) and is_map(metadata) and is_function(fun, 0) and is_function(augment_stop, 1) do
    event_prefix = [:condukt, event]
    start_time = System.monotonic_time()

    :telemetry.execute(
      event_prefix ++ [:start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()

      :telemetry.execute(
        event_prefix ++ [:stop],
        %{duration: System.monotonic_time() - start_time},
        Map.merge(metadata, augment_stop.(result))
      )

      result
    catch
      kind, reason ->
        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Emits a telemetry event.
  """
  def emit(event, measurements \\ %{}, metadata \\ %{})

  def emit(event, measurements, metadata) when is_atom(event) do
    emit([event], measurements, metadata)
  end

  def emit(event, measurements, metadata) when is_list(event) do
    :telemetry.execute([:condukt | event], measurements, metadata)
  end
end
