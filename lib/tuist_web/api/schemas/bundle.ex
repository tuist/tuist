defmodule TuistWeb.API.Schemas.Bundle do
  @moduledoc """
  The schema for a bundle.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "Bundle",
    description: "Response schema for bundle",
    type: :object,
    properties: %{
      id: %Schema{
        type: :string,
        description:
          "The ID of the bundle. This is not a bundle ID that you'd set in Xcode but the database identifier of the bundle."
      },
      url: %Schema{
        type: :string,
        description: "The URL of the bundle"
      }
    },
    required: [:id, :url]
  })
end
