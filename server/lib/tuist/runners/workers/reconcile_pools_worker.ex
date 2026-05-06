defmodule Tuist.Runners.Workers.ReconcilePoolsWorker do
  @moduledoc """
  Oban cron entry that runs `Tuist.Runners.Reconciler.reconcile/0`
  every minute.

  Single-tenant per BEAM cluster (the cron's `unique` option
  prevents duplicate jobs from queuing if the previous tick is
  still running). Idempotent — observed state lives in the k8s API
  server + Postgres; the worker just emits Pod-creates to close
  the gap.
  """

  use Oban.Worker, queue: :default, unique: [period: 60]

  alias Tuist.Runners.Reconciler

  @impl Oban.Worker
  def perform(_job) do
    Reconciler.reconcile()
    :ok
  end
end
