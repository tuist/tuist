defmodule TuistWeb.API.Schemas.CacheArtifactDownloadURL do
  @moduledoc """
  The schema for the cache artifact download URL.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CacheArtifactDownloadURL",
    description: "The URL to download the artifact from the cache.",
    type: :object,
    properties: %{
      status: %Schema{type: :string, default: "success", enum: ["success"]},
      data: %Schema{
        type: :object,
        properties: %{
          url: %Schema{
            type: :string,
            description: "The URL to download the artifact from the cache."
          },
          expires_at: %Schema{
            type: :integer,
            description: "The UNIX timestamp when the URL expires."
          }
        },
        required: [:url, :expires_at]
      }
    },
    required: [:status, :data]
  })
end
