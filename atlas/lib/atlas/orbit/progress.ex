defmodule Atlas.Orbit.Progress do
  @moduledoc """
  Payload-free Condukt compaction activity for the authorized Phoenix snapshot.
  Completion notices explain actual pruning without deleting thread history.
  """

  import Ecto.Query

  alias Atlas.Orbit
  alias Atlas.Orbit.Agent
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Repo

  require Logger

  @handler_id "atlas-orbit-compaction"

  def attach do
    :telemetry.attach_many(
      @handler_id,
      [[:condukt, :compact, :start], [:condukt, :compact, :stop]],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event(
        [:condukt, :compact, phase],
        _measurements,
        %{agent: Agent, session_id: session_id} = metadata,
        _config
      ) do
    case Repo.one(from run in Run, where: run.session_id == ^session_id and run.status == "running") do
      nil -> :ok
      run -> record_activity(run, phase, metadata[:changed] == true)
    end
  rescue
    _exception -> Logger.warning("orbit activity update failed: progress_error")
  catch
    _kind, _reason -> Logger.warning("orbit activity update failed: progress_exit")
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  defp record_activity(run, phase, changed?) do
    result =
      Runs.with_attempt(run.id, run.resume_count, fn thread, current ->
        if is_nil(current.cancel_requested_at) and current.session_id == run.session_id do
          activity = if phase == :start, do: "compacting"
          current |> Ecto.Changeset.change(activity: activity) |> Repo.update!()

          if phase == :stop and changed? do
            Orbit.append!(thread, %{
              kind: "system",
              run_id: current.id,
              body: "Context compacted. Older tool results were shortened; thread history is unchanged."
            })
          end

          thread.id
        end
      end)

    case result do
      {:ok, id} when is_binary(id) -> Orbit.notify_changed(id)
      _ -> :ok
    end
  end

  def status(%Run{status: "running", activity: "compacting"}), do: "compacting"
  def status(%Run{status: status}), do: status
end
