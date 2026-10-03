defmodule Atlas.Repo.Migrations.CreateMailingContactsListsAndBroadcasts do
  use Ecto.Migration

  def change do
    create table(:gtm_subscribers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :first_name, :string
      add :last_name, :string
      add :user_group, :string
      add :source, :string, null: false, default: "atlas"
      add :status, :string, null: false, default: "subscribed"
      add :metadata, :map, null: false, default: %{}
      add :confirmed_at, :utc_datetime
      add :unsubscribed_at, :utc_datetime
      add :welcomed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:gtm_subscribers, ["lower(email)"],
             name: :gtm_subscribers_lower_email_index
           )

    create index(:gtm_subscribers, [:status])
    create index(:gtm_subscribers, [:source])

    create constraint(:gtm_subscribers, :gtm_subscribers_status,
             check: "status IN ('pending', 'subscribed', 'unsubscribed')"
           )

    create table(:gtm_audiences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :source_id, :string

      timestamps()
    end

    create unique_index(:gtm_audiences, [:slug])
    create unique_index(:gtm_audiences, [:source_id], where: "source_id IS NOT NULL")

    create table(:gtm_audience_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :audience_id, references(:gtm_audiences, type: :binary_id, on_delete: :delete_all),
        null: false

      add :subscriber_id, references(:gtm_subscribers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "subscribed"
      add :unsubscribed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:gtm_audience_memberships, [:audience_id, :subscriber_id])
    create index(:gtm_audience_memberships, [:subscriber_id, :status])

    create constraint(:gtm_audience_memberships, :gtm_audience_memberships_status,
             check: "status IN ('pending', 'subscribed', 'unsubscribed')"
           )

    create table(:gtm_broadcasts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :audience_id, references(:gtm_audiences, type: :binary_id, on_delete: :restrict),
        null: false

      add :sender_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :subject, :string, null: false
      add :body_markdown, :text, null: false
      add :from_name, :string, null: false
      add :from_email, :string, null: false
      add :reply_to_email, :string
      add :status, :string, null: false, default: "pending"
      add :source_id, :string
      add :recipients_count, :integer, null: false, default: 0
      add :delivered_count, :integer, null: false, default: 0
      add :failed_count, :integer, null: false, default: 0
      add :skipped_count, :integer, null: false, default: 0
      add :sent_at, :utc_datetime

      timestamps()
    end

    create unique_index(:gtm_broadcasts, [:source_id], where: "source_id IS NOT NULL")
    create index(:gtm_broadcasts, [:audience_id, :inserted_at])
    create index(:gtm_broadcasts, [:status])

    create constraint(:gtm_broadcasts, :gtm_broadcasts_status,
             check: "status IN ('pending', 'sending', 'sent', 'failed')"
           )

    create table(:gtm_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :broadcast_id, references(:gtm_broadcasts, type: :binary_id, on_delete: :delete_all)

      add :audience_id, references(:gtm_audiences, type: :binary_id, on_delete: :nilify_all)

      add :subscriber_id, references(:gtm_subscribers, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :recipient_email, :string, null: false
      add :recipient_name, :string
      add :subject, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :provider_message_id, :string
      add :error, :text
      add :delivered_at, :utc_datetime

      timestamps()
    end

    create unique_index(:gtm_deliveries, [:broadcast_id, :recipient_email],
             where: "broadcast_id IS NOT NULL"
           )

    create index(:gtm_deliveries, [:subscriber_id, :inserted_at])
    create index(:gtm_deliveries, [:audience_id, :inserted_at])
    create index(:gtm_deliveries, [:status])

    create unique_index(:gtm_deliveries, [:subscriber_id, :kind],
             where: "kind = 'welcome' AND subscriber_id IS NOT NULL",
             name: :gtm_deliveries_unique_welcome_index
           )

    create constraint(:gtm_deliveries, :gtm_deliveries_kind,
             check: "kind IN ('broadcast', 'welcome', 'confirmation')"
           )

    create constraint(:gtm_deliveries, :gtm_deliveries_status,
             check: "status IN ('pending', 'delivered', 'failed', 'skipped')"
           )
  end
end
