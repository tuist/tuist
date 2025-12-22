defmodule TuistWeb.API.Schemas.AppBuild do
  @moduledoc """
  The schema for the Tuist AppBuild response.
  """
  alias OpenApiSpex.Schema
  alias Tuist.AppBuilds.AppBuild
  alias TuistWeb.API.Schemas.PreviewSupportedPlatform

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    properties: %{
      id: %Schema{
        type: :string,
        description: "Unique identifier of the build."
      },
      url: %Schema{type: :string, description: "The URL to download the build"},
      type: %Schema{
        type: :string,
        enum: Ecto.Enum.values(AppBuild, :type),
        description: "The type of the build"
      },
      supported_platforms: %Schema{
        type: :array,
        items: PreviewSupportedPlatform
      },
      binary_id: %Schema{
        type: :string,
        description: "The Mach-O UUID of the build's main binary."
      }
    },
    required: [:id, :url, :type, :supported_platforms]
  })
end
