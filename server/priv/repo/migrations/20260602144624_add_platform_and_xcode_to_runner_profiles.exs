defmodule Tuist.Repo.Migrations.AddPlatformAndXcodeToRunnerProfiles do
  use Ecto.Migration

  # macOS Runner Profiles. The shape dimension differs by platform:
  # Linux profiles vary by `(vcpus, memory_gb)`; macOS profiles
  # additionally pin an Xcode version (the runtime that produces /
  # consumes .xcresult bundles, dispatched to a per-Xcode pool in
  # the chart). `platform` discriminates; `xcode_version` is
  # required on macOS and stays NULL on Linux.
  #
  # Existing rows are all Linux today (the schema was Linux-only
  # since `create_runner_profiles` landed). Backfill them in the
  # same migration so the NOT NULL constraint can apply.
  def change do
    alter table(:runner_profiles) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :platform, :string, null: false, default: "linux"

      add :xcode_version, :string, null: true
    end
  end
end
