defmodule Atlas.Repo.Migrations.AddDirectDeliveries do
  use Ecto.Migration

  def up do
    drop constraint(:gtm_deliveries, :gtm_deliveries_kind)

    create constraint(:gtm_deliveries, :gtm_deliveries_kind,
             check: "kind IN ('broadcast', 'welcome', 'confirmation', 'transactional', 'direct')"
           )

    create index(:gtm_deliveries, [:kind, :recipient_email, :inserted_at],
             where: "kind = 'direct'",
             name: :gtm_deliveries_direct_recipient_index
           )
  end

  def down do
    drop index(:gtm_deliveries, [:kind, :recipient_email, :inserted_at],
           name: :gtm_deliveries_direct_recipient_index
         )

    drop constraint(:gtm_deliveries, :gtm_deliveries_kind)

    execute "DELETE FROM gtm_deliveries WHERE kind = 'direct'"

    create constraint(:gtm_deliveries, :gtm_deliveries_kind,
             check: "kind IN ('broadcast', 'welcome', 'confirmation', 'transactional')"
           )
  end
end
