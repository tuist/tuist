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
      },
      already_cached: %Schema{
        type: :boolean,
        description:
          "Whether the artifact is already cached. When true, upload_id is null and no upload is needed; when false, upload_id carries the id for the parts. Lets clients tell a cache hit apart from a failure instead of inferring it from a null upload_id. Optional so clients stay compatible with older servers that don't send it."
      }
    },
    required: [:upload_id]
  })
end
