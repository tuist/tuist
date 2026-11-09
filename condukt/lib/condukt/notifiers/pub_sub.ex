defmodule Condukt.Notifiers.PubSub do
  @moduledoc """
  Publishes session events over `Phoenix.PubSub`.

  This is how one session reaches many viewers, including viewers connected to
  other nodes: the session broadcasts once and PubSub delivers to everyone
  subscribed to its topic, wherever they are.

      Condukt.run(MyApp.Agent, "hello",
        notifier: {Condukt.Notifiers.PubSub, server: MyApp.PubSub}
      )

  Subscribers listen on the session's topic and receive
  `{:condukt_event, session_id, event}`:

      Phoenix.PubSub.subscribe(MyApp.PubSub, Condukt.Notifiers.PubSub.topic(session_id))

  ## Options

    * `:server` - the PubSub server name (required)
    * `:prefix` - topic prefix, `"condukt:session:"` by default

  Requires `:phoenix_pubsub`, which Condukt declares as optional so projects
  that fan out some other way do not carry it.
  """

  @behaviour Condukt.Notifier

  @default_prefix "condukt:session:"

  @doc "The topic a session publishes on."
  def topic(session_id, prefix \\ @default_prefix), do: prefix <> session_id

  @impl Condukt.Notifier
  def publish(session_id, event, opts) do
    server = Keyword.fetch!(opts, :server)
    prefix = Keyword.get(opts, :prefix, @default_prefix)

    Phoenix.PubSub.broadcast(
      server,
      topic(session_id, prefix),
      {:condukt_event, session_id, event}
    )
  end
end
