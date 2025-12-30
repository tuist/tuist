defmodule Tuist.Repo.Migrations.RenameTokensToGuardianTokens do
  use Ecto.Migration

  def change do
    # excellent_migrations:safety-assured-for-next-line table_renamed
    rename table(:tokens), to: table(:guardian_tokens)
  end
end
