defmodule Cache.CacheArtifact do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "cas_artifacts" do
    field :key, :string
    field :size_bytes, :integer
    field :last_accessed_at, :utc_datetime_usec

    timestamps()
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [:key, :size_bytes, :last_accessed_at])
    |> validate_required([:key, :last_accessed_at])
  end
end
