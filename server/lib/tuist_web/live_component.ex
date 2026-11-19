defmodule TuistWeb.LiveComponent do
  @moduledoc false

  # CID events have their own lifecycle and do not run the parent's hooks.
  # Wrap every stateful component callback, including components with a custom
  # mount, without requiring each call site to forward authentication assigns.
  defmacro __before_compile__(env) do
    if Module.defines?(env.module, {:handle_event, 3}) do
      quote do
        defoverridable handle_event: 3

        def handle_event(event, params, socket) do
          case TuistWeb.Authentication.check_live_component_session(socket) do
            {:cont, socket} -> super(event, params, socket)
            {:halt, socket} -> {:noreply, socket}
          end
        end
      end
    end
  end
end
