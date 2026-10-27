defmodule Atlas.Orbit.Checkpoints do
  @moduledoc """
  Per-turn Condukt snapshots for thread runs.

  Condukt persists session snapshots only when a run completes, so its session
  store alone cannot resume a run interrupted mid-way. Condukt does report the
  exact protocol messages handed to the model at the start of every turn
  (`[:condukt, :llm_turn, :start]`). This recorder stores those messages as a
  versioned `Condukt.SessionStore.Snapshot` on the run, encrypted at rest, and
  only for the attempt that owns the run: the write is conditional on the
  attempt's Condukt session id while the run is `running`.

  The snapshot is a cache beside the durable thread log, not the record
  of what happened. It is cleared when a run finishes, readable only through
  the run row, and decoded with `binary_to_term(..., [:safe])` followed by
  Condukt's own snapshot migration. Anything that fails to decode falls back to
  the transcript replay described in `Atlas.Orbit.Runs`.
  """

  import Ecto.Query

  alias Atlas.Orbit.Agent
  alias Atlas.Orbit.Run
  alias Atlas.Repo
  alias Condukt.SessionStore.Snapshot

  require Logger

  @handler_id "atlas-thread-checkpoints"

  def attach do
    :telemetry.attach(@handler_id, [:condukt, :llm_turn, :start], &__MODULE__.handle_event/4, nil)
  end

  def detach, do: :telemetry.detach(@handler_id)

  # `:telemetry` permanently detaches a handler the first time it raises, which
  # would silently stop checkpointing for the rest of the node. A failed
  # checkpoint only weakens resumption, so failures are swallowed. Only a fixed
  # category is logged: exception messages and query parameters can carry the
  # thread's protocol messages.
  def handle_event(_event, _measurements, %{agent: Agent, session_id: session_id} = metadata, _config)
      when is_binary(session_id) do
    record(session_id, Map.get(metadata, :messages, []), Map.get(metadata, :turn))
  rescue
    _exception ->
      Logger.warning("thread checkpoint failed: checkpoint_error")
      :ok
  catch
    _kind, _reason ->
      Logger.warning("thread checkpoint failed: checkpoint_exit")
      :ok
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  @doc false
  def record(session_id, messages, turn) when is_list(messages) do
    encoded =
      %{id: session_id, messages: messages}
      |> Snapshot.new()
      |> :erlang.term_to_binary()

    Repo.update_all(
      from(run in Run, where: run.session_id == ^session_id and run.status == "running"),
      set: [checkpoint: encoded, checkpoint_turn: turn]
    )

    :ok
  end

  @doc "The run's latest snapshot, or `:none` when it has none or it cannot be decoded."
  def load(%Run{checkpoint: nil}), do: :none

  def load(%Run{checkpoint: encoded}) when is_binary(encoded) do
    with {:ok, term} <- decode(encoded),
         {:ok, %Snapshot{messages: [_ | _]} = snapshot} <- Snapshot.migrate(term) do
      {:ok, snapshot}
    else
      _ -> :none
    end
  end

  # `:safe` refuses to create atoms or decode functions; anything else invalid
  # raises ArgumentError, which is the only way the BEAM reports it.
  defp decode(encoded) do
    {:ok, :erlang.binary_to_term(encoded, [:safe])}
  rescue
    ArgumentError -> :error
  end
end
