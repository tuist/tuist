defmodule TuistWeb.API.Schemas.AuthenticationTokens do
  @moduledoc """
  The schema for the API authentication tokens.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "AuthenticationTokens",
    description:
      "A pair of access token to authenticate requests and refresh token to generate new access tokens when they expire.",
    type: :object,
    properties: %{
      access_token: %Schema{
        type: :string,
        description: "API access token."
      },
      refresh_token: %Schema{
        type: :string,
        description: "A token to generate new API access tokens when they expire."
      }
    },
    required: [:access_token, :refresh_token]
  })
end
