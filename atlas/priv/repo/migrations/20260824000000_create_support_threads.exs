defmodule Atlas.Repo.Migrations.CreateSupportThreads do
  use Ecto.Migration

  def change do
    create table(:support_threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :customer_name, :string
      add :customer_email, :string, null: false
      add :subject, :string
      add :status, :string, null: false, default: "open"
      add :last_message_at, :utc_datetime, null: false
      add :last_inbound_at, :utc_datetime
      add :resolved_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create index(:support_threads, [:status, :last_message_at])
    create index(:support_threads, [:owner_id, :status, :last_message_at])
    create index(:support_threads, [:account_id, :last_message_at])
    create index(:support_threads, [:customer_email])

    create constraint(:support_threads, :support_threads_status_check,
             check: "status IN ('open', 'waiting', 'resolved')"
           )

    create table(:support_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :thread_id, references(:support_threads, type: :binary_id, on_delete: :delete_all),
        null: false

      add :inbox_email_id, references(:inbox_emails, type: :binary_id, on_delete: :nilify_all)
      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :message_id, :string
      add :in_reply_to, :string
      add :references, {:array, :string}, null: false, default: []
      add :sender_name, :string
      add :sender_email, :string
      add :to_emails, {:array, :string}, null: false, default: []
      add :cc_emails, {:array, :string}, null: false, default: []
      add :body, :text, null: false
      add :delivery_status, :string
      add :provider_message_id, :string
      add :delivery_error, :text
      add :delivered_at, :utc_datetime
      add :occurred_at, :utc_datetime, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create index(:support_messages, [:thread_id, :occurred_at])
    create unique_index(:support_messages, [:inbox_email_id], where: "inbox_email_id IS NOT NULL")
    create unique_index(:support_messages, [:message_id], where: "message_id IS NOT NULL")
    create index(:support_messages, [:in_reply_to])

    create constraint(:support_messages, :support_messages_kind_check,
             check: "kind IN ('inbound', 'outbound', 'note')"
           )

    create constraint(:support_messages, :support_messages_delivery_status_check,
             check:
               "delivery_status IS NULL OR delivery_status IN ('queued', 'sending', 'delivered', 'failed')"
           )
  end
end
