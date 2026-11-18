defmodule Tuist.Repo.Migrations.AddOsVersionToRunnerProfiles do
  @moduledoc false
  use Ecto.Migration

  # Linux profiles pick an Ubuntu release, the way macOS profiles pick an
  # Xcode. Existing Linux profiles are pinned to the release they run
  # today (ubuntu-24.04 since #15368) rather than following the catalog
  # default, so a later default change never moves a customer's jobs onto
  # a newer OS without them choosing it. macOS rows keep NULL.
  def up do
    alter table(:runner_profiles) do
      add :os_version, :string, null: true
    end

    flush()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE runner_profiles
       SET os_version = 'ubuntu-24.04'
     WHERE platform = 'linux' AND os_version IS NULL
    """)
  end

  def down do
    alter table(:runner_profiles) do
      # Rollback only, after the application that reads the column.
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :os_version
    end
  end
end
