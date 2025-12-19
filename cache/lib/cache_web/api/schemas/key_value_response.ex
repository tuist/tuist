defmodule CacheWeb.API.Schemas.KeyValueResponse do
  @moduledoc false
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "KeyValueResponse",
    type: :object,
    properties: %{
      entries: %Schema{
        type: :array,
        description: "The list of key-value entries",
        items: %Schema{
          type: :object,
          properties: %{
            value: %Schema{type: :string, description: "The value"}
          },
          required: [:value]
        }
      }
    },
    required: [:entries]
  })
end
