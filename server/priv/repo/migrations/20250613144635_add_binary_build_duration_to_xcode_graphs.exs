defmodule Tuist.Repo.Migrations.AddBinaryBuildDurationToXcodeGraphs do
  use Ecto.Migration

  def up do
    alter table(:xcode_graphs) do
      add :binary_build_duration, :integer, null: true
    end
  end

  def down do
    # Table was dropped by later migration, nothing to rollback
    :ok
  end
end
