defmodule AtlasWeb.PagesLive.Index do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Engineering.Pages
  alias AtlasWeb.Plugs.PagesSubdomain

  @max_files 500
  @max_file_size 5 * 1024 * 1024

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, dgettext("pages", "Pages"))
     |> assign(:sites, Pages.list_pages())
     |> assign(:new_form, to_form(%{"slug" => "", "title" => "", "description" => ""}, as: :new_site))
     |> assign(:target_slug, nil)
     |> assign(:flash_message, nil)
     |> allow_upload(:page_files,
       accept: :any,
       max_entries: @max_files,
       max_file_size: @max_file_size,
       auto_upload: false
     )}
  end

  @impl true
  def handle_event("validate", %{"new_site" => attrs}, socket) do
    {:noreply, assign(socket, :new_form, to_form(attrs, as: :new_site))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("select_target", %{"slug" => slug}, socket) do
    {:noreply, assign(socket, :target_slug, slug)}
  end

  def handle_event("clear_target", _params, socket) do
    {:noreply, assign(socket, :target_slug, nil)}
  end

  def handle_event("create_site", %{"new_site" => attrs}, socket) do
    case Pages.create_page(attrs, socket.assigns.current_user) do
      {:ok, page} ->
        {:noreply,
         socket
         |> assign(:sites, Pages.list_pages())
         |> assign(:target_slug, page.slug)
         |> assign(:new_form, to_form(%{"slug" => "", "title" => "", "description" => ""}, as: :new_site))
         |> assign(:flash_message, {:ok, dgettext("pages", "Site %{slug} created.", slug: page.slug)})}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_form, to_form(changeset, as: :new_site))}
    end
  end

  def handle_event("publish", _params, socket) do
    with %{target_slug: slug} when is_binary(slug) <- socket.assigns,
         page when not is_nil(page) <- Pages.get_page_by_slug(slug),
         manifest when manifest != [] <- upload_manifest(socket),
         {:ok, %{deploy: deploy}} <- Pages.start_deploy(page, manifest, socket.assigns.current_user),
         :ok <- upload_all(socket, page, deploy),
         {:ok, %{page: page}} <- Pages.finalize_deploy(deploy, socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(:sites, Pages.list_pages())
       |> assign(:flash_message, {:ok, dgettext("pages", "Deployed %{slug}", slug: page.slug)})
       |> assign(:target_slug, nil)}
    else
      [] ->
        {:noreply, assign(socket, :flash_message, {:error, dgettext("pages", "Drop at least one file first.")})}

      nil ->
        {:noreply, assign(socket, :flash_message, {:error, dgettext("pages", "Pick a target site first.")})}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_message, {:error, format_error(reason)})}

      _other ->
        {:noreply, assign(socket, :flash_message, {:error, dgettext("pages", "Deploy failed. Try again.")})}
    end
  end

  defp upload_manifest(socket) do
    socket.assigns.uploads.page_files.entries
    |> Enum.reject(&(&1.progress < 100))
    |> Enum.map(fn entry ->
      %{
        "path" => relative_path(entry),
        "size" => entry.client_size,
        "content_type" => entry.client_type
      }
    end)
  end

  defp upload_all(socket, page, deploy) do
    results =
      consume_uploaded_entries(socket, :page_files, fn %{path: temp_path}, entry ->
        body = File.read!(temp_path)
        path = relative_path(entry)

        case Pages.store_object(page, deploy, path, body, content_type: entry.client_type) do
          {:ok, _resp} -> {:ok, path}
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    case Enum.find(results, &match?({:error, _reason}, &1)) do
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp relative_path(entry) do
    Map.get(entry, :client_relative_path) || entry.client_name
  end

  defp format_error({:missing_object, path}),
    do: dgettext("pages", "Upload for %{path} did not land in storage.", path: path)

  defp format_error({:too_many_files, limit}),
    do: dgettext("pages", "Deploy has more than %{limit} files.", limit: limit)

  defp format_error({:too_large, limit}), do: dgettext("pages", "Deploy is over %{limit} bytes.", limit: limit)
  defp format_error(:invalid_manifest), do: dgettext("pages", "Some file paths are invalid.")
  defp format_error(:empty_manifest), do: dgettext("pages", "Drop at least one file first.")
  defp format_error(%Ecto.Changeset{}), do: dgettext("pages", "Site details are invalid.")
  defp format_error(other), do: "#{inspect(other)}"

  defp site_url(site) do
    host_suffix =
      Application.get_env(:atlas, PagesSubdomain, [])
      |> Keyword.get(:host_suffix, "atlas.tuist.dev")

    "https://#{site.slug}.#{host_suffix}/"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="pages" data-part="page">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{dgettext("pages", "Pages")}</h1>
          <p>
            {dgettext(
              "pages",
              "Deploy a folder of HTML and assets and Atlas serves it at slug.atlas.tuist.dev for everyone in the org."
            )}
          </p>
        </div>
      </div>

      <div :if={@flash_message} data-part="flash" data-tone={elem(@flash_message, 0)}>
        {elem(@flash_message, 1)}
      </div>

      <div data-part="grid">
        <div data-part="card">
          <h2>{dgettext("pages", "New site")}</h2>
          <p>{dgettext("pages", "Reserve a slug. It becomes the site's subdomain.")}</p>

          <.form for={@new_form} phx-change="validate" phx-submit="create_site">
            <.text_input field={@new_form[:slug]} label={dgettext("pages", "Slug")} />
            <.text_input field={@new_form[:title]} label={dgettext("pages", "Title")} />
            <.text_input field={@new_form[:description]} label={dgettext("pages", "Description")} />

            <button type="submit" data-part="submit">{dgettext("pages", "Create site")}</button>
          </.form>
        </div>

        <div data-part="card">
          <h2>{dgettext("pages", "Deploy")}</h2>
          <p :if={is_nil(@target_slug)}>
            {dgettext("pages", "Pick a site below, then drop a folder of files.")}
          </p>
          <p :if={@target_slug}>{dgettext("pages", "Deploying to %{slug}", slug: @target_slug)}</p>

          <form :if={@target_slug} phx-submit="publish" phx-change="validate">
            <div data-part="dropzone" phx-drop-target={@uploads.page_files.ref}>
              <.live_file_input upload={@uploads.page_files} webkitdirectory />
              <p>{dgettext("pages", "Drop a folder here.")}</p>
              <ul>
                <li :for={entry <- @uploads.page_files.entries}>
                  {relative_path(entry)} <span data-part="size">({entry.client_size} bytes)</span>
                </li>
              </ul>
              <p :for={err <- upload_errors(@uploads.page_files)} data-part="error">
                {Phoenix.Naming.humanize(err)}
              </p>
            </div>

            <div data-part="actions">
              <button type="submit" data-part="submit">{dgettext("pages", "Publish")}</button>
              <button type="button" phx-click="clear_target" data-part="cancel">
                {dgettext("pages", "Cancel")}
              </button>
            </div>
          </form>
        </div>
      </div>

      <div data-part="sites">
        <h2>{dgettext("pages", "Sites")}</h2>
        <ul :if={@sites != []}>
          <li :for={site <- @sites} data-part="site">
            <div data-part="site-header">
              <a href={site_url(site)} target="_blank" rel="noreferrer">
                {site.slug}.atlas.tuist.dev
              </a>
              <.link navigate={~p"/engineering/pages/#{site.id}"} data-part="details">
                {dgettext("pages", "Details")}
              </.link>
            </div>
            <div data-part="site-body">
              <span :if={site.title}>{site.title}</span>
              <span :if={site.description} data-part="description">{site.description}</span>
              <button
                type="button"
                phx-click="select_target"
                phx-value-slug={site.slug}
                data-part="target-button"
              >
                {dgettext("pages", "Deploy here")}
              </button>
            </div>
          </li>
        </ul>
        <p :if={@sites == []}>{dgettext("pages", "No sites yet. Create one to get started.")}</p>
      </div>
    </section>
    """
  end
end
