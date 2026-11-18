defmodule Tuist.Repo.Migrations.AddTagToBundleThresholds do
  use Ecto.Migration

  def change do
    alter table(:bundle_thresholds) do
      add :tag, :string
    end
  end
end
