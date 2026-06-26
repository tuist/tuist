defmodule CacheWeb.API.Schemas.StartMultipartUploadResponse do
  @moduledoc false
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "StartMultipartUploadResponse",
    description: "Response from starting a multipart upload",
    type: :object,
    properties: %{
      upload_id: %Schema{
        type: :string,
        nullable: true,
        description:
          "The upload ID to use for subsequent part uploads. Null on the legacy cache-hit response returned to CLIs that predate the 204 No Content signal."
      }
    },
    required: [:upload_id]
  })
end
