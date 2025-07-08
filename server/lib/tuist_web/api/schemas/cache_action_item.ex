defmodule TuistWeb.API.Schemas.CacheActionItem do
  @moduledoc """
  A schema for a cache action item.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CacheActionItem",
    description: "Represents an action item stored in the cache.",
    type: :object,
    properties: %{
      hash: %Schema{
        type: :string,
        description: "The hash that uniquely identifies the artifact in the cache."
      }
    },
    required: [:hash]
  })
end
