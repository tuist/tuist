defmodule Atlas.Repo.Migrations.AddReachabilityAndPriorityToAccountContacts do
  use Ecto.Migration

  def change do
    alter table(:account_contacts) do
      add :bounced_at, :utc_datetime
      add :opted_out_at, :utc_datetime
      add :is_decision_maker, :boolean, null: false, default: false
      add :is_primary, :boolean, null: false, default: false
    end

    create index(:account_contacts, [:account_id, :is_primary],
             where: "is_primary = true",
             name: :account_contacts_primary_index
           )
  end
end
