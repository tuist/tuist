defmodule LuftServerWeb.AISubscriptionsController do
  @moduledoc """
  The person's AI subscriptions (`LuftServer.AISubscriptions`). Paths, bodies
  and statuses match the API Tuist used to serve, so clients are unchanged.
  Responses are metadata only and never cached; no credential is returned.
  Every change that succeeds goes out to the person's open `ai_subscriptions`
  channels, so their other devices show it at once.
  """
  use LuftServerWeb, :controller

  alias LuftServer.AISubscriptions

  @providers %{"claude" => :claude, "chatgpt" => :chatgpt}

  def index(conn, _params) do
    case AISubscriptions.list(conn.assigns.session) do
      {:ok, subscriptions} -> json(conn, %{subscriptions: subscriptions})
      {:error, reason} -> error(conn, reason)
    end
  end

  def connect_claude(conn, %{"token" => token}) when is_binary(token) do
    case AISubscriptions.connect_claude(conn.assigns.session, token) do
      :ok -> changed(conn)
      {:error, reason} -> error(conn, reason)
    end
  end

  def connect_claude(conn, _params), do: error(conn, :invalid_claude_token)

  def start_chatgpt_login(conn, _params) do
    case AISubscriptions.start_chatgpt(conn.assigns.session) do
      {:ok, login} -> json(conn, login)
      {:error, reason} -> error(conn, reason)
    end
  end

  def poll_chatgpt_login(conn, %{"login_id" => login_id}) when is_binary(login_id) do
    case AISubscriptions.poll_chatgpt(conn.assigns.session, login_id) do
      {:ok, :connected} ->
        AISubscriptions.broadcast(conn.assigns.session)
        json(conn, %{status: :connected})

      {:ok, status} ->
        json(conn, %{status: status})

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def poll_chatgpt_login(conn, _params), do: invalid(conn)

  def cancel_chatgpt_login(conn, %{"login_id" => login_id}) when is_binary(login_id) do
    case AISubscriptions.cancel_chatgpt(conn.assigns.session, login_id) do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> error(conn, reason)
    end
  end

  def cancel_chatgpt_login(conn, _params), do: invalid(conn)

  def delete(conn, %{"provider" => provider}) when is_map_key(@providers, provider) do
    case AISubscriptions.disconnect(conn.assigns.session, Map.fetch!(@providers, provider)) do
      :ok -> changed(conn)
      {:error, reason} -> error(conn, reason)
    end
  end

  def delete(conn, _params), do: error(conn, :not_found)

  defp changed(conn) do
    case AISubscriptions.broadcast(conn.assigns.session) do
      {:ok, subscriptions} -> json(conn, %{subscriptions: subscriptions})
      {:error, reason} -> error(conn, reason)
    end
  end

  defp invalid(conn),
    do: conn |> put_status(:unprocessable_entity) |> json(%{message: "Invalid request."})

  defp error(conn, reason) do
    {status, message} = error_response(reason)
    conn |> put_status(status) |> json(%{message: message})
  end

  defp error_response(:not_found), do: {:not_found, "Not found."}

  defp error_response(:invalid_claude_token),
    do: {:unprocessable_entity, "Provide the subscription token that claude setup-token prints."}

  defp error_response(:rate_limited),
    do: {:too_many_requests, "Too many ChatGPT sign-in attempts. Try again in a few minutes."}

  defp error_response(:login_expired),
    do: {:gone, "The ChatGPT sign-in expired. Start a new one."}

  defp error_response(:chatgpt_not_configured),
    do: {:service_unavailable, "ChatGPT sign-in is not configured on this server."}

  defp error_response(:storage_unavailable),
    do: {:service_unavailable, "The subscription could not be saved. Try again."}

  defp error_response(:chatgpt_login_failed),
    do: {:bad_gateway, "OpenAI rejected the ChatGPT sign-in. Start a new one."}

  defp error_response(_reason),
    do: {:bad_gateway, "OpenAI could not be reached. Try again later."}
end
