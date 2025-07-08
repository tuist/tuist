defmodule TuistWeb.API.Schemas.ArtifactUploadId do
  @moduledoc """
  The schema for the artifact upload ID response.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ArtifactUploadID",
    description:
      "The upload has been initiated and a ID is returned to upload the various parts using multi-part uploads",
    type: :object,
    properties: %{
      status: %Schema{type: :string, default: "success", enum: ["success"]},
      data: %Schema{
        type: :object,
        description: "Data that contains ID that's associated with the multipart upload to use when uploading parts",
        properties: %{
          upload_id: %Schema{type: :string, description: "The upload ID"}
        },
        required: [:upload_id]
      }
    },
    required: [:status, :data]
  })
end
