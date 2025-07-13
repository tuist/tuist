defmodule Tuist.Repo.Migrations.MakeAccountsBillingEmailNonOptional do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      # excellent_migrations:safety-assured-for-next-line not_null_added column_type_changed
      modify :billing_email, :string, null: false, from: {:string, null: true}
    end
  end
end
