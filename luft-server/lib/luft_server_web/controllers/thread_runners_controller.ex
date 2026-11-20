defmodule LuftServerWeb.ThreadRunnersController do
  @moduledoc "The signed-in person's machines, independent of account membership."
  use LuftServerWeb, :controller

  alias LuftServer.Sessions
  alias LuftServer.Sessions.Session
  alias LuftServer.Threads.Runners
  alias LuftServerWeb.Plugs.Authenticate

  plug :require_session

  def index(conn, _params) do
    json(conn, %{
      runners: conn.assigns.session |> Runners.list() |> Enum.map(&Runners.serialize/1)
    })
  end

  def create(conn, _params) do
    case Runners.register(conn.assigns.session, conn.body_params) do
      {:ok, runner, token} ->
        conn |> put_status(:created) |> json(Map.put(Runners.serialize(runner), :token, token))

      {:error, :too_many} ->
        conn
        |> put_status(:conflict)
        |> json(%{message: "Remove a runner before adding another."})

      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Name the runner and its platform: macos, linux or windows."})
    end
  end

  def delete(conn, %{"id" => id}) do
    case Runners.revoke(conn.assigns.session, id) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, _} -> conn |> put_status(:not_found) |> json(%{message: "Not found."})
    end
  end

  defp require_session(conn, _opts) do
    with %Session{id: id} <- conn.assigns[:session],
         %Session{} = session <- Sessions.get_by_id(id),
         false <- Map.has_key?(conn.assigns, :runner_token) do
      assign(conn, :session, session)
    else
      _ -> Authenticate.unauthorized(conn)
    end
  end
end
