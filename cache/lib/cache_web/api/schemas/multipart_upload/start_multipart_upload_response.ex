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
        description: "The upload ID to use for subsequent part uploads."
      }
    },
    required: [:upload_id]
  })
end
