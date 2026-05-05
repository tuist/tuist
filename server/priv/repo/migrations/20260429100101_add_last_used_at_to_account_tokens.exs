defmodule Tuist.Repo.Migrations.AddLastUsedAtToAccountTokens do
  use Ecto.Migration

  def change do
    alter table(:account_tokens) do
      add :last_used_at, :timestamptz
    end
  end
end
