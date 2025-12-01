defmodule Tuist.Repo.Migrations.IncreaseOauthTokensStateLength do
  use Ecto.Migration

  def up do
    alter table(:oauth_tokens) do
      modify :state, :string, size: 10_000
    end
  end

  def down do
    alter table(:oauth_tokens) do
      modify :state, :string, size: 500
    end
  end
end
