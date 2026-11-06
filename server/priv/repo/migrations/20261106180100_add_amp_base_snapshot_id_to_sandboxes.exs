defmodule Tuist.Repo.Migrations.AddAmpBaseSnapshotIdToSandboxes do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      # The Amp project snapshot the Orb's first spawn asked to boot from.
      # A snapshot the Orb saves later under another identifier supersedes it.
      add :amp_base_snapshot_id, :string
    end
  end
end
