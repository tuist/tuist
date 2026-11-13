defmodule Tuist.Repo.Migrations.AddLineageIdToSandboxDiskSnapshots do
  use Ecto.Migration

  # The Amp snapshot id a chain of refreshes started from. Amp refreshes a
  # project snapshot under a new id; the new save inherits the lineage of
  # the one it refreshes, so its copies go to the same nodes.
  def change do
    alter table(:sandbox_disk_snapshots) do
      add :lineage_id, :string
    end
  end
end
