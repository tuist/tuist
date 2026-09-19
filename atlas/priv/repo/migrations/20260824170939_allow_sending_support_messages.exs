defmodule Atlas.Repo.Migrations.AllowSendingSupportMessages do
  use Ecto.Migration

  def up do
    drop constraint(:support_messages, :support_messages_delivery_status_check)

    create constraint(:support_messages, :support_messages_delivery_status_check,
             check:
               "delivery_status IS NULL OR delivery_status IN ('queued', 'sending', 'delivered', 'failed')"
           )
  end

  def down do
    drop constraint(:support_messages, :support_messages_delivery_status_check)

    create constraint(:support_messages, :support_messages_delivery_status_check,
             check:
               "delivery_status IS NULL OR delivery_status IN ('queued', 'delivered', 'failed')"
           )
  end
end
