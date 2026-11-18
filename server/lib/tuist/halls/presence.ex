defmodule Tuist.Halls.Presence do
  @moduledoc """
  Which members of an organization have Tuist Guild open. Each connected
  client's `TuistWeb.PresenceChannel` tracks its user on the organization's
  topic, so every web replica sees every connection through the cluster's
  PubSub. It is ephemeral: a replica that stops takes its connections with it,
  and nothing is stored.
  """
  use Phoenix.Presence, otp_app: :tuist, pubsub_server: Tuist.PubSub

  # Not `presence:<id>`: clients join `presence:<handle>`, handles can be all
  # digits, and every channel receives broadcasts on its own topic, so an
  # organization named after another's ID would receive its diffs.
  def topic(account), do: "halls_presence:#{account.id}"

  @doc "The user IDs connected to the account's topic on any replica."
  def online(account) do
    account |> topic() |> list() |> Map.keys() |> MapSet.new(&String.to_integer/1)
  end
end
