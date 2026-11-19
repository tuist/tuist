defmodule Tuist.Repo.Migrations.AddAmpSnapshotLineageIdToSandboxes do
  use Ecto.Migration

  # The disk snapshot lineage an Orb was spawned in. Amp refreshes a project
  # snapshot under a new id and the old row is deleted, so a lineage's
  # spawns are counted by this column, not by the Amp ids.
  def change do
    alter table(:sandboxes) do
      add :amp_snapshot_lineage_id, :string
    end
  end
end
