defmodule TuistWeb.API.Schemas.ArtifactMultipartUploadPart do
  @moduledoc """
  The schema for a multipart upload part.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ArtifactMultipartUploadPart",
    description: "Represents an multipart upload's part identified by the upload id and the part number",
    type: :object,
    properties: %{
      part_number: %Schema{
        description: "The part number of the multipart upload.",
        type: :integer
      },
      upload_id: %Schema{
        description: "The upload ID.",
        type: :string
      },
      content_length: %Schema{
        description: "The content length of the part.",
        type: :integer
      }
    },
    required: [:part_number, :upload_id]
  })
end
