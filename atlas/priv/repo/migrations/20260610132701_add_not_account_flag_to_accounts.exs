defmodule Atlas.Repo.Migrations.AddNotAccountFlagToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :not_an_account_at, :utc_datetime
      add :not_an_account_reason, :text
    end

    create index(:accounts, [:not_an_account_at])
  end
end
