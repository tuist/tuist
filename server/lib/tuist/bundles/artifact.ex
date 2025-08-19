defmodule Tuist.Bundles.Artifact do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "artifacts" do
    field :artifact_type, Ecto.Enum, values: [:directory, :file, :font, :binary, :localization, :asset, :unknown]

    field :path, :string
    field :size, :integer
    field :shasum, :string

    belongs_to :bundle, Tuist.Bundles.Bundle
    belongs_to :artifact, __MODULE__
    has_many :children, __MODULE__

    timestamps(type: :utc_datetime)
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [:artifact_type, :path, :size, :shasum, :bundle_id, :artifact_id])
    |> validate_required([:artifact_type, :path, :size, :shasum, :bundle_id])
    |> validate_inclusion(:artifact_type, Ecto.Enum.values(__MODULE__, :artifact_type))
    |> foreign_key_constraint(:bundle_id)
    |> foreign_key_constraint(:artifact_id)
  end
end
