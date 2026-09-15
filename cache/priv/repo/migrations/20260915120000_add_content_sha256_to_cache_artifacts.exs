defmodule Cache.Repo.Migrations.AddContentSha256ToCacheArtifacts do
  use Ecto.Migration

  # The lowercase hex SHA-256 an uploading CLI declared for the artifact and
  # the server verified at multipart completion. Served back as
  # `tuist-checksum-sha256` so the downloader can check the body it received.
  # Nullable: artifacts from clients that declare nothing, and every row
  # written before this column existed, carry no digest and are served
  # unverified, as before.
  def change do
    alter table(:cache_artifacts) do
      add :content_sha256, :string
    end
  end
end
