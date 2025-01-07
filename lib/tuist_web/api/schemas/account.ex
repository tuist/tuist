defmodule TuistWeb.API.Schemas.Account do
  @moduledoc """
  The schema for the account response.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    type: :object,
    required: [:id, :handle],
    properties: %{
      id: %Schema{
        type: :number,
        description: "ID of the account"
      },
      handle: %Schema{
        type: :string,
        description: "The handle of the account"
      }
    }
  })
end
