defmodule LuftServerWeb.OrganizationsController do
  @moduledoc """
  The signed-in person's Tuist organizations. Tuist owns accounts and
  organizations; Luft reads and creates them through the Tuist API, so an
  organization made in Luft is the same one in Tuist and vice versa.
  """
  use LuftServerWeb, :controller

  alias LuftServer.Sessions
  alias LuftServer.Tuist.API
  alias LuftServerWeb.Plugs.Authenticate

  def index(conn, _params) do
    with_access_token(conn, fn token ->
      with {:ok, organizations} <- API.list_organizations(token) do
        json(conn, %{organizations: organizations})
      end
    end)
  end

  def create(conn, %{"name" => name}) when is_binary(name) do
    with_access_token(conn, fn token ->
      with {:ok, organization} <- API.create_organization(token, name) do
        conn |> put_status(:created) |> json(organization)
      end
    end)
  end

  def create(conn, _params),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: "name is required"})

  defp with_access_token(conn, fun) do
    result =
      with {:ok, token} <- Sessions.access_token(conn.assigns.session) do
        fun.(token)
      end

    case result do
      %Plug.Conn{} = conn ->
        conn

      {:error, reason} when reason in [:reauthenticate, :unauthorized] ->
        Authenticate.unauthorized(conn)

      {:error, {:invalid, message}} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: message})

      {:error, _reason} ->
        conn |> put_status(:bad_gateway) |> json(%{error: "tuist_unavailable"})
    end
  end
end
