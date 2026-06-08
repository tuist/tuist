defmodule Tuist.Repo.Migrations.RemoveRunnerMaxConcurrentFromAccounts do
  use Ecto.Migration

  # Runner availability is gated solely by the `:runners` feature flag
  # (`Tuist.FeatureFlags.runners_enabled?/1`) now — the per-account
  # concurrency cap is gone, so its column drops with it.
  def up do
    alter table(:accounts) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove_if_exists :runner_max_concurrent, :integer
    end
  end

  def down do
    alter table(:accounts) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :runner_max_concurrent, :integer, null: false, default: 0
    end
  end
end
