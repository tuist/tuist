defmodule Tuist.Kura.Reconciler do
  @moduledoc """
  Cleans up Kura deployments stranded in `:running` after a server crash
  or restart.

  `Tuist.Kura.Workers.RolloutWorker` is `max_attempts: 1`. When the
  worker's BEAM is killed mid-flight (SIGTERM during a rolling deploy,
  SIGKILL on OOM) Oban has no retry budget left — the job ends up
  `discarded`/`cancelled` and is never picked back up. The deployment
  row stays in `:running` forever, and the worker explicitly bails on
  pre-existing `:running` rows to avoid re-entrancy, so manual SQL is
  the only way out.

  The reconciler runs once on boot and walks every `:running` row. If
  the associated Oban job is in a terminal state — or gone — the
  deployment is marked `:failed` (and the parent server with it, to
  match how the worker reports rollout failures). Jobs still alive
  (`executing` on another node, `available`/`scheduled`/`retryable`
  pending pickup) are left untouched: the worker handles those itself.

  A deliberately conservative design: we never auto-resume a rollout.
  `rollout.sh` is idempotent, but the cluster-side state may be
  mid-helm-upgrade and an operator should look before re-triggering.
  """

  # `:temporary` so the supervisor logs and moves on if reconciliation
  # crashes — looping a broken reconciler would only churn alerts.
  use Task, restart: :temporary

  import Ecto.Query

  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Server
  alias Tuist.Repo

  require Logger

  @reason "deployment was interrupted by a server restart; re-trigger manually"
  @terminal_oban_states ~w(completed discarded cancelled)

  def start_link(_arg) do
    Task.start_link(__MODULE__, :reconcile, [])
  end

  def reconcile do
    query = from(d in Deployment, where: d.status == :running, preload: :kura_server)

    query
    |> Repo.all()
    |> Enum.each(&reconcile_deployment/1)

    :ok
  end

  defp reconcile_deployment(%Deployment{} = deployment) do
    case oban_job_state(deployment.oban_job_id) do
      :alive ->
        :ok

      :orphaned ->
        Logger.info("[Kura.Reconciler] failing orphaned deployment #{deployment.id}")
        {:ok, _} = Kura.mark_failed(deployment, @reason)
        maybe_fail_server(deployment.kura_server)
    end
  end

  defp oban_job_state(nil), do: :orphaned

  defp oban_job_state(job_id) do
    case Repo.get(Oban.Job, job_id) do
      nil -> :orphaned
      %Oban.Job{state: state} when state in @terminal_oban_states -> :orphaned
      %Oban.Job{} -> :alive
    end
  end

  defp maybe_fail_server(%Server{status: status} = server) when status in [:provisioning, :active, :failed] do
    {:ok, _} = Kura.fail_server(server)
    :ok
  end

  defp maybe_fail_server(_), do: :ok
end
