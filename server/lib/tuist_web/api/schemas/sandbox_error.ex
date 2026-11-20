defmodule TuistWeb.API.Schemas.SandboxError do
  @moduledoc """
  The error body of the sandbox API: the shared error's `message` plus the
  stable `code` from `Tuist.Sandboxes.Query.error/1`. A separate schema, so
  other endpoints' error bodies keep their shape.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    properties: %{
      message: %Schema{type: :string, description: "The error message"},
      code: %Schema{
        type: :string,
        description:
          "A stable, machine-readable error code, such as `fleet_busy` or `account_limit`. Branch on it rather than on the message, which may change. Errors from before the sandbox code ran, such as authorization, have none."
      }
    },
    required: [:message]
  })
end
