defmodule Atlas.Repo.Migrations.MakeAccountInvoiceDueDateNullable do
  use Ecto.Migration

  def change do
    alter table(:account_invoices) do
      modify :due_date, :date, null: true, from: {:date, null: false}
    end
  end
end
