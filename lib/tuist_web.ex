defmodule TuistWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use TuistWeb, :controller
      use TuistWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """
  use Boundary, deps: [Tuist], exports: [Endpoint, Router]

  def static_paths,
    do: ~w(assets fonts images favicon.ico robots.txt js css .well-known marketing app)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
      import TuistWeb.CSP, only: [put_content_security_policy: 2]
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json, :xml],
        layouts: [html: TuistWeb.Layouts]

      import Plug.Conn
      use Gettext, backend: TuistWeb.Gettext

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView
      import TuistWeb.AppLayoutComponents
      use Gettext, backend: TuistWeb.Gettext

      on_mount(TuistWeb.CSP)

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def xml do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import TuistWeb.CSP,
        only: [get_csp_nonce: 0]

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      import TuistWeb.AppComponents
      import TuistWeb.HeadlessComponents
      import TuistWeb.AppAuthComponents
      import TuistWeb.Components.IconComponents
      import TuistWeb.AppCommandEventComponents
      use Gettext, backend: TuistWeb.Gettext

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: TuistWeb.Endpoint,
        router: TuistWeb.Router,
        statics: TuistWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
