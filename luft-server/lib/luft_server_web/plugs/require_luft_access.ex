defmodule LuftServerWeb.Plugs.RequireLuftAccess do
  @moduledoc """
  Admits a request for the person's own data only while Tuist still lets them
  use Luft: their account is active and has Luft enabled. Tuist answers that
  through the personal account's context (`LuftServer.Tuist.Scope`), on every
  request, so deactivation or losing access applies at once.

  Requests naming an `account_handle` load that account's scope themselves,
  so they pass through.
  """
  @behaviour Plug

  import Plug.Conn

  alias LuftServer.Tuist.Scope

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_params: %{"account_handle" => _}} = conn, _opts), do: conn

  def call(conn, _opts) do
    session = conn.assigns.session

    case Scope.load(session, session.handle || "") do
      {:ok, _scope} ->
        conn

      {:error, :unauthorized} ->
        deny(conn, :unauthorized, "Sign in again.")

      {:error, :not_found} ->
        deny(conn, :forbidden, "Luft is not available for this account.")

      {:error, _reason} ->
        deny(conn, :service_unavailable, "Tuist could not be reached. Try again.")
    end
  end

  defp deny(conn, status, message) do
    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{message: message})
    |> halt()
  end
end
