defmodule TuistWeb.API.Schemas.ArtifactMultipartUploadParts do
  @moduledoc """
  The schema for the artifact multipart upload parts.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    description:
      "It represents a part that has been uploaded using multipart uploads. The part is identified by its number and the etag",
    properties: %{
      upload_id: %Schema{type: :string, description: "The upload ID"},
      parts: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            part_number: %Schema{type: :integer, description: "The part number"},
            etag: %Schema{type: :string, description: "The ETag of the part"}
          },
          required: [:part_number, :etag]
        }
      }
    },
    required: [:upload_id, :parts]
  })
end
