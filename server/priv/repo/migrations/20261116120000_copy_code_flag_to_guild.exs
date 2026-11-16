defmodule Tuist.Repo.Migrations.CopyCodeFlagToGuild do
  @moduledoc """
  The `:code` feature flag is now `:guild` (`Tuist.FeatureFlags.guild_enabled?/1`).
  Copies every `code` gate to `guild` so users and organizations keep access.

  The `code` rows stay: replicas still running the previous release read them
  during a rolling deploy, and rolling back the code needs no data change.
  """
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def up do
    execute("""
    INSERT INTO feature_flags (id, flag_name, gate_type, target, enabled)
    SELECT gen_random_uuid(), 'guild', gate_type, target, enabled
    FROM feature_flags
    WHERE flag_name = 'code'
    ON CONFLICT (flag_name, gate_type, target) DO NOTHING
    """)
  end

  # `guild` gates may have been changed since; the `code` rows were never removed.
  def down, do: :ok
end
