defmodule Atlas.Repo.Migrations.CreateProductChangelogEntries do
  use Ecto.Migration

  def change do
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
  end
end
