defmodule TuistWeb.Plugs.CacheEndpointAuthPlug do
  @moduledoc """
  Allows credential-free cache endpoint discovery only on opted-in self-hosted instances.
  Supplied credentials still require ordinary authentication.
  """
  use TuistWeb, :controller

  alias Tuist.Environment
  alias TuistWeb.Authentication
  alias TuistWeb.AuthenticationPlug

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      [] ->
        if Authentication.authenticated?(conn) or Environment.network_trusted_cache_access_enabled?(),
          do: conn,
          else: reject(conn)

      ["Bearer " <> token] when token != "" ->
        if token == String.trim(token) do
          conn = %{conn | assigns: Map.drop(conn.assigns, [:current_user, :current_project, :current_subject])}

          conn
          |> AuthenticationPlug.call(:load_authenticated_subject)
          |> AuthenticationPlug.call({:require_authentication, response_type: :open_api})
        else
          reject(conn)
        end

      _ ->
        reject(conn)
    end
  end

  defp reject(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{message: "You need valid credentials to discover the cache endpoint."})
    |> halt()
  end
end
