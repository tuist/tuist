defmodule AtlasWeb.EnvironmentsController do
  use AtlasWeb, :controller

  alias Atlas.Environments
  alias Atlas.Environments.Commands
  alias AtlasWeb.Plugs.NativeOAuthClient

  plug NativeOAuthClient when action != :index

  def action(conn, _opts) do
    if Atlas.Demo.enabled?() do
      error(conn, :not_found)
    else
      apply(__MODULE__, action_name(conn), [conn, conn.params])
    end
  end

  def index(conn, _params), do: json(conn, Environments.list(conn.assigns.current_user))

  def update(conn, %{"id" => id}) do
    case Environments.register(conn.assigns.current_user, conn.assigns.oauth_client_id, id, conn.body_params) do
      {:ok, environment} -> json(conn, %{environment: Environments.serialize(environment)})
      {:error, reason} -> error(conn, reason)
    end
  end

  def delete(conn, %{"id" => id}) do
    respond(conn, Environments.disable(conn.assigns.current_user, conn.assigns.oauth_client_id, id))
  end

  def commands(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    client = conn.assigns.oauth_client_id

    with {:ok, _environment} <- Environments.renew(user, client, id, Ecto.UUID.generate()),
         {:ok, commands} <- Commands.queued(user, client, id) do
      json(conn, %{commands: commands})
    else
      {:error, reason} -> error(conn, reason)
      _ -> error(conn, :invalid_params)
    end
  end

  def claim(conn, %{"id" => id, "command_id" => command_id}) do
    respond(
      conn,
      Commands.claim(conn.assigns.current_user, conn.assigns.oauth_client_id, id, command_id, conn.body_params)
    )
  end

  def result(conn, %{"id" => id, "command_id" => command_id}) do
    respond(
      conn,
      Commands.complete(conn.assigns.current_user, conn.assigns.oauth_client_id, id, command_id, conn.body_params)
    )
  end

  def progress(conn, %{"id" => id, "command_id" => command_id}) do
    respond(
      conn,
      Commands.progress(conn.assigns.current_user, conn.assigns.oauth_client_id, id, command_id, conn.body_params)
    )
  end

  defp respond(conn, {:ok, payload}), do: json(conn, payload)
  defp respond(conn, {:error, reason}), do: error(conn, reason)
  defp respond(conn, _result), do: error(conn, :invalid_params)

  defp error(conn, reason) do
    status =
      case reason do
        :not_found -> :not_found
        :invalid_params -> :unprocessable_entity
        _ -> :conflict
      end

    conn |> put_status(status) |> json(%{error: Atom.to_string(reason)})
  end
end
