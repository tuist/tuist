defmodule Tuist.Repo.Migrations.AddWebhookDeliveryAttemptsTable do
  use Ecto.Migration

  def change do
    create table(:webhook_delivery_attempts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :webhook_endpoint_id, references(:webhook_endpoints, type: :uuid, on_delete: :delete_all),
        null: false

      add :event_id, :string, null: false
      add :event_type, :string, null: false
      add :attempt, :integer, null: false
      add :status, :string, null: false
      add :request_body, :text
      add :request_headers, :map
      add :response_status, :integer
      add :response_headers, :map
      add :response_body, :text
      add :error, :text
      add :duration_ms, :integer

      timestamps(type: :timestamptz)
    end

    create index(:webhook_delivery_attempts, [:webhook_endpoint_id, :inserted_at])
    create index(:webhook_delivery_attempts, [:webhook_endpoint_id, :event_id])
    create index(:webhook_delivery_attempts, [:webhook_endpoint_id, :status])
  end
end
