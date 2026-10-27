defmodule Atlas.Repo.Migrations.CreateMemoryBulletins do
  use Ecto.Migration

  def change do
    create table(:memory_bulletins, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scope, :string, null: false, default: "global"

      add :slack_channel_id,
          references(:slack_channels, type: :binary_id, on_delete: :delete_all)

      add :body, :text, null: false
      add :generated_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:memory_bulletins, [:scope, :slack_channel_id],
             name: :memory_bulletins_scope_channel_index,
             nulls_distinct: false
           )
  end
end
