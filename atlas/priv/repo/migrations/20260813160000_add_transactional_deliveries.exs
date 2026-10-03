defmodule Atlas.Repo.Migrations.AddTransactionalDeliveries do
  use Ecto.Migration

  def up do
    alter table(:gtm_deliveries) do
      # Holds the transactional template id and its data variables so the send
      # can be rendered again on a retry without the caller repeating itself.
      add :metadata, :map, null: false, default: %{}
    end

    drop constraint(:gtm_deliveries, :gtm_deliveries_kind)

    create constraint(:gtm_deliveries, :gtm_deliveries_kind,
             check: "kind IN ('broadcast', 'welcome', 'confirmation', 'transactional')"
           )
  end

  def down do
    drop constraint(:gtm_deliveries, :gtm_deliveries_kind)

    execute "DELETE FROM gtm_deliveries WHERE kind = 'transactional'"

    create constraint(:gtm_deliveries, :gtm_deliveries_kind,
             check: "kind IN ('broadcast', 'welcome', 'confirmation')"
           )

    alter table(:gtm_deliveries) do
      remove :metadata
    end
  end
end
