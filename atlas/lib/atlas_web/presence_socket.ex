defmodule AtlasWeb.PresenceSocket do
  @moduledoc false
  use Phoenix.Socket

  alias Atlas.Demo
  alias Atlas.Guardian

  channel "presence:team", AtlasWeb.PresenceChannel
  channel "orbit:thread:*", AtlasWeb.OrbitThreadChannel
  channel "orbit:me", AtlasWeb.OrbitInboxChannel

  @impl true
  def connect(_params, socket, %{auth_token: token}) when is_binary(token) do
    with false <- Demo.enabled?(),
         {:ok, user, _claims} <- Guardian.resource_from_token(token) do
      {:ok, socket |> assign(:current_user, user) |> assign(:access_token, token)}
    else
      _ -> :error
    end
  end

  def connect(_params, _socket, _info), do: :error

  @impl true
  def id(socket), do: "presence:#{socket.assigns.current_user.id}"
end
