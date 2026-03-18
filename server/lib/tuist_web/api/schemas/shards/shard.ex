defmodule TuistWeb.API.Schemas.Shards.Shard do
  @moduledoc false
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "Shard",
    type: :object,
    description: "A shard with its assigned test targets and download URLs.",
    properties: %{
      test_targets: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "The test targets assigned to this shard."
      },
      bundle_download_url: %Schema{
        type: :string,
        description: "Presigned URL to download the shared test products bundle."
      }
    },
    required: [:test_targets, :bundle_download_url]
  })
end
