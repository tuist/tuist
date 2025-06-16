defmodule Tuist.Repo.Migrations.AddBinaryBuildDurationToXcodeGraphs do
  use Ecto.Migration

  def change do
    alter table(:xcode_graphs) do
      add :binary_build_duration, :integer, null: true
    end
  end
end
