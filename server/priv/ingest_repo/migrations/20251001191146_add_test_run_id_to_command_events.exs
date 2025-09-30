defmodule Tuist.IngestRepo.Migrations.AddTestRunIdToCommandEvents do
  use Ecto.Migration

  def change do
    alter table(:command_events) do
      add :test_run_id, :"Nullable(UUID)"
    end
  end
end
