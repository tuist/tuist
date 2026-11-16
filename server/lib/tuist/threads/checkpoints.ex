defmodule Tuist.Threads.Checkpoints do
  @moduledoc """
  Encrypted per-turn snapshots. The worker must replace session_id with a fresh
  UUID at every attempt. Matching that ID and running status fences stale writes.
  Only protocol messages enter the snapshot, never client options or credentials.
  """

  import Ecto.Query

  alias Condukt.SessionStore.Snapshot
  alias Tuist.Repo
  alias Tuist.Threads.Agent
  alias Tuist.Threads.Run
  alias Tuist.Threads.ToolCall

  require Logger

  @handler_id "tuist-thread-checkpoints"

  def attach do
    :telemetry.attach(@handler_id, [:condukt, :llm_turn, :start], &__MODULE__.handle_event/4, nil)
  end

  def detach, do: :telemetry.detach(@handler_id)

  # Never let a persistence failure permanently detach the global handler or
  # leak protocol messages through exception/query logging.
  def handle_event(_event, _measurements, %{agent: Agent, session_id: id} = metadata, _config) when is_binary(id) do
    record(id, Map.get(metadata, :messages, []), Map.get(metadata, :turn))
  rescue
    _ -> Logger.warning("thread checkpoint failed: checkpoint_error")
  catch
    _, _ -> Logger.warning("thread checkpoint failed: checkpoint_exit")
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  def record(session_id, messages, _turn) when is_binary(session_id) and is_list(messages) do
    encoded = %{id: session_id, messages: messages} |> Snapshot.new() |> :erlang.term_to_binary()

    {:ok, _} =
      Repo.transaction(fn ->
        {_, ids} =
          Repo.update_all(
            from(run in Run, where: run.session_id == ^session_id and run.status == "running", select: run.id),
            [set: [checkpoint: encoded]],
            log: false
          )

        # Results may be replayed only once they are part of the same persisted
        # protocol snapshot. A crash between a tool and this checkpoint stops the
        # run rather than asking a model to regenerate the already-applied effect.
        Repo.update_all(
          from(call in ToolCall, where: call.run_id in ^ids and call.status == "completed"),
          [set: [checkpointed: true]],
          log: false
        )
      end)

    :ok
  end

  def load(%{checkpoint: nil}), do: :none

  def load(%{checkpoint: encoded}) when is_binary(encoded) do
    with {:ok, term} <- decode(encoded),
         {:ok, %Snapshot{messages: [_ | _]} = snapshot} <- Snapshot.migrate(term) do
      {:ok, snapshot}
    else
      _ -> {:error, :checkpoint_unavailable}
    end
  end

  defp decode(encoded) do
    {:ok, :erlang.binary_to_term(encoded, [:safe])}
  rescue
    ArgumentError -> :error
  end
end
