defmodule TuistOps.Repo.Migrations.CreatePreviewRequests do
  use Ecto.Migration

  def change do
    create table(:preview_requests) do
      add :slug, :string, null: false
      add :action, :string, null: false
      add :status, :string, null: false, default: "requested"
      add :requester_email, :string, null: false
      add :requester_slack_id, :string, null: false
      add :ref_kind, :string
      add :ref_value, :string
      add :reason, :text, null: false
      add :ttl_seconds, :integer
      add :host, :string
      add :namespace, :string
      add :release, :string
      add :slack_channel_id, :string, null: false
      add :slack_message_ts, :string
      add :workflow_id, :string
      add :workflow_ref, :string
      add :expires_at, :utc_datetime
      add :deleted_at, :utc_datetime
      add :failed_at, :utc_datetime
      add :failure_reason, :text

      timestamps(type: :utc_datetime)
    end

    create index(:preview_requests, [:slug, :inserted_at])
    create index(:preview_requests, [:status])
    create index(:preview_requests, [:expires_at])
  end
end
