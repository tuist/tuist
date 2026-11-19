defmodule Atlas.Repo.Migrations.AddMcpEventReceiversToSignals do
  use Ecto.Migration

  def change do
    alter table(:signal_sources) do
      add :event_receiver, :map
      add :signing_secret, :binary
    end

    create constraint(:signal_sources, :event_receiver_secret_pair,
             check: "(event_receiver IS NULL) = (signing_secret IS NULL)"
           )
  end
end
