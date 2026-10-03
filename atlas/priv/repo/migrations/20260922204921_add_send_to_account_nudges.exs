defmodule Atlas.Repo.Migrations.AddSendToAccountNudges do
  use Ecto.Migration

  def up do
    alter table(:account_nudges) do
      add :sent_at, :utc_datetime

      add :email_delivery_id,
          references(:gtm_deliveries, type: :binary_id, on_delete: :nilify_all)

      add :email_delivery_observed_at, :utc_datetime
    end

    create index(:account_nudges, [:email_delivery_id])

    create index(:account_nudges, [:state, :email_delivery_id],
             where: "state = 'sent' AND email_delivery_id IS NOT NULL",
             name: :account_nudges_sent_delivery_index
           )

    execute("ALTER TABLE account_nudges DROP CONSTRAINT account_nudges_state_check")

    execute("""
    ALTER TABLE account_nudges
      ADD CONSTRAINT account_nudges_state_check
      CHECK (state IN ('pending_post', 'proposed', 'claimed', 'sent', 'dismissed', 'expired'))
    """)
  end

  def down do
    execute("ALTER TABLE account_nudges DROP CONSTRAINT account_nudges_state_check")

    execute("""
    ALTER TABLE account_nudges
      ADD CONSTRAINT account_nudges_state_check
      CHECK (state IN ('pending_post', 'proposed', 'claimed', 'dismissed', 'expired'))
    """)

    drop index(:account_nudges, [:state, :email_delivery_id],
           name: :account_nudges_sent_delivery_index
         )

    drop index(:account_nudges, [:email_delivery_id])

    alter table(:account_nudges) do
      remove :email_delivery_observed_at
      remove :email_delivery_id
      remove :sent_at
    end
  end
end
