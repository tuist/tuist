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

  Publishing happens inside the session process, so an implementation must not
  block: hand the event to something else and return.
  """

  @callback publish(session_id :: String.t(), event :: term(), opts :: keyword()) :: :ok

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
end
