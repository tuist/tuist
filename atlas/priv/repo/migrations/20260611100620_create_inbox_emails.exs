defmodule Atlas.Repo.Migrations.CreateInboxEmails do
  use Ecto.Migration

  def change do
    create table(:inbox_emails, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :raw_email, :binary, null: false
      add :envelope_from, :string
      add :envelope_to, :string
      add :received_at, :utc_datetime, null: false
      add :status, :string, null: false, default: "pending"
      add :processed_at, :utc_datetime
      add :outcome, :map
      add :last_error, :text

      timestamps()
    end

    create index(:inbox_emails, [:status, :received_at])
    create index(:inbox_emails, [:received_at])
  end
end
