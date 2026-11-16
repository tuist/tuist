defmodule Tuist.Repo.Migrations.BackfillLegacyTokenHashes do
  use Ecto.Migration

  def up do
    for table <- ["users", "projects"] do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("""
      UPDATE #{table} SET token_hash = sha256(convert_to(token, 'UTF8'))
      WHERE token IS NOT NULL AND token_hash IS NULL
      """)
    end
  end

  def down, do: :ok
end
