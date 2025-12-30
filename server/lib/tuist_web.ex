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

  alias Plug.Conn
  alias TuistWeb.Controller

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt js css .well-known marketing app apidocs)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Phoenix.Controller
      import Phoenix.LiveView.Router

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
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

      use Gettext, backend: TuistWeb.Gettext

      def action(conn, _) do
        case apply(__MODULE__, action_name(conn), [conn, conn.params]) do
          %Conn{} = conn ->
            conn

          {:ok, conn} ->
            conn

          {:error, reason} ->
            Controller.handle_error(conn, reason)
        end
      end

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView
      use Gettext, backend: TuistWeb.Gettext

      import TuistWeb.AppLayoutComponents

      on_mount(TuistWeb.CSP)
      on_mount({TuistWeb.Timezone, :assign_timezone})

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

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      import TuistWeb.CSP,
        only: [get_csp_nonce: 0]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use Gettext, backend: TuistWeb.Gettext
      # HTML escaping functionality
      import Phoenix.HTML
      import TuistWeb.AppAuthComponents
      # Core UI components and translation
      import TuistWeb.AppComponents
      import TuistWeb.Components.IconComponents
      import TuistWeb.Widget

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
