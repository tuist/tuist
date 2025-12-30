defmodule Tuist.Repo.Migrations.AddArtifactsIndexes do
  use Ecto.Migration

  def change do
    # Add index for bundle_id - most common query pattern (WHERE bundle_id = ?)
    # This is critical for bundle loading performance with 13M+ artifacts
    create index(:artifacts, [:bundle_id])

    # Add index for artifact_id - used for parent/child relationships and filtering top-level artifacts
    create index(:artifacts, [:artifact_id])

    # Add composite index for efficient parent/child queries (WHERE bundle_id = ? AND artifact_id = ?)
    create index(:artifacts, [:bundle_id, :artifact_id])

    # Add partial index specifically for top-level artifacts (WHERE bundle_id = ? AND artifact_id IS NULL)
    # This will be extremely fast for loading the initial bundle view
    create index(:artifacts, [:bundle_id],
             where: "artifact_id IS NULL",
             name: :artifacts_bundle_id_top_level_idx
           )
  end
end
