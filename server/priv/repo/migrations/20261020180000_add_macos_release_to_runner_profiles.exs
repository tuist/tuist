defmodule Tuist.Repo.Migrations.AddMacosReleaseToRunnerProfiles do
  use Ecto.Migration

  def change do
    alter table(:runner_profiles) do
      # NULL on Linux profiles and on macOS profiles created before the column,
      # which run macOS 26 (Tahoe).
      add :macos_release, :string
    end
  end
end
