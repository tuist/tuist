defmodule TuistWeb.API.Schemas.ArtifactMultipartUploadPart do
  @moduledoc """
  The schema for a multipart upload part.
  """

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ArtifactMultipartUploadPart",
    description:
      "Represents an multipart upload's part identified by the upload id and the part number",
    properties: %{
      part_number: %OpenApiSpex.Schema{
        description: "The part number of the multipart upload.",
        type: :integer
      },
      upload_id: %OpenApiSpex.Schema{
        description: "The upload ID.",
        type: :string
      },
      content_length: %OpenApiSpex.Schema{
        description: "The content length of the part.",
        type: :integer
      }
    },
    required: [:part_number, :upload_id]
  })
end
