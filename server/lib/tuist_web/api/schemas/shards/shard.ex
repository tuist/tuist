defmodule TuistWeb.API.Schemas.Shards.Shard do
  @moduledoc false
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "Shard",
    type: :object,
    description: "A shard with its assigned modules, suites, and download URLs.",
    properties: %{
      shard_plan_id: %Schema{
        type: :string,
        format: :uuid,
        description: "The UUID of the shard plan."
      },
      modules: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "The test modules assigned to this shard."
      },
      suites: %Schema{
        type: :object,
        additionalProperties: %Schema{
          type: :array,
          items: %Schema{type: :string}
        },
        description: "The test suites assigned to this shard, grouped by module name."
      },
      download_url: %Schema{
        type: :string,
        description: "Presigned URL to download the shared test products bundle."
      }
    },
    required: [:shard_plan_id, :modules, :suites, :download_url]
  })
end
