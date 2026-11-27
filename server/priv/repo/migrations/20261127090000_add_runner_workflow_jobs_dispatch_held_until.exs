defmodule Tuist.Repo.Migrations.AddRunnerWorkflowJobsDispatchHeldUntil do
  use Ecto.Migration

  # Set on a queued job whose runner credential cannot be minted until the
  # customer acts (the GitHub App lacks a permission, is uninstalled, the
  # repository runner endpoint is missing). Dispatch and the autoscaler's
  # queue counts skip the row until then, so it neither burns a runner per
  # retry nor keeps a pool scaled for work no runner can take. Nullable and
  # without a default, so adding it is a catalog-only change.
  def change do
    alter table(:runner_workflow_jobs) do
      add :dispatch_held_until, :timestamptz
    end
  end
end
