defmodule Atlas.Repo.Migrations.AddInferenceProviderDecisionPath do
  use Ecto.Migration

  def change do
    alter table(:inference_providers) do
      add :decision_path, :string
    end
  end
end
