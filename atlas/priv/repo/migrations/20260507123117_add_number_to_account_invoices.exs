defmodule Atlas.Repo.Migrations.AddNumberToAccountInvoices do
  use Ecto.Migration

  def change do
    alter table(:account_invoices) do
      add :number, :string
    end
  end
end
