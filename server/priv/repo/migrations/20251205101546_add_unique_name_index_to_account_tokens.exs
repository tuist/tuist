defmodule Tuist.Repo.Migrations.AddUniqueNameIndexToAccountTokens do
  use Ecto.Migration

  def change do
    create unique_index(:account_tokens, [:account_id, :name])
  end
end
