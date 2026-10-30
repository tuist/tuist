defmodule AtlasWeb.NativeEnvironmentCommandsController do
  use AtlasWeb, :controller

  alias Atlas.Environments.Commands
  alias AtlasWeb.Plugs.NativeOAuthClient

  plug NativeOAuthClient when action == :cancel

  def action(conn, _opts) do
    if Atlas.Demo.enabled?() do
      respond(conn, {:error, :not_found})
    else
      apply(__MODULE__, action_name(conn), [conn, conn.params])
    end
  end

  def index(conn, %{"thread_id" => id}) do
    respond(conn, Commands.list(conn.assigns.current_user, id))
  end

  def cancel(conn, %{"thread_id" => id, "command_id" => command_id}) do
    respond(conn, Commands.cancel(conn.assigns.current_user, id, command_id, conn.body_params))
  end

  defp respond(conn, {:ok, payload}), do: json(conn, payload)

  defp respond(conn, {:error, reason}) do
    status =
      case reason do
        :not_found -> :not_found
        :invalid_params -> :unprocessable_entity
        _ -> :conflict
      end

    conn |> put_status(status) |> json(%{error: Atom.to_string(reason)})
  end
end
