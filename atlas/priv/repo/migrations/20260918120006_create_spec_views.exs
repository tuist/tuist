defmodule Atlas.Repo.Migrations.CreateSpecViews do
  use Ecto.Migration

  def change do
    create table(:spec_views, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :spec_id, references(:specs, type: :binary_id, on_delete: :delete_all), null: false
      add :last_viewed_at, :utc_datetime_usec, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:spec_views, [:user_id, :spec_id])
    create index(:spec_views, [:spec_id])
  end
end
