defmodule LuftServer.Lounges.Presence do
  @moduledoc "Ephemeral, account-scoped presence shared through Luft's PubSub."
  use Phoenix.Presence, otp_app: :luft_server, pubsub_server: LuftServer.PubSub

  def topic(scope), do: "lounges_presence:#{scope.account_id}"

  def online(scope) do
    scope |> topic() |> list() |> Map.keys() |> MapSet.new(&String.to_integer/1)
  end
end
