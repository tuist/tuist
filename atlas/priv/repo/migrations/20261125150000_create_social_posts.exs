defmodule Atlas.Repo.Migrations.CreateSocialPosts do
  use Ecto.Migration

  def change do
    create table(:social_posts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :platform, :string, null: false
      add :external_id, :string, null: false
      add :account_id, :string, null: false
      add :account_handle, :string, null: false
      add :url, :string, null: false
      add :text, :text, null: false
      add :format, :string, null: false
      add :thread, :boolean, null: false, default: false
      add :posted_at, :utc_datetime, null: false

      add :impressions, :integer, null: false, default: 0
      add :likes, :integer, null: false, default: 0
      add :reposts, :integer, null: false, default: 0
      add :quotes, :integer, null: false, default: 0
      add :replies, :integer, null: false, default: 0
      add :bookmarks, :integer, null: false, default: 0
      add :url_clicks, :integer
      add :profile_clicks, :integer
      add :metrics_updated_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:social_posts, [:platform, :external_id])
    create index(:social_posts, [:posted_at])

    create table(:social_post_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :social_post_id, references(:social_posts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :captured_on, :date, null: false

      add :impressions, :integer, null: false
      add :likes, :integer, null: false
      add :reposts, :integer, null: false
      add :quotes, :integer, null: false
      add :replies, :integer, null: false
      add :bookmarks, :integer, null: false
      add :url_clicks, :integer
      add :profile_clicks, :integer

      timestamps()
    end

    create unique_index(:social_post_snapshots, [:social_post_id, :captured_on])
  end
end
