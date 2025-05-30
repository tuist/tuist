defmodule Tuist.PubSub do
  @moduledoc """
  The main PubSub module.
  """

  def subscribe(channel), do: Phoenix.PubSub.subscribe(Tuist.PubSub, channel)

  def broadcast(payload, channel, event) do
    Phoenix.PubSub.broadcast(
      Tuist.PubSub,
      channel,
      {event, payload}
    )

    {:ok, payload}
  end
end
