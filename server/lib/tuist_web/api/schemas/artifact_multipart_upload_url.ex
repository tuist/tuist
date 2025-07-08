defmodule TuistWeb.API.Schemas.ArtifactMultipartUploadUrl do
  @moduledoc """
  The schema for the artifact multipart upload URL.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ArtifactMultipartUploadURL",
    description: "The URL to upload a multipart part",
    type: :object,
    properties: %{
      status: %Schema{type: :string, default: "success", enum: ["success"]},
      data: %Schema{
        type: :object,
        properties: %{
          url: %Schema{type: :string, description: "The URL to upload the part"}
        },
        required: [:url]
      }
    },
    required: [:status, :data]
  })
end
