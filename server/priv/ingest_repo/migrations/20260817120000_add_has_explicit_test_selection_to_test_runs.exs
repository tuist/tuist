defmodule Tuist.IngestRepo.Migrations.AddHasExplicitTestSelectionToTestRuns do
  @moduledoc """
  Records whether a run was restricted to a caller-supplied set of tests, so shard planning can tell
  a run that executed a module's whole suite set from one that was asked for a handful of them. A
  restriction Tuist itself applies for a shard is not one of these: the flag covers only a selection
  the caller asked for.
  """

  use Ecto.Migration

  def change do
    alter table(:test_runs) do
      add :has_explicit_test_selection, :boolean, default: false
    end
  end
end
