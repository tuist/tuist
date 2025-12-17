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
        description: "The upload ID to use for subsequent part uploads. Null if artifact already exists."
      }
    },
    required: [:upload_id]
  })
end

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
