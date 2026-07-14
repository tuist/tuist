defmodule Tuist.Repo.Migrations.AddTokenLastFourToAccountTokens do
  use Ecto.Migration

  def change do
    alter table(:account_tokens) do
      add :token_last_four, :string
    end
  end
end
