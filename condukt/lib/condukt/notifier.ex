defmodule Condukt.Notifier do
  @moduledoc """
  Publishes session events somewhere other than the caller that asked for them.

  `Condukt.Session.stream/3` delivers events to the process that subscribed, one
  message per subscriber, held in the session's own state. That is the right
  shape for a caller streaming its own run and the wrong one for several people
  watching the same session: the list lives in one process on one node, so it
  cannot reach a viewer that connected to a different one.

  A notifier is the seam for that. It receives every event the session
  broadcasts, alongside the direct subscribers rather than instead of them, so
  adding one changes nothing for existing callers.

      # Anything implementing the behaviour
      Condukt.run(MyApp.Agent, "hello", notifier: MyApp.Fanout)

      # Or with options, which are passed back on every call
      Condukt.run(MyApp.Agent, "hello", notifier: {MyApp.Fanout, topic_prefix: "runs"})

  Phoenix.PubSub is the common destination, and `Condukt.Notifiers.PubSub`
  implements it when that dependency is present.

  ## Implementing one

      defmodule MyApp.Fanout do
        @behaviour Condukt.Notifier

        @impl true
        def publish(session_id, event, _opts) do
          MyAppWeb.Endpoint.broadcast("session:" <> session_id, "event", event)
          :ok
        end
      end

  Publishing happens in the session's view process, which publishes events
  and view changes in one order. A slow notifier then delays what viewers see,
  not the session's turn. `Condukt.abort/1` and `Condukt.clear/1` still return
  only once the notifier has the events they published. An implementation
  still must not block: hand the event to something else and return.

  ## Changes to the view

  Events tell a viewer what happens from the moment it subscribes. A viewer
  that joins mid-turn or reconnects also needs what happened before, which
  `Condukt.Session.view/1` returns as a `Condukt.Session.View`, numbered by
  the last change it holds. Implement the optional `c:publish_change/5` to
  carry the numbered changes after it, so a viewer on another node can apply
  them in order and notice one it missed:

      @impl true
      def publish_change(session_id, epoch, seq, change, _opts) do
        MyAppWeb.Endpoint.broadcast("session:" <> session_id, "change", {epoch, seq, change})
        :ok
      end

  A notifier without it publishes events only, as before.
  """

  @callback publish(session_id :: String.t(), event :: term(), opts :: keyword()) :: :ok

  @callback publish_change(
              session_id :: String.t(),
              epoch :: pos_integer(),
              seq :: pos_integer(),
              change :: term(),
              opts :: keyword()
            ) :: :ok

  @optional_callbacks publish_change: 5

  @doc """
  Publishes one event through a notifier spec.

  A `nil` notifier is the default and does nothing, which is what keeps this
  free for callers that never configure one.
  """
  def publish(nil, _session_id, _event), do: :ok

  def publish({module, opts}, session_id, event) when is_atom(module) and is_list(opts) do
    module.publish(session_id, event, opts)
  end

  def publish(module, session_id, event) when is_atom(module) do
    module.publish(session_id, event, [])
  end

  @doc """
  Publishes one numbered view change through a notifier spec, when the
  notifier implements `c:publish_change/5`.
  """
  def publish_change(nil, _session_id, _epoch, _seq, _change), do: :ok

  def publish_change({module, opts}, session_id, epoch, seq, change) when is_atom(module) and is_list(opts) do
    if Code.ensure_loaded?(module) and function_exported?(module, :publish_change, 5) do
      module.publish_change(session_id, epoch, seq, change, opts)
    else
      :ok
    end
  end

  def publish_change(module, session_id, epoch, seq, change) when is_atom(module) do
    publish_change({module, []}, session_id, epoch, seq, change)
  end
end
