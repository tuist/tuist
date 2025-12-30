defmodule CacheWeb.API.Schemas.CompleteMultipartUploadRequest do
  @moduledoc false
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CompleteMultipartUploadRequest",
    description: "Request to complete a multipart upload",
    type: :object,
    properties: %{
      parts: %Schema{
        type: :array,
        items: %Schema{type: :integer},
        description: "Ordered list of part numbers that were uploaded"
      }
    },
    required: [:parts]
  })
end
