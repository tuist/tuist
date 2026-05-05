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

  The reconciler runs periodically through Oban Cron and walks every
  `:running` row. If the associated Oban job is in a terminal state —
  or gone — the deployment is marked `:failed` (and the parent server
  with it, to match how the worker reports rollout failures). Jobs
  still alive (`executing` on another node, `available`/`scheduled`/
  `retryable` pending pickup) are left untouched: the worker handles
  those itself.

  A deliberately conservative design: we never auto-resume a rollout.
  `rollout.sh` is idempotent, but the cluster-side state may be
  mid-helm-upgrade and an operator should look before re-triggering.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Server
  alias Tuist.Repo

  require Logger

  @reason "deployment was interrupted by a server restart; re-trigger manually"
  @terminal_oban_states ~w(completed discarded cancelled)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    reconcile()
  end

  def reconcile do
    # Intentional cross-tenant scan: this is a system-level recovery job
    # (Oban Cron) detecting deployments stranded after a server restart.
    # It only ever transitions a `:running` row to `:failed`, never reads
    # back to a tenant-facing surface, so there's no leak path; account
    # isolation is enforced at the writer (Tuist.Kura.mark_failed/2).
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
    # Intentional cross-tenant lookup: the reconciler runs as a
    # background job to detect orphaned deployments after a web-process
    # crash, and Oban jobs aren't account-scoped to begin with. The
    # deployment row carrying job_id is already account-owned, so
    # there's no leak: we only act on rows the caller already loaded.
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
