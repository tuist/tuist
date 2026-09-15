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
      },
      checksum_sha256: %Schema{
        type: :string,
        description:
          "Lowercase hex SHA-256 (64 characters) of the assembled artifact. When present, the server refuses " <>
            "the completion with 422 if the assembled bytes do not match, and otherwise serves the digest back " <>
            "as the tuist-checksum-sha256 header on downloads."
      }
    },
    required: [:parts]
  })
end
