defmodule Condukt.Compactor do
  @moduledoc """
  Behaviour for compacting a session's conversation history.

  Long-running agents accumulate messages that grow past the model's context
  window. A compactor receives the current message list and returns a shorter
  one — by dropping old turns, eliding large tool results, or replacing a
  prefix with a summary.

  Compactors are pluggable just like `Condukt.SessionStore`. Pass one to
  `start_link/1` and Condukt will apply it before every native model request
  (including tool iterations) and after run completion before persistence.
  Compactors should be idempotent when no further pruning is needed.

      MyApp.Agent.start_link(
        compactor: Condukt.Compactor.Sliding
      )

      MyApp.Agent.start_link(
        compactor: {Condukt.Compactor.Sliding, keep: 30}
      )

  Compaction can also be triggered manually with `Condukt.compact/1`.

  ## Background compaction

  Native sessions can opt into `background_compaction: true` or a keyword
  policy alongside `:compactor`. The callback runs in a supervised task on
  an older prefix while recent messages and new activity remain unchanged.
  Its replacement is adopted only between inference requests or when idle.
  Unlike synchronous mode, the callback receives only the selected prefix.

  Defaults start work at 65% of the model's context window and wait at 90%.
  If the pending result fails or is insufficient, the loop tries one fresh
  compaction before returning `{:error, {:compaction_failed, reason}}`.
  See the [Compaction guide](compaction.md#background-compaction) for options,
  token estimates, cancellation, and the manual compaction contract.

  ## Built-in compactors

  - `Condukt.Compactor.Sliding` — keeps the most recent N messages.
  - `Condukt.Compactor.ToolResultPrune` — replaces old tool result payloads
    with a placeholder, preserving the surrounding reasoning structure.

  ## Implementing a compactor

      defmodule MyApp.MyCompactor do
        @behaviour Condukt.Compactor

        @impl true
        def compact(messages, _opts) do
          {:ok, Enum.take(messages, -10)}
        end
      end

  ## Telemetry

  Each compaction emits `[:condukt, :compact, :start]` and
  `[:condukt, :compact, :stop]`. Stop measurements include `:duration`,
  `:before`/`:after` message counts and `:before_bytes`/`:after_bytes` external-term
  sizes. Metadata identifies `:agent` and `:session_id`; stop also includes
  `:status` and `:changed`. No message payload is included.
  """

  alias Condukt.Message

  @callback compact([Message.t()], keyword()) :: {:ok, [Message.t()]} | {:error, term()}

  @doc """
  Dispatches `compact/2` to the configured compactor module or `{module, opts}`
  tuple. Default options are merged underneath the tuple's options.
  """
  def compact(compactor, messages, default_opts \\ [])

  def compact({module, opts}, messages, default_opts) do
    module.compact(messages, Keyword.merge(default_opts, opts))
  end

  def compact(module, messages, default_opts) when is_atom(module) do
    module.compact(messages, default_opts)
  end
end
