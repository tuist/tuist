defmodule TuistWeb.Marketing.DocsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Docs
  alias Tuist.Docs.Sidebar

  on_mount {TuistWeb.Authentication, :mount_current_user}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"slug" => slug_parts}, _url, socket) do
    slug = "/docs/" <> Enum.join(slug_parts, "/")
    render_doc(socket, slug)
  end

  def handle_params(_params, _url, socket) do
    render_doc(socket, "/docs/index")
  end

  defp render_doc(socket, slug) do
    case Docs.get_doc_by_slug(slug) do
      nil ->
        {:noreply, push_navigate(socket, to: "/")}

      doc ->
        sidebar = Sidebar.sidebar_for_slug(slug)
        headings = extract_headings(doc.body)

        socket =
          socket
          |> assign(:doc, doc)
          |> assign(:sidebar, sidebar)
          |> assign(:current_slug, slug)
          |> assign(:headings, headings)
          |> assign(:head_title, doc.title || "Documentation")
          |> assign(:head_description, doc.description || "Tuist documentation")

        {:noreply, socket}
    end
  end

  defp extract_headings(html) do
    ~r/<(h[23])[^>]*id="([^"]*)"[^>]*>(.*?)<\/\1>/s
    |> Regex.scan(html)
    |> Enum.map(fn [_, _tag, id, text] ->
      clean_text = String.replace(text, ~r/<[^>]+>/, "")
      %{id: id, text: clean_text}
    end)
  end
end
