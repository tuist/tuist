defmodule TuistWeb.API.Responses do
  @moduledoc """
  Reusable OpenAPI responses shared across API controllers.
  """

  alias OpenApiSpex.Header
  alias OpenApiSpex.MediaType
  alias OpenApiSpex.Response
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Error

  @authorization_throttled %Response{
    description: "You've made too many unauthorized requests.",
    headers: %{
      "retry-after" => %Header{
        description: "Whole seconds to wait before retrying.",
        schema: %Schema{type: :string}
      },
      "x-tuist-throttle-reason" => %Header{
        description:
          "Set to `authorization` when the throttling is a response to the volume of unauthorized requests. Waiting out `retry-after` reaches the same denial.",
        schema: %Schema{type: :string}
      }
    },
    content: %{
      "application/json" => %MediaType{schema: Error}
    }
  }

  @app_writes_throttled %Response{
    description: "Too many changes from this user. Retry after the `retry-after` interval.",
    headers: %{
      "retry-after" => %Header{
        description: "Whole seconds to wait before retrying.",
        schema: %Schema{type: :string}
      }
    },
    content: %{
      "application/json" => %MediaType{schema: Error}
    }
  }

  def authorization_throttled, do: @authorization_throttled

  def app_writes_throttled, do: @app_writes_throttled
end
