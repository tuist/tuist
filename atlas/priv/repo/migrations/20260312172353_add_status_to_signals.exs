defmodule Atlas.Repo.Migrations.AddStatusToSignals do
  use Ecto.Migration

  def change do
    alter table(:signals) do
      add :status, :string, null: false, default: "new"
    end

    create index(:signals, [:status])
  end
end
