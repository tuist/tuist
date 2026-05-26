defmodule Tuist.Runners.RunnerSessions do
  @moduledoc """
  Open/close the per-Pod billing record in Postgres. Called from
  the two points where the Tuist server knows a Pod is about to
  start or end its life: claim-win
  (`Tuist.Runners.Jobs.record_claimed/3`) and completion-webhook
  (`Tuist.Runners.Jobs.complete/2`).

  These functions are fire-and-forget for billing — they don't
  block the hot dispatch path and they swallow Postgres errors
  with a warning rather than failing the caller. A missed
  session insert means we under-bill that customer for one Pod;
  a hard failure here would mean a missed claim or a missed
  completion webhook, which is much worse. Track failures via
  the warning log line; the operator should be alerted on
  sustained noise.
  """
  require Logger

  alias Tuist.Repo
  alias Tuist.Runners.RunnerSession

  import Ecto.Query

  @doc """
  Open a billing session at claim-win. The `started_at` lands at
  the claim time — within a few hundred ms of the controller
  actually creating the Pod, which is the closest server-side
  signal we have until the controller starts reporting Pod
  timestamps directly.
  """
  def open(%{
          workflow_job_id: workflow_job_id,
          account_id: account_id,
          fleet_name: fleet_name,
          pod_name: pod_name,
          started_at: started_at
        } = attrs) do
    now = DateTime.utc_now()

    attrs = %{
      workflow_job_id: workflow_job_id,
      account_id: account_id,
      fleet_name: fleet_name,
      pod_name: pod_name,
      repo: Map.get(attrs, :repo, ""),
      workflow_name: Map.get(attrs, :workflow_name, ""),
      started_at: started_at,
      inserted_at: DateTime.truncate(now, :second),
      updated_at: DateTime.truncate(now, :second)
    }

    case Repo.insert(struct(RunnerSession, attrs)) do
      {:ok, session} ->
        {:ok, session}

      {:error, changeset} ->
        Logger.warning("runners: failed to open billing session",
          workflow_job_id: workflow_job_id,
          account_id: account_id,
          changeset_errors: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  @doc """
  Close the most recent open session for `workflow_job_id`. The
  re-claim path (`Jobs.record_queued/1`) can produce multiple
  rows per workflow_job_id over time; only the latest open one
  represents the Pod that's about to be torn down.

  `ended_at` is the completion-webhook arrival time. The
  controller will react to the same event by deleting the Pod a
  few seconds later, so this slightly under-bills the customer
  — fine for now, will tighten when the controller reports
  Pod-delete directly.

  Returns `{:ok, session}` on success, `{:ok, :no_open_session}`
  when no open row exists (e.g. a completion webhook landing
  for a workflow_job that never claimed — duplicate delivery,
  out-of-order, or seeded data).
  """
  def close(workflow_job_id, ended_at) when is_integer(workflow_job_id) do
    case latest_open(workflow_job_id) do
      nil ->
        {:ok, :no_open_session}

      %RunnerSession{} = session ->
        session
        |> Ecto.Changeset.cast(
          %{ended_at: ended_at, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)},
          [:ended_at, :updated_at]
        )
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            {:ok, updated}

          {:error, changeset} ->
            Logger.warning("runners: failed to close billing session",
              workflow_job_id: workflow_job_id,
              changeset_errors: inspect(changeset.errors)
            )

            {:error, changeset}
        end
    end
  end

  defp latest_open(workflow_job_id) do
    RunnerSession
    |> where([s], s.workflow_job_id == ^workflow_job_id and is_nil(s.ended_at))
    |> order_by([s], desc: s.started_at)
    |> limit(1)
    |> Repo.one()
  end
end
