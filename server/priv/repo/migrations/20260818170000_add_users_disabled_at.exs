defmodule Tuist.Repo.Migrations.AddUsersDisabledAt do
  use Ecto.Migration

  def change do
    # Nullable with no default, so PostgreSQL records it in table metadata
    # without rewriting existing rows.
    alter table(:users) do
      add :disabled_at, :timestamptz
    end
  end
end
