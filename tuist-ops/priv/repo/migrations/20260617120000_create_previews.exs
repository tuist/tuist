defmodule TuistOps.Repo.Migrations.CreatePreviews do
  use Ecto.Migration

  def change do
    create table(:previews) do
      add :slug, :string, null: false
      add :status, :string, null: false, default: "creating"
      add :requester_email, :string, null: false
      add :requester_slack_id, :string, null: false
      add :ref_kind, :string
      add :ref_value, :string
      add :reason, :text, null: false
      add :ttl_seconds, :integer
      add :host, :string
      add :slack_channel_id, :string, null: false
      add :slack_message_ts, :string
      add :deleted_at, :utc_datetime
      add :failed_at, :utc_datetime
      add :failure_reason, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:previews, [:slug])
    create index(:previews, [:status])
  end
end
