defmodule TuistWeb.API.Schemas.Shards.ShardPlan do
  @moduledoc false
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ShardPlan",
    type: :object,
    description: "A shard plan with assignment details.",
    properties: %{
      id: %Schema{
        type: :string,
        format: :uuid,
        description: "The shard plan id."
      },
      reference: %Schema{
        type: :string,
        description: "A unique shard plan reference, typically derived from CI environment."
      },
      shard_count: %Schema{
        type: :integer,
        description: "The number of shards."
      },
      shards: %Schema{
        type: :array,
        description: "The shard assignments.",
        items: %Schema{
          type: :object,
          properties: %{
            index: %Schema{type: :integer, description: "The zero-based shard index."},
            test_targets: %Schema{
              type: :array,
              items: %Schema{type: :string},
              description: "The test targets assigned to this shard."
            },
            estimated_duration_ms: %Schema{
              type: :integer,
              description: "The estimated duration in milliseconds."
            }
          },
          required: [:index, :test_targets, :estimated_duration_ms]
        }
      }
    },
    required: [:id, :reference, :shard_count, :shards]
  })
end
