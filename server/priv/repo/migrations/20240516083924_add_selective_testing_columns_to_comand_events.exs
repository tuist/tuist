defmodule Tuist.Repo.Migrations.AddSelectiveTestingColumnsToComandEvents do
  use Ecto.Migration

  def change do
    alter table(:command_events) do
      add :tested_targets, {:array, :string}
      add :local_tested_target_hits, {:array, :string}
      add :remote_tested_target_hits, {:array, :string}
    end
  end
end
