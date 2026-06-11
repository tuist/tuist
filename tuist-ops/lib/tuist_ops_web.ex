defmodule TuistOpsWeb do
  @moduledoc """
  HTTP surface for tuist-ops. Two kinds of endpoints:

    * JSON / webhooks — the Slack webhooks and the Pomerium impersonation
      policy endpoint.
    * HTML — the operator-facing pages (the project-access reason form and
      the audit trail), rendered with the Noora design system so they
      match the rest of the Tuist ops surface.
  """

  def static_paths, do: ~w(assets)

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: TuistOpsWeb.Layouts]

      import Plug.Conn
      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component
      use Noora

      unquote(verified_routes())
    end
  end

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: TuistOpsWeb.Endpoint,
        router: TuistOpsWeb.Router,
        statics: TuistOpsWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/router/html.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
