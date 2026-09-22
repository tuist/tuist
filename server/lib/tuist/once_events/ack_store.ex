defmodule Tuist.OnceEvents.AckStore do
  @moduledoc """
  In-memory tracker for per-run durable acknowledgement state.

  Keyed by `{project_id, run_id}`. The run id is picked by the client, so
  keying on it alone would let one project observe (or reset) another
  project's sequence state simply by reusing the same string. Holds
  `acked_seq`, the highest contiguous sequence durably projected, so
  `GetRunAck` can answer reconnecting clients without a Postgres
  round-trip. Loss on restart is acceptable: the client re-polls
  `GetRunAck`, gets `acked_seq = 0`, and the projector's
  `ON CONFLICT DO NOTHING` deduplicates resent writes.
  """
  use GenServer

  @table :once_events_ack_store

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, {:read_concurrency, true}, {:write_concurrency, true}])
    {:ok, nil}
  end

  @doc """
  Record that we projected events up to `acked_seq` for a run.

  Monotonic: a late or out-of-order batch never walks the high-water mark
  backwards, because the client treats a regressing `expected_next_seq` as
  a fatal protocol violation.
  """
  def observe(project_id, run_id, acked_seq) when is_binary(run_id) and is_integer(acked_seq) do
    key = key(project_id, run_id)

    if acked_seq > acked_seq(project_id, run_id) do
      :ets.insert(@table, {key, acked_seq})
    end

    :ok
  end

  @doc """
  Read the highest contiguous acked sequence for a run. Zero when never seen.
  """
  def acked_seq(project_id, run_id) when is_binary(run_id) do
    key = key(project_id, run_id)

    case :ets.lookup(@table, key) do
      [{^key, seq}] -> seq
      _ -> 0
    end
  end

  defp key(project_id, run_id), do: {to_string(project_id), run_id}
end
