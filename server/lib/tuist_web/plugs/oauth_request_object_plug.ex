defmodule TuistWeb.Plugs.OAuthRequestObjectPlug do
  @moduledoc """
  Rejects OAuth requests that carry a request object (`request` or
  `request_uri`, RFC 9101).

  Boruta resolves request objects before it authenticates the client or
  validates the grant, and merges their claims under the request's own
  parameters without checking a signature:

    * an http(s) `request_uri` is fetched from the server, so anonymous
      callers could make it send requests to addresses they choose;
    * an unsigned `request` JWT can supply parameters such as `grant_type`
      that the controllers never see, so a refresh carried in one skips
      the SSO check in `TuistWeb.Oauth.TokenController`.

  Tuist neither supports request objects nor exposes a pushed authorization
  request endpoint, so neither parameter can be valid. Boruta reads the
  query string before the body, so both are checked.
  """

  @behaviour Plug

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn

  @parameters ["request", "request_uri"]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Enum.find(@parameters, &(Map.has_key?(conn.query_params, &1) or Map.has_key?(conn.body_params, &1))) do
      nil ->
        conn

      parameter ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_status(:bad_request)
        |> json(%{
          error: "#{parameter}_not_supported",
          error_description: "The #{parameter} parameter is not supported."
        })
        |> halt()
    end
  end
end
