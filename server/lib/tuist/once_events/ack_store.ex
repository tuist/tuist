defmodule Tuist.OnceEvents.AckStore do
  @moduledoc """
  In-memory tracker for per-run durable acknowledgement state.

  Keyed by `run_id`. Holds `acked_seq` (highest contiguous sequence
  durably projected) and `expected_next_seq` so `GetRunAck` can answer
  reconnecting clients without a Postgres round-trip. Loss on restart is
  acceptable: the client re-polls `GetRunAck`, gets `acked_seq = 0`, and
  the projector's `ON CONFLICT DO NOTHING` deduplicates resent writes.
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
  """
  def observe(run_id, acked_seq) when is_binary(run_id) and is_integer(acked_seq) do
    :ets.insert(@table, {run_id, acked_seq})
    :ok
  end

  @doc """
  Read the highest contiguous acked sequence for a run. Zero when never seen.
  """
  def acked_seq(run_id) when is_binary(run_id) do
    case :ets.lookup(@table, run_id) do
      [{^run_id, seq}] -> seq
      _ -> 0
    end
  end

  def expected_next_seq(run_id), do: acked_seq(run_id) + 1
end
