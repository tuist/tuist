defmodule AtlasWeb.Plugs.NativeOAuthClient do
  @moduledoc """
  Restricts a bearer-authenticated route to tokens issued to the native Atlas
  app's dynamically registered OAuth client, and assigns that client's ID as
  `:oauth_client_id`.

  Every app installation registers its own public client with exactly the
  native callback, and reuses it across sign-ins on that installation. Other MCP
  clients (for example a desktop assistant) cannot register push devices. This
  is a client-shape check, not device attestation. Must run after `MCPAuth`.
  """

  import Plug.Conn

  alias Atlas.OAuth.AccessTokens
  alias Boruta.Oauth.Client
  alias Boruta.Oauth.Token

  @native_redirect_uri "dev.tuist.atlas://oauth-callback"

  def init(opts), do: opts

  def call(conn, _opts) do
    with [header | _] <- get_req_header(conn, "authorization"),
         {:ok, value} <- bearer(header),
         %Token{client: %Client{id: client_id, redirect_uris: [@native_redirect_uri]}} <-
           AccessTokens.get_by(value: value) do
      assign(conn, :oauth_client_id, client_id)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, JSON.encode!(%{error: "native_client_required"}))
        |> halt()
    end
  end

  defp bearer("Bearer " <> value), do: {:ok, value}
  defp bearer("bearer " <> value), do: {:ok, value}
  defp bearer(_header), do: :error
end
