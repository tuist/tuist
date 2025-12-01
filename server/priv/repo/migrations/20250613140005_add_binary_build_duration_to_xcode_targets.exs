defmodule Tuist.Repo.Migrations.AddBinaryBuildDurationToXcodeTargets do
  use Ecto.Migration

  def up do
    alter table(:xcode_targets) do
      add :binary_build_duration, :integer, null: true
    end
  end

  def down do
    # Table was dropped by later migration, nothing to rollback
    :ok
  end
end
