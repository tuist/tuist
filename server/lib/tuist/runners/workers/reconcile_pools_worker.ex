defmodule Tuist.Runners.Workers.ReconcilePoolsWorker do
  @moduledoc """
  Periodic Oban job that walks every enabled Orchard worker pool and invokes
  the reconciler. Also accepts an `"orchard_worker_pool_id"` arg for targeted
  reconciliation triggered by UI actions (scale up/down).

  Once the app runs inside a Kubernetes cluster with a Bonny controller, the
  cron can be removed -- the same reconciler will be called from the
  controller's reconcile step.
  """

  use Oban.Worker, queue: :runners, max_attempts: 3

  alias Tuist.Runners.Reconciler

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"orchard_worker_pool_id" => pool_id}}) do
    case Reconciler.reconcile(pool_id) do
      {:ok, result} ->
        Logger.info("Reconciled pool #{pool_id}: #{inspect(result)}")
        :ok

      {:error, reason} = error ->
        Logger.error("Reconciliation of pool #{pool_id} failed: #{inspect(reason)}")
        error
    end
  end

  def perform(%Oban.Job{args: _}) do
    results = Reconciler.reconcile_all()
    Logger.debug("Reconciled #{length(results)} pools")
    :ok
  end
end
