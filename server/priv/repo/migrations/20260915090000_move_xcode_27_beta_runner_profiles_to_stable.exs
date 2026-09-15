defmodule Tuist.Repo.Migrations.MoveXcode27BetaRunnerProfilesToStable do
  use Ecto.Migration

  # The `27.0-beta` channel is no longer in the macOS Xcode catalog, so a
  # profile still naming it would resolve to a RunnerPool that doesn't
  # render. `27.0` is the stable release of the same Xcode.

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE runner_profiles
       SET xcode_version = '27.0', updated_at = NOW()
     WHERE xcode_version = '27.0-beta'
    """)
  end

  def down, do: :ok
end
