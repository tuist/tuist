defmodule Tuist.Repo.Migrations.CopyGuildFlagToLuft do
  @moduledoc """
  The `:guild` feature flag is now `:luft` (`Tuist.FeatureFlags.luft_enabled?/1`).
  Copies every `guild` gate to `luft` so users and organizations keep access.

  The `guild` rows stay: replicas still running the previous release read them
  during a rolling deploy, and rolling back the code needs no data change.
  """
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def up do
    execute("""
    INSERT INTO feature_flags (id, flag_name, gate_type, target, enabled)
    SELECT gen_random_uuid(), 'luft', gate_type, target, enabled
    FROM feature_flags
    WHERE flag_name = 'guild'
    ON CONFLICT (flag_name, gate_type, target) DO NOTHING
    """)
  end

  # `luft` gates may have been changed since; the `guild` rows were never removed.
  def down, do: :ok
end
