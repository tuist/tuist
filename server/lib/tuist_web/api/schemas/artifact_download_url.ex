defmodule TuistWeb.API.Schemas.ArtifactDownloadURL do
  @moduledoc """
  The schema for an artifact download URL.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ArtifactDownloadURL",
    description: "The URL to download an artifact.",
    type: :object,
    properties: %{
      url: %Schema{
        type: :string,
        description: "The URL to download the artifact."
      },
      expires_at: %Schema{
        type: :integer,
        description: "The UNIX timestamp when the URL expires."
      }
    },
    required: [:url, :expires_at]
  })
end
