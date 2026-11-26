defmodule Tuist.IngestRepo.Migrations.AddIsCiToRemoteExecutionActions do
  @moduledoc """
  Whether the action's run ran on CI, copied at ingestion from the Struo run
  (`once_runs.is_ci`) its invocation ID names, so the Remote execution page
  can filter Struo runs by environment. Null when no such run was known:
  Bazel invocations, which the page filters through `bazel_invocations`, and
  rows written before this column.
  """
  use Ecto.Migration

  def change do
    alter table(:remote_execution_actions) do
      add :is_ci, :"Nullable(Bool)"
    end
  end
end
