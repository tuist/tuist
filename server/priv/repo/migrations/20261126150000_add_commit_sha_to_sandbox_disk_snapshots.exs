defmodule Tuist.Repo.Migrations.AddCommitShaToSandboxDiskSnapshots do
  use Ecto.Migration

  def change do
    alter table(:sandbox_disk_snapshots) do
      # The default branch's head a macOS repository snapshot's build cloned.
      add :commit_sha, :string
    end
  end
end
