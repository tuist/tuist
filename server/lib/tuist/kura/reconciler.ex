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

  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Server
  alias Tuist.Repo

  require Logger

  @reason "deployment was interrupted by a server restart; re-trigger manually"
  @terminal_oban_states ~w(completed discarded cancelled)
  @server_statuses_to_fail [:provisioning, :active, :failed]

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
    deployments =
      Deployment
      |> where([d], d.status == :running)
      |> preload(:kura_server)
      |> Repo.all()

    job_states = oban_job_states(deployments)

    deployments
    |> Enum.reject(&(Map.get(job_states, &1.oban_job_id, :orphaned) == :alive))
    |> reconcile_orphaned_deployments()

    :ok
  end

  defp reconcile_orphaned_deployments([]), do: :ok

  defp reconcile_orphaned_deployments(deployments) do
    {already_activated, failed} = Enum.split_with(deployments, &deployment_already_activated?/1)

    mark_deployments_succeeded(already_activated)
    mark_deployments_failed(failed)
    fail_servers_for(failed)

    :ok
  end

  defp deployment_already_activated?(%Deployment{
         image_tag: image_tag,
         kura_server: %Server{status: :active, current_image_tag: current_image_tag}
       }) do
    current_image_tag == image_tag
  end

  defp deployment_already_activated?(_), do: false

  defp oban_job_states(deployments) do
    # Intentional cross-tenant lookup: the reconciler runs as a
    # background job to detect orphaned deployments after a web-process
    # crash, and Oban jobs aren't account-scoped to begin with. The
    # deployment rows carrying job_ids are already account-owned, so
    # there's no leak: we only act on rows this job already loaded.
    job_ids =
      deployments
      |> Enum.map(& &1.oban_job_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Oban.Job
    |> where([j], j.id in ^job_ids)
    |> select([j], {j.id, j.state})
    |> Repo.all()
    |> Map.new(fn
      {id, state} when state in @terminal_oban_states -> {id, :orphaned}
      {id, _state} -> {id, :alive}
    end)
  end

  defp mark_deployments_succeeded([]), do: :ok

  defp mark_deployments_succeeded(deployments) do
    Enum.each(deployments, fn deployment ->
      Logger.info("[Kura.Reconciler] marking already-activated orphaned deployment #{deployment.id} as succeeded")
    end)

    update_deployments(deployments, %{
      status: :succeeded,
      error_message: nil,
      finished_at: now_truncated()
    })
  end

  defp mark_deployments_failed([]), do: :ok

  defp mark_deployments_failed(deployments) do
    Enum.each(deployments, fn deployment ->
      Logger.info("[Kura.Reconciler] failing orphaned deployment #{deployment.id}")
    end)

    update_deployments(deployments, %{
      status: :failed,
      error_message: @reason,
      finished_at: now_truncated()
    })
  end

  defp update_deployments(deployments, attrs) do
    ids = Enum.map(deployments, & &1.id)
    timestamp = now_truncated()

    Deployment
    |> where([d], d.id in ^ids and d.status == :running)
    |> Repo.update_all(set: attrs |> Map.put(:updated_at, timestamp) |> Map.to_list())

    :ok
  end

  defp fail_servers_for(deployments) do
    server_ids =
      deployments
      |> Enum.flat_map(fn
        %Deployment{kura_server: %Server{id: id, status: status}} when status in @server_statuses_to_fail -> [id]
        _deployment -> []
      end)
      |> Enum.uniq()

    case server_ids do
      [] ->
        :ok

      server_ids ->
        timestamp = now_truncated()

        Server
        |> where([s], s.id in ^server_ids and s.status in ^@server_statuses_to_fail)
        |> Repo.update_all(set: [status: :failed, updated_at: timestamp])

        :ok
    end
  end

  defp now_truncated, do: DateTime.truncate(DateTime.utc_now(), :second)
end
