defmodule AtlasWeb.PagesLive.Show do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Ecto.Query

  alias Atlas.Engineering.Pages
  alias Atlas.Engineering.Pages.Deploy
  alias Atlas.Repo
  alias AtlasWeb.Plugs.PagesSubdomain

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Pages.get_page(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("pages", "Page not found."))
         |> push_navigate(to: ~p"/engineering/pages")}

      page ->
        deploys =
          Deploy
          |> where([d], d.page_id == ^page.id)
          |> order_by([d], desc: d.inserted_at)
          |> Repo.all()

        {:ok,
         socket
         |> assign(:page_title, page.slug)
         |> assign(:page, page)
         |> assign(:deploys, deploys)}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Pages.delete_page(socket.assigns.page, socket.assigns.current_user) do
      {:ok, _page} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("pages", "Site deleted."))
         |> push_navigate(to: ~p"/engineering/pages")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, dgettext("pages", "Could not delete: %{reason}", reason: inspect(reason)))}
    end
  end

  defp site_url(page) do
    host_suffix =
      Application.get_env(:atlas, PagesSubdomain, [])
      |> Keyword.get(:host_suffix, "atlas.tuist.dev")

    "https://#{page.slug}.#{host_suffix}/"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="page-show" data-part="page">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{@page.slug}.atlas.tuist.dev</h1>
          <p :if={@page.title}>{@page.title}</p>
          <p :if={@page.description}>{@page.description}</p>
        </div>
        <div data-part="header-actions">
          <a href={site_url(@page)} target="_blank" rel="noreferrer" data-part="open-button">
            {dgettext("pages", "Open site")}
          </a>
          <button
            type="button"
            phx-click="delete"
            data-confirm={
              dgettext("pages", "Delete this site and every deploy? This cannot be undone.")
            }
            data-part="delete-button"
          >
            {dgettext("pages", "Delete site")}
          </button>
        </div>
      </div>

      <div data-part="deploys">
        <h2>{dgettext("pages", "Deploys")}</h2>
        <ul :if={@deploys != []}>
          <li :for={deploy <- @deploys} data-part="deploy" data-state={deploy.state}>
            <div data-part="deploy-header">
              <span data-part="state">{deploy.state}</span>
              <span data-part="timestamp">{deploy.inserted_at}</span>
            </div>
            <div data-part="deploy-body">
              <span>{deploy.file_count} {dgettext("pages", "files")}</span>
              <span>{deploy.total_bytes} {dgettext("pages", "bytes")}</span>
            </div>
          </li>
        </ul>
        <p :if={@deploys == []}>{dgettext("pages", "No deploys yet.")}</p>
      </div>
    </section>
    """
  end
end
