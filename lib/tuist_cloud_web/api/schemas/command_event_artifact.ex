defmodule TuistCloudWeb.API.Schemas.CommandEventArtifact do
  @moduledoc """
  The schema for the command event artifact.
  """

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CommandEventArtifact",
    description:
      "It represents an artifact that's associated with a command event (e.g. result bundles)",
    properties: %{
      type: %OpenApiSpex.Schema{
        description: "The command event artifact type.",
        type: :string,
        enum: ["result_bundle"]
      }
    },
    required: [:type]
  })
end
