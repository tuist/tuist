defmodule LuftServerWeb.AISubscriptionsController do
  @moduledoc """
  The person's AI subscriptions (`LuftServer.AISubscriptions`), with the same
  paths, bodies and statuses as Tuist's `/api/me/ai-subscriptions`. Every
  change that succeeds goes out to the person's open `ai_subscriptions`
  channels, so their other devices show it at once.
  """
  use LuftServerWeb, :controller

  alias LuftServer.AISubscriptions
  alias LuftServerWeb.Plugs.Authenticate

  def index(conn, _params), do: forward(conn, :get, "")

  def connect_claude(conn, %{"token" => token}) when is_binary(token),
    do: conn |> forward(:put, "/claude", json: %{token: token}) |> changed()

  def connect_claude(conn, _params), do: invalid(conn)

  def start_chatgpt_login(conn, _params), do: forward(conn, :post, "/chatgpt/login")

  def poll_chatgpt_login(conn, %{"login_id" => login_id}) when is_binary(login_id) do
    conn = forward(conn, :post, "/chatgpt/login/poll", json: %{login_id: login_id})

    # A sign-in that just connected changed the list, which the poll doesn't return.
    with %{status: 200, assigns: %{upstream: %{"status" => "connected"}}} <- conn,
         {:ok, subscriptions} <- AISubscriptions.list(conn.assigns.session) do
      AISubscriptions.broadcast(conn.assigns.session, subscriptions)
    end

    conn
  end

  def poll_chatgpt_login(conn, _params), do: invalid(conn)

  def cancel_chatgpt_login(conn, %{"login_id" => login_id}) when is_binary(login_id),
    do: forward(conn, :delete, "/chatgpt/login", params: [login_id: login_id])

  def cancel_chatgpt_login(conn, _params), do: invalid(conn)

  def delete(conn, %{"provider" => provider}) when provider in ["claude", "chatgpt"],
    do: conn |> forward(:delete, "/" <> provider) |> changed()

  def delete(conn, _params), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})

  defp forward(conn, method, path, opts \\ []) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case AISubscriptions.request(conn.assigns.session, method, path, opts) do
      {:ok, 204, _body} ->
        send_resp(conn, 204, "")

      {:ok, status, body} when is_map(body) ->
        conn |> assign(:upstream, body) |> put_status(status) |> json(body)

      {:error, :reauthenticate} ->
        Authenticate.unauthorized(conn)

      _ ->
        conn |> put_status(:bad_gateway) |> json(%{error: "tuist_unavailable"})
    end
  end

  defp changed(%{status: 200, assigns: %{upstream: body}} = conn) do
    with {:ok, subscriptions} <- AISubscriptions.subscriptions(body),
         do: AISubscriptions.broadcast(conn.assigns.session, subscriptions)

    conn
  end

  defp changed(conn), do: conn

  defp invalid(conn),
    do: conn |> put_status(:unprocessable_entity) |> json(%{message: "Invalid request."})
end
