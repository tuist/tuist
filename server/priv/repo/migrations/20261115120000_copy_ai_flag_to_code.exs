defmodule Tuist.Repo.Migrations.CopyAiFlagToCode do
  @moduledoc """
  The `:ai` feature flag is now `:code` (`Tuist.FeatureFlags.code_enabled?/1`).
  Copies every `ai` gate to `code` so users and organizations keep access.

  The `ai` rows stay: replicas still running the previous release read them
  during a rolling deploy, and rolling back the code needs no data change.
  """
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def up do
    execute("""
    INSERT INTO feature_flags (id, flag_name, gate_type, target, enabled)
    SELECT gen_random_uuid(), 'code', gate_type, target, enabled
    FROM feature_flags
    WHERE flag_name = 'ai'
    ON CONFLICT (flag_name, gate_type, target) DO NOTHING
    """)
  end

  # `code` gates may have been changed since; the `ai` rows were never removed.
  def down, do: :ok
end
