defmodule Tuist.OAuth2.AuthCodeBasicAuth do
  @moduledoc """
  OAuth2 Authorization Code strategy that authenticates the client using
  HTTP Basic Auth only and never includes the client credentials in the
  token request body.

  The default `OAuth2.Strategy.AuthCode` puts `client_id` in the request body
  and also adds the Authorization header. RFC 6749 §2.3.1 forbids supplying
  credentials in more than one location, and stricter providers (notably
  Okta) reject the request with `invalid_request` when both are present.
  """

  use OAuth2.Strategy

  @impl true
  def authorize_url(client, params) do
    client
    |> put_param(:response_type, "code")
    |> put_param(:client_id, client.client_id)
    |> put_param(:redirect_uri, client.redirect_uri)
    |> merge_params(params)
  end

  @impl true
  def get_token(client, params, headers) do
    {code, params} = Keyword.pop(params, :code, client.params["code"])

    if !code do
      raise OAuth2.Error, reason: "Missing required key `code` for #{inspect(__MODULE__)}"
    end

    client
    |> put_param(:code, code)
    |> put_param(:grant_type, "authorization_code")
    |> put_param(:redirect_uri, client.redirect_uri)
    |> merge_params(params)
    |> basic_auth()
    |> put_headers(headers)
  end
end
