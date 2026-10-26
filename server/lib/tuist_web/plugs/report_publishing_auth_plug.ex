defmodule TuistWeb.Plugs.ReportPublishingAuthPlug do
  @moduledoc """
  Optional authentication for the dedicated structured report-creation routes. An
  invalid supplied credential must never become a network-trusted publisher.
  """
  use TuistWeb, :controller

  alias Tuist.Environment
  alias TuistWeb.Authentication
  alias TuistWeb.AuthenticationPlug

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      [] ->
        if Authentication.authenticated?(conn) or Environment.network_trusted_report_publishing_enabled?() do
          conn
        else
          reject(conn)
        end

      [header] ->
        conn = %{conn | assigns: Map.drop(conn.assigns, [:current_user, :current_project, :current_subject])}

        authenticate(conn, header)

      _ ->
        reject(conn)
    end
  end

  defp authenticate(conn, "Bearer " <> token) when token != "" do
    if token == String.trim(token) do
      conn = AuthenticationPlug.call(conn, :load_authenticated_subject)
      if Authentication.authenticated?(conn), do: conn, else: reject(conn)
    else
      reject(conn)
    end
  end

  defp authenticate(conn, _header), do: reject(conn)

  defp reject(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{message: "You need valid credentials to publish this report."})
    |> halt()
  end
end
