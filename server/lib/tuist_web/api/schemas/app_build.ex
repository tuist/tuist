defmodule TuistWeb.API.Schemas.AppBuild do
  @moduledoc """
  The schema for the Tuist AppBuild response.
  """
  alias OpenApiSpex.Schema

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
        description:
          "The build format, currently app_bundle, ipa, apk or executable. Clients must ignore unknown formats."
      },
      supported_platforms: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Supported platforms. Clients must ignore unknown platforms."
      },
      supported_architectures: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description:
          "CPU architectures in the build, currently arm64 and x86_64. Empty or absent means unknown or interpreter-based; clients must inspect the downloaded executable."
      },
      binary_id: %Schema{
        type: :string,
        description: "The Mach-O UUID or SHA-256 content hash of the build."
      }
    },
    required: [:id, :url, :type, :supported_platforms]
  })
end
