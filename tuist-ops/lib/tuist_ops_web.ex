defmodule TuistOpsWeb do
  @moduledoc """
  HTTP surface for the JIT service. No HTML / LiveView — this is a
  webhooks + JSON API app (Slack on one side, the impersonation policy endpoint on the
  other).
  """

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
    end
  end

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/router.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
