defmodule Tuist.Repo.Migrations.CreateBundleThresholds do
  use Ecto.Migration

  def change do
    create table(:bundle_thresholds, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :string, null: false, default: "Untitled"
      add :metric, :integer, null: false
      add :deviation_percentage, :float, null: false
      add :baseline_branch, :string, null: false
      add :bundle_name, :string
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:bundle_thresholds, [:project_id])
  end
end
