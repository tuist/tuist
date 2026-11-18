defmodule Tuist.Repo.Migrations.AddLegacyTokenHashColumns do
  @moduledoc """
  Legacy user and project tokens were stored and compared in plaintext, so
  read access to the database handed out working credentials. Lookups now go
  through a SHA-256 digest (`token_hash`), and `legacy_token_last_used_at`
  shows which ones are still in use before they are retired. `token` stays,
  nullable, until every replica runs the hashed lookup;
  `Tuist.Release.clear_plaintext_legacy_tokens/0` then hashes rows written
  meanwhile and clears it.
  """
  use Ecto.Migration

  def change do
    for table <- [:users, :projects] do
      alter table(table) do
        add :token_hash, :binary
        add :legacy_token_last_used_at, :timestamptz
        # excellent_migrations:safety-assured-for-next-line column_type_changed
        modify :token, :string, size: 100, null: true, from: {:string, size: 100, null: false}
      end
    end
  end
end
