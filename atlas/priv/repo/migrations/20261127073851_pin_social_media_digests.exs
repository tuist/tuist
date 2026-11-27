defmodule Atlas.Repo.Migrations.PinSocialMediaDigests do
  use Ecto.Migration

  def change do
    # The SHA-256 of the bytes finalized for a media row. The signed upload URL
    # stays valid after finalizing, so publishing checks the stored bytes still
    # match it.
    alter table(:social_media) do
      add :sha256, :string
    end

    # The size and digest of every attached media row when a person approved
    # the publication, by media id. Publishing posts only bytes that match.
    alter table(:social_publications) do
      add :approved_media, :map
    end
  end
end
