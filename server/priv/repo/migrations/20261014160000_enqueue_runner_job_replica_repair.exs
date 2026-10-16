defmodule Tuist.Repo.Migrations.EnqueueRunnerJobReplicaRepair do
  @moduledoc """
  Queued a one-off repair of the ClickHouse `runner_jobs` rows left
  non-terminal while their Postgres lifecycle row was terminal. It ran in
  production, and the worker it queued has since been removed, so this is
  now a no-op: a database migrating past it later would otherwise queue a
  job for a worker that no longer exists.
  """
  use Ecto.Migration

  def up, do: :ok

  def down, do: :ok
end
