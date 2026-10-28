defmodule Atlas.Repo.Migrations.OauthTokensStateText do
  use Ecto.Migration

  # OAuth state is opaque client data and can exceed Boruta's varchar(255)
  # default. It must be stored and returned intact, never truncated.
  def up do
    alter table(:oauth_tokens) do
      modify :state, :text
    end
  end

  def down do
    alter table(:oauth_tokens) do
      modify :state, :string
    end
  end
end
