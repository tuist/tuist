defmodule Tuist.Repo.Migrations.AddEventTypesToWebhookEndpoints do
  use Ecto.Migration

  def change do
    alter table(:webhook_endpoints) do
      # The empty-array default is only needed so existing rows backfill
      # safely; the app-level changeset rejects endpoints with an empty
      # subscription list.
      add :event_types, {:array, :string}, null: false, default: []
    end
  end
end
