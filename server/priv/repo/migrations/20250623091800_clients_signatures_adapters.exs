defmodule Tuist.Repo.Migrations.ClientsSignaturesAdapters do
  use Ecto.Migration

  def up do
    alter table(:oauth_clients) do
      add :signatures_adapter, :string, null: false, default: "Elixir.Boruta.Internal.Signatures"
      modify :did, :text
    end
  end

  def down do
    alter table(:oauth_clients) do
      modify :did, :string
      remove :signatures_adapter
    end
  end
end
