defmodule Tuist.Repo.Migrations.AddBillingEmailToAccount do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :billing_email, :string, null: true
    end
  end
end
