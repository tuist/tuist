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
    :telemetry.attach(
      @handler_id,
      [:condukt, :compact, :stop],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  # ToolResultPrune checks before every turn, even when nothing needs pruning.
  # It does no model work: publishing each start invents a repeated busy phase
  # and blocks the model loop on two database writes for every no-op check.
  def handle_event(
        [:condukt, :compact, :stop],
        _measurements,
        %{agent: Agent, session_id: session_id} = metadata,
        _config
      ) do
    changed? = metadata[:changed] == true

    case Repo.one(from run in Run, where: run.session_id == ^session_id and run.status == "running") do
      nil -> :ok
      %Run{activity: nil} when not changed? -> :ok
      run -> record_activity(run, changed?)
    end
  rescue
    _exception -> Logger.warning("orbit activity update failed: progress_error")
  catch
    _kind, _reason -> Logger.warning("orbit activity update failed: progress_exit")
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  defp record_activity(run, changed?) do
    result =
      Runs.with_attempt(run.id, run.resume_count, fn thread, current ->
        if is_nil(current.cancel_requested_at) and current.session_id == run.session_id do
          current |> Ecto.Changeset.change(activity: nil) |> Repo.update!()

          if changed? do
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
