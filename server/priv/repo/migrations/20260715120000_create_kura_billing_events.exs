defmodule Tuist.Repo.Migrations.CreateKuraBillingEvents do
  use Ecto.Migration

  def change do
    create table(:kura_billing_events, primary_key: false) do
      add :event_id, :text, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :reported_at, :timestamptz, null: false
    end
  end
end
