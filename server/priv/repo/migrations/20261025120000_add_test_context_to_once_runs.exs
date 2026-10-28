defmodule Tuist.Repo.Migrations.AddTestContextToOnceRuns do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:once_runs) do
      # PostgreSQL 11+ stores constant defaults without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :test_context, :map, default: %{}, null: false
    end
  end
end
