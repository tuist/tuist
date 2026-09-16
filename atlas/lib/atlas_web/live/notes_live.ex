defmodule AtlasWeb.NotesLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.Filter

  alias Atlas.Notes
  alias Atlas.Notes.Note
  alias Noora.Filter

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Notes"))
     |> assign(:note, nil)
     |> assign(:query, "")
     |> assign(:uri, URI.parse("?"))
     |> assign(:available_filters, [])
     |> assign(:active_filters, [])
     |> assign(:notes_empty?, true)
     |> assign(:search_form, search_form(""))
     |> assign(:form, note_form(%{}))
     |> assign(:preview_markdown, "# Untitled note\n\nStart writing in Markdown.")
     |> assign(:preview_title, "Untitled note")
     |> assign(:preview_html, render_markdown("# Untitled note\n\nStart writing in Markdown."))
     |> stream(:notes, [], reset: true)}
  end

  def handle_params(params, uri, %{assigns: %{live_action: :index}} = socket) do
    available_filters = define_filters()
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)
    query = present(params["search"])

    {:noreply,
     socket
     |> assign(:page_title, gettext("Notes"))
     |> assign(:uri, URI.parse(uri))
     |> assign(:available_filters, available_filters)
     |> assign(:active_filters, active_filters)
     |> assign(:query, query || "")
     |> assign(:search_form, search_form(query || ""))
     |> assign(:note, nil)
     |> load_notes()}
  end

  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    {:noreply,
     socket
     |> assign(:page_title, gettext("New note"))
     |> assign(:note, nil)
     |> assign_editor(%{})}
  end

  def handle_params(%{"id" => id}, _uri, %{assigns: %{live_action: :show}} = socket) do
    case Notes.get_note(id) do
      %Note{} = note ->
        {:noreply,
         socket
         |> assign(:page_title, note.title)
         |> assign(:note, note)
         |> assign_editor(%{"content" => note.content, "visibility" => note.visibility})}

      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Note not found."))
         |> push_navigate(to: ~p"/library/notes")}
    end
  end

  def handle_event("preview", %{"note" => params}, socket) do
    {:noreply, assign_editor(socket, params)}
  end

  def handle_event("save", %{"note" => params}, %{assigns: %{note: nil, current_user: user}} = socket) do
    case Notes.create_note(params, user, interface: "dashboard", audit_actor: user) do
      {:ok, note} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Note created."))
         |> push_navigate(to: ~p"/library/notes/#{note.id}")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign_editor(params)
         |> assign(:form, to_form(changeset, as: :note, action: :validate))}
    end
  end

  def handle_event("save", %{"note" => params}, %{assigns: %{note: %Note{} = note}} = socket) do
    case Notes.update_note(note, params, interface: "dashboard", audit_actor: socket.assigns.current_user) do
      {:ok, updated_note} ->
        {:noreply,
         socket
         |> assign(:note, updated_note)
         |> assign_editor(%{"content" => updated_note.content, "visibility" => updated_note.visibility})
         |> put_flash(:info, gettext("Note updated."))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign_editor(params)
         |> assign(:form, to_form(changeset, as: :note, action: :validate))}
    end
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    query_string =
      socket
      |> current_query_params()
      |> put_search_param(String.trim(query || ""))

    {:noreply, push_patch(socket, to: ~p"/library/notes?#{query_string}", replace: true)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> reset_pagination()
      |> then(&Filter.Operations.add_filter_to_query(filter_id, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/library/notes?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      params
      |> Filter.Operations.update_filters_in_query(socket, current_query_params(socket) |> reset_pagination())

    {:noreply,
     socket
     |> push_patch(to: ~p"/library/notes?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def render(%{live_action: :index} = assigns), do: render_index(assigns)
  def render(assigns), do: render_editor(assigns)

  defp render_index(assigns) do
    ~H"""
    <div id="notes">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Notes")}</h1>
          <p data-part="description">
            {gettext("Shared Markdown notes, indexed for quick retrieval by people and agents.")}
          </p>
        </div>
        <.button id="notes-new-button" label={gettext("New note")} navigate={~p"/library/notes/new"}>
          <:icon_left><.icon name="plus" /></:icon_left>
        </.button>
      </div>

      <.card title={gettext("All notes")} icon="file_text" data-part="notes-card">
        <.card_section data-part="notes-section">
          <div data-part="filters">
            <.filter_dropdown
              id="notes-filters-dropdown"
              available_filters={@available_filters}
              active_filters={@active_filters}
            />

            <div data-part="search">
              <.form
                id="notes-search-form"
                for={@search_form}
                phx-change="search"
                phx-submit="search"
              >
                <.text_input
                  id="notes-search-input"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={gettext("Search notes")}
                  phx-debounce="300"
                />
              </.form>
            </div>
          </div>

          <div
            :if={@query != "" or @active_filters != []}
            id="notes-active-filters"
            data-part="active-filters"
          >
            <.active_filter :for={filter <- @active_filters} filter={filter} />
            <div :if={@query != ""} id="notes-search-filter" data-part="search-filter">
              <span data-part="label">{gettext("Search")}</span>
              <span data-part="label">{gettext("contains")}</span>
              <span data-part="badge">{@query}</span>
            </div>
          </div>

          <div id="notes-table">
            <%= if @notes_empty? do %>
              <.table id="notes-table-empty" rows={[]}>
                <:col label={gettext("Note")} />
                <:col label={gettext("Updated")} />
                <:empty_state>
                  <.table_empty_state
                    title={gettext("No notes")}
                    subtitle={gettext("Create a Markdown note to make it searchable here.")}
                  />
                </:empty_state>
              </.table>
            <% else %>
              <.table
                id="notes-table-content"
                rows={@streams.notes}
                row_navigate={fn {_id, note} -> ~p"/library/notes/#{note.id}" end}
              >
                <:col :let={{_id, note}} label={gettext("Note")}>
                  <.text_and_description_cell
                    label={note.title}
                    description={excerpt(note.content)}
                    truncate={false}
                  />
                </:col>
                <:col :let={{_id, note}} label={gettext("Updated")}>
                  <.text_cell label={format_datetime(note.updated_at)} />
                </:col>
              </.table>
            <% end %>
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp render_editor(assigns) do
    ~H"""
    <div id="note-editor">
      <div data-part="header">
        <div data-part="text">
          <.link navigate={~p"/library/notes"} data-part="back-link">{gettext("Notes")}</.link>
          <h1 data-part="title">{@preview_title}</h1>
          <p data-part="description">
            {gettext("Write Markdown on the left and preview the rendered note on the right.")}
          </p>
        </div>
      </div>

      <.form id="note-form" for={@form} phx-change="preview" phx-submit="save" data-part="editor">
        <section data-part="pane" data-pane="source">
          <.text_area
            id="note-content"
            field={@form[:content]}
            label={gettext("Markdown")}
            rows={24}
            max_length={50_000}
            phx-debounce="300"
            show_character_count={false}
          />
          <div data-part="editor-actions">
            <.button id="note-save-button" label={gettext("Save note")} type="submit" />
          </div>
        </section>
        <section data-part="pane" data-pane="preview">
          <h2 data-part="pane-title">{gettext("Preview")}</h2>
          <article id="note-preview" data-part="markdown-preview">
            {raw(@preview_html)}
          </article>
        </section>
      </.form>
    </div>
    """
  end

  defp load_notes(socket) do
    active_filters = socket.assigns.active_filters

    notes =
      Notes.list_notes(
        query: socket.assigns.query,
        created_by_id: active_filter_value(active_filters, "created_by_id")
      )

    socket
    |> assign(:notes_empty?, notes == [])
    |> stream(:notes, notes, reset: true)
  end

  defp define_filters do
    users = Atlas.Users.list_users()
    options = Enum.map(users, & &1.id)

    [
      %Filter.Filter{
        id: "created_by_id",
        field: :created_by_id,
        display_name: gettext("Created by"),
        type: :option,
        searchable: true,
        options: options,
        options_display_names: Map.new(users, fn user -> {user.id, user_label(user)} end),
        operator: :==,
        value: nil
      }
    ]
  end

  defp user_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp user_label(%{email: email}), do: email

  defp active_filter_value(filters, filter_id) do
    case Enum.find(filters, &(&1.id == filter_id && &1.operator == :==)) do
      %{value: value} -> value
      _filter -> nil
    end
  end

  defp current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp reset_pagination(params), do: Map.drop(params, ["after", "before"])

  defp put_search_param(params, ""), do: Map.delete(params, "search")
  defp put_search_param(params, query), do: Map.put(params, "search", query)

  defp assign_editor(socket, params) do
    markdown = Map.get(params, "content") || ""
    title = Note.title_from_content(markdown) || gettext("Untitled note")

    socket
    |> assign(:form, note_form(params))
    |> assign(:preview_markdown, markdown)
    |> assign(:preview_title, title)
    |> assign(:preview_html, render_markdown(markdown))
  end

  defp note_form(params), do: to_form(params, as: :note)
  defp search_form(query), do: to_form(%{"query" => query}, as: :search)

  defp render_markdown(markdown) do
    MDEx.to_html!(markdown,
      extension: [table: true, strikethrough: true, autolink: true, tasklist: true],
      sanitize: MDEx.Document.default_sanitize_options()
    )
  end

  defp excerpt(content) do
    content
    |> String.replace(~r/```.*?```/s, "")
    |> String.replace(~r/^\s{0,3}\#{1,6}\s+/m, "")
    |> String.replace(~r/^\s*[-*+]\s+/m, "")
    |> String.replace(~r/^\s*\d+\.\s+/m, "")
    |> String.replace(~r/[*_`~]/, "")
    |> then(fn markdown ->
      Regex.replace(~r/\[([^\]]+)\]\([^)]+\)/, markdown, fn _, label -> label end)
    end)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 180)
  end

  defp format_datetime(nil), do: "—"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present(_value), do: nil
end
