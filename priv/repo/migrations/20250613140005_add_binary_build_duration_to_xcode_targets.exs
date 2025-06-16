defmodule Tuist.Repo.Migrations.AddBinaryBuildDurationToXcodeTargets do
  use Ecto.Migration

  def change do
    alter table(:xcode_targets) do
      add :binary_build_duration, :integer, null: true
    end
  end
end
