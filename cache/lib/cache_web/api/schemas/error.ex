defmodule CacheWeb.API.Schemas.Error do
  @moduledoc false
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "Error",
    type: :object,
    properties: %{
      message: %Schema{type: :string, description: "The error message"}
    },
    required: [:message]
  })
end
