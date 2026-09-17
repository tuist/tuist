defmodule Atlas.Repo.Migrations.DropProductAndFeatureRequestTables do
  use Ecto.Migration

  def up do
    execute """
    UPDATE gtm_signal_queries
    SET enabled = false, updated_at = now()
    WHERE metadata->>'topic_source' IN ('product_changelog', 'agent')
    """

    execute "ALTER TABLE account_action_items DROP COLUMN IF EXISTS feature_request_id"

    drop_if_exists table(:account_feature_request_accounts)
    drop_if_exists table(:account_feature_request_comments)
    drop_if_exists table(:account_feature_requests)

    drop_if_exists table(:product_release_issue_notifications)
    drop_if_exists table(:product_releases)
    drop_if_exists table(:product_changelog_domains)
    drop_if_exists table(:product_changelog_entries)

    execute "DROP TABLE IF EXISTS product_features CASCADE"
  end

  def down do
    create table(:product_changelog_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entry_id, :string, null: false
      add :domains, {:array, :string}, default: [], null: false
      add :title, :string, null: false
      add :description, :text, null: false
      add :release_date, :date, null: false
      add :source_guid, :string, null: false
      add :source_url, :string, null: false
      add :source_title, :string, null: false
      add :source_description, :text, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create unique_index(:product_changelog_entries, [:entry_id])
    create unique_index(:product_changelog_entries, [:source_guid])
    create index(:product_changelog_entries, [:domains], using: :gin)
    create index(:product_changelog_entries, [:release_date])

    create table(:product_changelog_domains, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:product_changelog_domains, ["lower(name)"],
             name: :product_changelog_domains_lower_name_index
           )

    create table(:product_releases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_id, :string, null: false
      add :tag_name, :string, null: false
      add :name, :string
      add :body, :text, null: false
      add :html_url, :string, null: false
      add :published_at, :utc_datetime_usec, null: false
      add :status, :string, null: false, default: "pending"
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create table(:product_release_issue_notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :product_release_id,
          references(:product_releases, type: :binary_id, on_delete: :delete_all),
          null: false

      add :issue_number, :integer, null: false
      add :issue_url, :string, null: false
      add :comment_body, :text, null: false
      add :github_comment_id, :string
      add :github_comment_url, :string
      add :status, :string, null: false, default: "pending"
      add :error, :text
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:product_releases, [:source_id])
    create unique_index(:product_releases, [:tag_name])
    create index(:product_releases, [:published_at])
    create index(:product_releases, [:status])

    create unique_index(:product_release_issue_notifications, [
             :product_release_id,
             :issue_number
           ])

    create index(:product_release_issue_notifications, [:status])

    create table(:account_feature_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source_action_item_id,
          references(:account_action_items, type: :binary_id, on_delete: :nilify_all)

      add :status, :string, null: false, default: "open"
      add :title, :string, null: false
      add :body, :text
      add :request_count, :integer, null: false, default: 1
      add :last_requested_at, :utc_datetime
      add :created_by_agent, :string
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create index(:account_feature_requests, [:account_id, :status])
    create index(:account_feature_requests, [:account_id, :last_requested_at])
    create index(:account_feature_requests, [:source_action_item_id])

    alter table(:account_action_items) do
      add :feature_request_id,
          references(:account_feature_requests, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:account_action_items, [:feature_request_id])

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
  end
end
