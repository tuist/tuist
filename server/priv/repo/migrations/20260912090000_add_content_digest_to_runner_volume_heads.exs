defmodule Tuist.Repo.Migrations.AddContentDigestToRunnerVolumeHeads do
  use Ecto.Migration

  # SHA-256 of the master image object's bytes, published alongside the
  # inventory digest at promote time. The inventory digest (tree_digest) is a
  # hash of sorted entry names and CAS file sizes — it detects cache-set
  # changes and keys the immutable object, but says nothing about the bytes
  # inside the cached files. The content digest is what lets a converging host
  # verify the downloaded object bit-for-bit before adopting it as its master.
  #
  # Nullable for rollout: promotes from runner images that predate the content
  # hash publish no digest, and hosts skip the content check for a HEAD row
  # without one (the inventory check still applies, the status quo).
  def change do
    alter table(:runner_volume_heads) do
      add :content_digest, :string
    end
  end
end
