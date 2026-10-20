defmodule Atlas.Repo.Migrations.CreateProductReleases do
  use Ecto.Migration

  def change do
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
          references(:product_releases, type: :binary_id, on_delete: :delete_all), null: false

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
  end
end
