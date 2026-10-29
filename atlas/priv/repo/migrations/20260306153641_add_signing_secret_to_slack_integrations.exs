defmodule Atlas.Repo.Migrations.AddSigningSecretToSlackIntegrations do
  use Ecto.Migration

  def change do
    alter table(:slack_integrations) do
      add :signing_secret, :string
    end
  end
end
