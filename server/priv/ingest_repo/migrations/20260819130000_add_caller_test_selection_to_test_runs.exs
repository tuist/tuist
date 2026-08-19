defmodule Tuist.IngestRepo.Migrations.AddCallerTestSelectionToTestRuns do
  @moduledoc """
  Records the tests the caller asked a run to include or exclude. Three parties add `-only-testing`
  and `-skip-testing` to the same invocation: the caller, the shard Tuist is executing, and the
  quarantine and selective-testing filters Tuist applies. Only the caller's is recorded here, since
  the other two are already known from the shard plan and the project's quarantine state.

  Shard planning reads a module's suites from past runs, and a run told to run only a couple of them
  executed what it was given rather than what the module holds.
  """

  use Ecto.Migration

  def change do
    alter table(:test_runs) do
      add :only_test_identifiers, {:array, :string}, default: fragment("[]")
      add :skip_test_identifiers, {:array, :string}, default: fragment("[]")
    end
  end
end
