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

  Numbered view changes go to a topic of their own, so subscribers of the
  event topic receive nothing new. They arrive as
  `{:condukt_change, session_id, epoch, seq, change}`, the same message
  `Condukt.Session.watch/1` sends locally. Subscribe first, then fetch the
  view, and apply each change with `Condukt.Session.View.advance/4`:

      Phoenix.PubSub.subscribe(MyApp.PubSub, Condukt.Notifiers.PubSub.changes_topic(session_id))
      view = Condukt.Session.view(session)

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

  @doc "The topic a session publishes its numbered view changes on."
  def changes_topic(session_id, prefix \\ @default_prefix), do: topic(session_id, prefix) <> ":changes"

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

  @impl Condukt.Notifier
  def publish_change(session_id, epoch, seq, change, opts) do
    server = Keyword.fetch!(opts, :server)
    prefix = Keyword.get(opts, :prefix, @default_prefix)

    Phoenix.PubSub.broadcast(
      server,
      changes_topic(session_id, prefix),
      {:condukt_change, session_id, epoch, seq, change}
    )
  end
end
