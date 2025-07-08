defmodule TuistWeb.API.Schemas.CommandEvent do
  @moduledoc """
  The schema for the command event response.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    description: "The schema for the command analytics event.",
    required: [:id, :name, :url],
    properties: %{
      id: %Schema{
        type: :number,
        description: "ID of the command event"
      },
      name: %Schema{
        type: :string,
        description: "Name of the command"
      },
      url: %Schema{
        type: :string,
        description: "URL to the command event"
      }
    }
  })
end
