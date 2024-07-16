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
      }
    },
    required: [:part_number, :upload_id]
  })
end
