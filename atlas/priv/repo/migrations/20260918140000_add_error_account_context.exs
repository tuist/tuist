defmodule Atlas.Repo.Migrations.AddErrorAccountContext do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :plan_tier, :string
    end

    create index(:accounts, [:plan_tier])

    create table(:errors_issues_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :issue_id, references(:errors_issues, type: :binary_id, on_delete: :delete_all),
        null: false

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :event_count, :bigint, default: 0, null: false
      add :first_seen, :utc_datetime_usec, null: false
      add :last_seen, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:errors_issues_accounts, [:issue_id, :account_id])
    create index(:errors_issues_accounts, [:account_id, :last_seen])
    create index(:errors_issues_accounts, [:issue_id, :last_seen])
  end
end
