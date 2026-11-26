defmodule LuftServerWeb.ConversationsSocket do
  @moduledoc "Luft-owned realtime conversations, authenticated only by the native bearer subprotocol."
  use Phoenix.Socket

  alias LuftServer.NativeAuth

  channel "threads:*", LuftServerWeb.ThreadsChannel
  channel "presence:*", LuftServerWeb.PresenceChannel
  channel "ai_subscriptions", LuftServerWeb.AISubscriptionsChannel

  def connect(_params, socket, %{auth_token: bearer}) when is_binary(bearer) do
    case NativeAuth.resolve_bearer(bearer) do
      nil -> :error
      session -> {:ok, socket |> assign(:bearer, bearer) |> assign(:session, session)}
    end
  end

  def connect(_params, _socket, _info), do: :error

  def id(socket), do: "luft:session:#{socket.assigns.session.id}"

  def authenticate(socket) do
    case NativeAuth.resolve_bearer(socket.assigns.bearer) do
      %{id: id} = session when id == socket.assigns.session.id -> {:ok, session}
      _ -> {:error, :unauthorized}
    end
  end
end
