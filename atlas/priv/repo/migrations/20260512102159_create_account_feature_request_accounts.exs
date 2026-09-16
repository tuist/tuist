defmodule Atlas.Repo.Migrations.CreateAccountFeatureRequestAccounts do
  use Ecto.Migration

  def change do
    create table(:account_feature_request_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :feature_request_id,
          references(:account_feature_requests, type: :binary_id, on_delete: :delete_all),
          null: false

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create unique_index(:account_feature_request_accounts, [:feature_request_id, :account_id])
    create index(:account_feature_request_accounts, [:account_id])

    execute(
      """
      INSERT INTO account_feature_request_accounts (id, feature_request_id, account_id, inserted_at, updated_at)
      SELECT gen_random_uuid(), id, account_id, inserted_at, updated_at
      FROM account_feature_requests
      """,
      "DELETE FROM account_feature_request_accounts"
    )
  end
end
