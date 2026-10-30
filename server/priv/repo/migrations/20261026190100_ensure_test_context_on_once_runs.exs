defmodule Tuist.Repo.Migrations.EnsureTestContextOnOnceRuns do
  use Ecto.Migration

  # Databases that recorded 20261025120000 for the runner_profiles migration
  # skipped the once_runs one that shared its version.
  def up do
    alter table(:once_runs) do
      # PostgreSQL 11+ stores constant defaults without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add_if_not_exists :test_context, :map, default: %{}, null: false
    end
  end

  def down, do: :ok
end
