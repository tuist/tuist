defmodule Atlas.Repo.Migrations.AddCcEmailsToGtmDeliveries do
  use Ecto.Migration

  def change do
    alter table(:gtm_deliveries) do
      add :cc_emails, {:array, :string}, null: false, default: []
    end
  end
end
