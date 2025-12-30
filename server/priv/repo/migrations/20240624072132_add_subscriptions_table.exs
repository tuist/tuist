defmodule Tuist.Repo.Migrations.AddSubscriptionsTable do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add(:subscription_id, :string, required: true)
      add(:plan, :integer, required: true)
      add(:status, :string, required: true)
      add(:account_id, references(:accounts, on_delete: :delete_all))
      add(:default_payment_method, :string)
      # credo:disable-for-next-line Credo.Checks.TimestampsType
      timestamps()
    end

    create unique_index(:subscriptions, [:subscription_id])
  end
end
