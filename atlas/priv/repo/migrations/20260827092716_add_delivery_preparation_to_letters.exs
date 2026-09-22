defmodule Atlas.Repo.Migrations.AddDeliveryPreparationToLetters do
  use Ecto.Migration

  def up do
    alter table(:letters) do
      add :delivery_details, :map
      add :delivery_prepared_at, :utc_datetime
    end

    drop constraint(:letters, :letters_status_check)

    create constraint(:letters, :letters_status_check,
             check:
               "status IN ('awaiting_signature', 'collecting_delivery_details', 'awaiting_delivery_confirmation', 'queued', 'sending', 'sent', 'delivered', 'undeliverable', 'failed')"
           )
  end

  def down do
    execute(
      "UPDATE letters SET status = 'awaiting_delivery_confirmation' WHERE status = 'collecting_delivery_details'"
    )

    drop constraint(:letters, :letters_status_check)

    create constraint(:letters, :letters_status_check,
             check:
               "status IN ('awaiting_signature', 'awaiting_delivery_confirmation', 'queued', 'sending', 'sent', 'delivered', 'undeliverable', 'failed')"
           )

    alter table(:letters) do
      remove :delivery_details
      remove :delivery_prepared_at
    end
  end
end
