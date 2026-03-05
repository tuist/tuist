defmodule TuistWeb.DocsLive do
  @moduledoc false
  use TuistWeb, :live_view

  alias Tuist.Docs
  alias Tuist.Docs.Redirects
  alias TuistWeb.Errors.NotFoundError

  def mount(_params, _session, socket) do
    socket =
      attach_hook(socket, :assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
        {:cont, assign(socket, current_path: current_path)}
      end)

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    path = build_path(params)

    case Redirects.redirect_path(path) do
      nil ->
        case Docs.get_page(path) do
          nil ->
            raise NotFoundError, dgettext("errors", "Page not found")

          page ->
            head_title =
              case page.title_template do
                nil -> "#{page.title} · Docs · Tuist"
                template -> String.replace(template, ":title", page.title)
              end

            {:noreply,
             socket
             |> assign(:page, page)
             |> assign(:head_title, head_title)
             |> assign(:head_description, page.description)}
        end

      destination ->
        query_string = URI.parse(socket.assigns.current_path).query
        target = if query_string, do: "/docs#{destination}?#{query_string}", else: "/docs#{destination}"
        {:noreply, redirect(socket, to: target)}
    end
  end

  def render(assigns) do
    ~H"""
    <TuistWeb.Docs.Components.layout
      current_slug={@page.slug}
      tab={Tuist.Docs.Sidebar.tab_for_slug(@page.slug)}
      headings={@page.headings}
      markdown={@page.markdown}
    >
      <article id={"docs-body-#{@page.slug}"} data-part="docs-body" data-prose phx-hook="DocsContent">
        {raw(@page.body)}
      </article>
    </TuistWeb.Docs.Components.layout>
    """
  end

  def handle_event("copy-page-markdown", _params, socket) do
    {:noreply, push_event(socket, "docs:copy-to-clipboard", %{text: socket.assigns.page.markdown})}
  end

  defp build_path(%{"path" => path_parts}), do: "/en/" <> Enum.join(path_parts, "/")
  defp build_path(_params), do: "/en"
end
