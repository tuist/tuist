defmodule Tuist.Repo.Migrations.RequireAccountTokenName do
  use Ecto.Migration

  def change do
    # Backfill legacy tokens that predate the `name` column (mostly `account:registry:read`
    # tokens created by `tuist registry login`) with a generated, per-row-unique name
    # derived from the token id, so the NOT NULL constraint below holds. New tokens always
    # get a name — every creation path goes through a changeset that requires it.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "UPDATE account_tokens SET name = 'token-' || right(replace(id::text, '-', ''), 12) WHERE name IS NULL",
      "SELECT 1"
    )

    alter table(:account_tokens) do
      # excellent_migrations:safety-assured-for-next-line not_null_added column_type_changed
      modify :name, :string, null: false, from: {:string, null: true}
    end
  end
end
