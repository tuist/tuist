defmodule TuistWeb.API.Schemas.Shards.ShardAssignment do
  @moduledoc false
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ShardAssignment",
    type: :object,
    description: "The assignment for a specific shard.",
    properties: %{
      test_targets: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "The test targets assigned to this shard."
      },
      xctestrun_download_url: %Schema{
        type: :string,
        description: "Presigned URL to download the filtered .xctestrun for this shard."
      },
      bundle_download_url: %Schema{
        type: :string,
        description: "Presigned URL to download the shared test products bundle."
      }
    },
    required: [:test_targets, :xctestrun_download_url, :bundle_download_url]
  })
end
