defmodule TuistWeb.API.Schemas.ArtifactUploadURL do
  @moduledoc """
  The schema for an artifact upload URL.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ArtifactUploadURL",
    description: "The URL to upload an artifact.",
    type: :object,
    properties: %{
      url: %Schema{
        type: :string,
        description: "The URL to upload the artifact."
      },
      expires_at: %Schema{
        type: :integer,
        description: "The UNIX timestamp when the URL expires."
      }
    },
    required: [:url, :expires_at]
  })
end
