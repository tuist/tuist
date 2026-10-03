defmodule Atlas.Repo.Migrations.CreateAccountFeatureRequestComments do
  use Ecto.Migration

  def change do
    create table(:account_feature_request_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :feature_request_id,
          references(:account_feature_requests, type: :binary_id, on_delete: :delete_all),
          null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :body, :text, null: false

      timestamps()
    end

    create index(:account_feature_request_comments, [:feature_request_id, :inserted_at])
    create index(:account_feature_request_comments, [:author_id])
  end
end
