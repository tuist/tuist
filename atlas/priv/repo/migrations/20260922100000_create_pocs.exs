defmodule Atlas.Repo.Migrations.CreatePocs do
  use Ecto.Migration

  def change do
    create table(:pocs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :title, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :hosting, :string, null: false, default: "unknown"
      add :starts_on, :date
      add :ends_on, :date
      add :public_token, :uuid
      add :brand_accent_color, :string
      add :brand_logo_url, :string
      add :summary, :text

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :updated_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    create index(:pocs, [:account_id])
    create index(:pocs, [:status])
    create unique_index(:pocs, [:public_token])

    create table(:poc_contexts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :poc_id, references(:pocs, type: :binary_id, on_delete: :delete_all), null: false
      add :developer_count, :integer
      add :ci_solution, :string
      add :git_forge, :string
      add :primary_language, :string
      add :monorepo, :boolean
      add :notes, :text

      timestamps(type: :timestamptz)
    end

    create unique_index(:poc_contexts, [:poc_id])

    create table(:poc_scope_features, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :poc_id, references(:pocs, type: :binary_id, on_delete: :delete_all), null: false

      add :feature_interest_id,
          references(:feature_interests, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:poc_scope_features, [:poc_id, :feature_interest_id])
    create index(:poc_scope_features, [:feature_interest_id])

    create table(:poc_timeline_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :poc_id, references(:pocs, type: :binary_id, on_delete: :delete_all), null: false
      add :occurred_on, :date, null: false
      add :title, :string, null: false
      add :body, :text
      add :kind, :string, null: false, default: "event"
      add :author_label, :string

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    create index(:poc_timeline_entries, [:poc_id, :occurred_on])
  end
end
