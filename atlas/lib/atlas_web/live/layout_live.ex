defmodule AtlasWeb.LayoutLive do
  @moduledoc """
  Assigns shared data for dashboard LiveViews and requires an authenticated user.
  """

  use AtlasWeb, :live_view

  alias Atlas.Accounts
  alias Atlas.Audit
  alias Atlas.Users

  @search_palette_result_limit 10

  def on_mount(:default, _params, session, socket) do
    mount_authenticated(session, socket)
  end

  def on_mount(:admin, _params, session, socket) do
    mount_authenticated(session, socket, require_executive?: true)
  end

  def on_mount(:executive, _params, session, socket) do
    mount_authenticated(session, socket, require_executive?: true)
  end

  defp load_user(%{"user_id" => user_id}) when is_binary(user_id), do: Users.get_user(user_id)
  defp load_user(_session), do: nil

  defp mount_authenticated(session, socket, opts \\ []) do
    case load_user(session) do
      nil ->
        {:halt, redirect(socket, to: ~p"/login")}

      user ->
        if Keyword.get(opts, :require_executive?, false) and not Users.executive?(user) do
          {:halt,
           socket
           |> put_flash(:error, gettext("You do not have access to that page."))
           |> redirect(to: ~p"/commercial/sales")}
        else
          {:cont, socket |> assign_user(user) |> assign_search_palette()}
        end
    end
  end

  defp assign_user(socket, user) do
    Audit.put_context(%{actor: user, interface: "dashboard"})

    socket
    |> assign(:current_user, user)
    |> assign(:current_path, "/")
    |> assign(:favicon_href, default_favicon_href())
    |> push_event("set-favicon", %{href: default_favicon_href()})
    |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
      %{path: current_path} = URI.parse(url)
      {:cont, assign(socket, :current_path, current_path)}
    end)
  end

  defp assign_search_palette(socket) do
    socket
    |> assign(:search_palette_query, "")
    |> assign(:search_palette_accounts, [])
    |> assign(:search_palette_form, to_form(%{"query" => ""}, as: :search_palette))
    |> attach_hook(:search_palette, :handle_event, &handle_search_palette_event/3)
  end

  defp handle_search_palette_event("search_palette_search", %{"search_palette" => %{"query" => query}}, socket) do
    accounts =
      case String.trim(query) do
        "" ->
          []

        trimmed ->
          [query: trimmed]
          |> Accounts.list_accounts()
          |> Enum.take(@search_palette_result_limit)
      end

    {:halt,
     socket
     |> assign(:search_palette_query, query)
     |> assign(:search_palette_accounts, accounts)
     |> assign(:search_palette_form, to_form(%{"query" => query}, as: :search_palette))}
  end

  defp handle_search_palette_event(_event, _params, socket), do: {:cont, socket}

  def default_favicon_href, do: ~p"/favicon-32x32.png"
end
