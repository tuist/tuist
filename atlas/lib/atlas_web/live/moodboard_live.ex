defmodule AtlasWeb.MoodboardLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.MoodboardComponents
  import AtlasWeb.MoodboardMedia, only: [media: 1]
  import AtlasWeb.PaginationComponents

  alias Atlas.Moodboard
  alias Atlas.Moodboard.Resource

  @page_size 24
  @refresh_interval :timer.seconds(30)

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_resources, @refresh_interval)

    {:ok,
     socket
     |> assign(:page_title, gettext("Moodboard"))
     |> assign(:resources, [])
     |> assign(:editing, nil)
     |> assign_form(%Resource{})}
  end

  def handle_params(params, uri, socket) do
    query = String.slice(params["search"] || "", 0, 200)
    tag = String.slice(params["tag"] || "", 0, 40)
    offset = parse_offset(params["offset"])

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:query, query)
     |> assign(:tag, tag)
     |> assign(:offset, offset)
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))
     |> load_resources()}
  end

  def handle_info(:refresh_resources, socket) do
    Process.send_after(self(), :refresh_resources, @refresh_interval)
    # Do not repeatedly buy query embeddings for an idle search tab.
    {:noreply, if(socket.assigns.query == "", do: load_resources(socket), else: socket)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply, push_patch(socket, to: board_path(String.trim(query), socket.assigns.tag, 0), replace: true)}
  end

  def handle_event("clear_tag", _params, socket),
    do: {:noreply, push_patch(socket, to: board_path(socket.assigns.query, "", 0))}

  def handle_event("clear_search", _params, socket),
    do: {:noreply, push_patch(socket, to: board_path("", socket.assigns.tag, 0))}

  def handle_event("new", _params, socket), do: {:noreply, socket |> assign(:editing, nil) |> assign_form(%Resource{})}

  def handle_event("edit", %{"id" => id}, socket) do
    case Moodboard.get_resource(socket.assigns.current_user, id) do
      %Resource{created_by_id: owner_id} = resource when owner_id == socket.assigns.current_user.id ->
        {:noreply,
         socket
         |> assign(:editing, resource)
         |> assign_form(resource)
         |> push_event("open-modal", %{id: "moodboard-resource-modal"})}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("This resource is not yours to edit."))}
    end
  end

  def handle_event("save", %{"resource" => attrs}, socket) do
    attrs = Map.update(attrs, "tags", [], &String.split(&1, ","))

    result =
      case socket.assigns.editing do
        nil -> Moodboard.create_resource(attrs, socket.assigns.current_user, interface: "dashboard")
        resource -> Moodboard.update_resource(resource.id, attrs, socket.assigns.current_user, interface: "dashboard")
      end

    case result do
      {:ok, _resource} ->
        {:noreply,
         socket
         |> load_resources()
         |> put_flash(:info, gettext("Resource saved to Moodboard."))
         |> push_event("close-modal", %{id: "moodboard-resource-modal"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :resource_form, resource_form(changeset, attrs["tags"]))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("This resource is no longer available."))}
    end
  end

  def handle_event("delete", _params, %{assigns: %{editing: %Resource{} = resource}} = socket) do
    case Moodboard.delete_resource(resource.id, socket.assigns.current_user, interface: "dashboard") do
      {:ok, _resource} ->
        {:noreply,
         socket
         |> load_resources()
         |> put_flash(:info, gettext("Resource removed."))
         |> push_event("close-modal", %{id: "moodboard-resource-modal"})}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("This resource is no longer available."))}
    end
  end

  def handle_event("delete", _params, socket), do: {:noreply, socket}
  def handle_event("resource_modal_changed", _params, socket), do: {:noreply, socket}

  def handle_event("close_resource_modal", _params, socket),
    do: {:noreply, push_event(socket, "close-modal", %{id: "moodboard-resource-modal"})}

  defp load_resources(socket) do
    {resources, more} =
      Moodboard.list_resources(socket.assigns.current_user,
        query: socket.assigns.query,
        tag: socket.assigns.tag,
        offset: socket.assigns.offset,
        limit: @page_size
      )

    socket
    |> assign(:resources, resources)
    |> assign(:has_more, more)
    |> assign(:previous_cursor, Integer.to_string(max(socket.assigns.offset - @page_size, 0)))
    |> assign(:next_cursor, Integer.to_string(socket.assigns.offset + @page_size))
  end

  defp assign_form(socket, resource), do: assign(socket, :resource_form, resource_form(resource))

  defp parse_offset(value) when is_binary(value) do
    case Integer.parse(value) do
      {offset, ""} when offset >= 0 -> min(offset, 1_000_000)
      _ -> 0
    end
  end

  defp parse_offset(_value), do: 0

  defp board_path(query, tag, offset) do
    params = Enum.reject([search: query, tag: tag, offset: offset], fn {_key, value} -> value in ["", 0] end)
    ~p"/library/moodboard?#{params}"
  end

  defp snippet(resource), do: resource.description || resource.source_description || resource.content

  def render(assigns) do
    ~H"""
    <div id="moodboard">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Moodboard")}</h1>
          <p data-part="description">
            {gettext(
              "A shared pool of things that spark ideas. Save a reference. See where it leads."
            )}
          </p>
        </div>
        <div data-part="header-actions">
          <.resource_modal form={@resource_form} editing={@editing != nil}>
            <:trigger :let={attrs}>
              <.button
                id="moodboard-add"
                label={gettext("Add resource")}
                phx-click="new"
                type="button"
                {attrs}
              >
                <:icon_left><.plus /></:icon_left>
              </.button>
            </:trigger>
          </.resource_modal>
        </div>
      </div>
      <.card title={gettext("Resources")} icon="photo">
        <.card_section data-part="resources-section">
          <div data-part="filters">
            <div data-part="search">
              <.form id="moodboard-search" for={@search_form} phx-change="search" phx-submit="search">
                <.text_input
                  id="moodboard-search-input"
                  field={@search_form[:query]}
                  type="search"
                  aria-label={gettext("Search resources")}
                  placeholder={gettext("Search ideas, source text, and conversations")}
                  show_suffix={false}
                  phx-debounce="300"
                />
              </.form>
            </div>
          </div>
          <div
            :if={@tag != "" or @query != ""}
            id="moodboard-active-filters"
            data-part="active-filters"
          >
            <.tag
              :if={@tag != ""}
              id="moodboard-clear-tag"
              label={@tag}
              icon="filter"
              dismissible
              on_dismiss="clear_tag"
            />
            <.tag
              :if={@query != ""}
              id="moodboard-clear-search"
              label={gettext("Search: %{query}", query: @query)}
              icon="search"
              dismissible
              on_dismiss="clear_search"
            />
          </div>
          <div :if={@resources == []} id="moodboard-empty">
            <.table_empty_state
              icon="photo"
              title={
                if @query != "" or @tag != "" or @offset > 0,
                  do: gettext("No resources found"),
                  else: gettext("Make room for inspiration")
              }
              subtitle={
                if @query != "" or @tag != "" or @offset > 0,
                  do: gettext("Try another search or tag, or go back to the first page."),
                  else:
                    gettext(
                      "Collect articles, websites, videos, and ideas worth coming back to. Add the first resource here or through MCP."
                    )
              }
            />
          </div>
          <div :if={@resources != []} id="moodboard-grid" data-part="grid">
            <article :for={resource <- @resources} id={"resource-#{resource.id}"} data-part="resource">
              <.media resource={resource} id={"resource-media-#{resource.id}"} />
              <.link navigate={~p"/library/moodboard/#{resource.id}"} data-part="resource-link">
                <div data-part="resource-text">
                  <div data-part="domain">
                    <span :if={resource.url}>{URI.parse(resource.url).host}</span>
                    <.badge
                      label={kind_label(resource.kind)}
                      color="neutral"
                      style="light-fill"
                      size="small"
                    />
                  </div>
                  <h2>{resource.title}</h2>
                  <p :if={snippet(resource)}>{snippet(resource)}</p>
                  <span :if={resource.preview_status == "pending"} data-part="preview-status">
                    {gettext("Finding a preview…")}
                  </span>
                </div>
              </.link>
              <div :if={resource.tags != []} data-part="tags">
                <.link
                  :for={tag <- resource.tags}
                  patch={board_path(@query, tag, 0)}
                  aria-label={gettext("Filter by %{tag}", tag: tag)}
                >
                  <.tag label={tag} />
                </.link>
              </div>
              <div data-part="resource-footer">
                <span>
                  {gettext("Added by %{name}",
                    name: (resource.created_by && resource.created_by.name) || gettext("a teammate")
                  )}
                </span>
                <div data-part="resource-actions">
                  <.button
                    :if={resource.url}
                    href={resource.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    icon_only
                    aria-label={gettext("Open original")}
                    variant="secondary"
                    size="small"
                  >
                    <.external_link />
                  </.button>
                  <.button
                    id={"discuss-resource-#{resource.id}"}
                    navigate={~p"/library/moodboard/#{resource.id}"}
                    label={gettext("Discuss")}
                    variant="secondary"
                    size="small"
                  />
                  <.button
                    :if={resource.created_by_id == @current_user.id}
                    id={"edit-resource-#{resource.id}"}
                    label={gettext("Edit")}
                    variant="secondary"
                    size="small"
                    phx-click="edit"
                    phx-value-id={resource.id}
                  />
                </div>
              </div>
            </article>
          </div>
          <nav
            :if={@offset > 0 or @has_more}
            id="moodboard-pagination"
            aria-label={gettext("Resource pages")}
          >
            <.pagination
              uri={@uri}
              has_previous_page={@offset > 0}
              has_next_page={@has_more}
              start_cursor={@previous_cursor}
              end_cursor={@next_cursor}
              before_param="offset"
              after_param="offset"
            />
          </nav>
        </.card_section>
      </.card>
    </div>
    """
  end
end
