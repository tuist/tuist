defmodule Tuist.Repo.Migrations.MigrateTestColumnsFromCommandEvents do
  use Ecto.Migration

  def change do
    # We could rename the columsn here because:
    # - We had not released an on-premise image including these changes
    # - We had no business logic storing data into these columns
    rename table(:command_events), :tested_targets, to: :test_targets
    rename table(:command_events), :local_tested_target_hits, to: :local_test_target_hits
    rename table(:command_events), :remote_tested_target_hits, to: :remote_test_target_hits
  end
end
