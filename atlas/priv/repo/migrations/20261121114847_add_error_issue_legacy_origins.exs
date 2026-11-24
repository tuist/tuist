defmodule Atlas.Repo.Migrations.AddErrorIssueLegacyOrigins do
  use Ecto.Migration

  def change do
    alter table(:errors_issues) do
      add :legacy_ids, {:array, :uuid}, null: false, default: []
    end
  end
end
