defmodule TuistWeb.API.Schemas.BundleArtifact do
  @moduledoc """
  The schema for the bundle artifact.
  """
  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema
  alias Tuist.Bundles.Artifact

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "BundleArtifact",
    description: "A bundle artifact schema",
    type: :object,
    properties: %{
      artifact_type: %Schema{
        type: :string,
        description: "The type of artifact",
        enum: Ecto.Enum.values(Artifact, :artifact_type)
      },
      path: %Schema{
        type: :string,
        description: "The path to the artifact relative to the root of the bundle."
      },
      size: %Schema{
        type: :integer,
        description: "The size of the artifact in bytes"
      },
      shasum: %Schema{
        type: :string,
        description: "The SHA checksum of the artifact"
      },
      children: %Schema{
        type: :array,
        description: "Nested child artifacts, for example for artifacts that represent a directory.",
        items: %Reference{"$ref": "#/components/schemas/BundleArtifact"}
      }
    },
    required: [:artifact_type, :path, :size, :shasum]
  })
end
