defmodule AtlasWeb.Admin.MemoryLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.Filter

  alias Atlas.Memory
  alias Atlas.Memory.Bulletin
  alias Atlas.Memory.Edge
  alias Atlas.Memory.Node
  alias AtlasWeb.Utilities.Query, as: WebQuery
  alias Noora.Filter
  alias Phoenix.HTML.Form

  @node_limit 100

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Memory"))
     |> assign(:memory_kinds, Node.kinds())
     |> assign(:available_filters, define_filters())
     |> assign(:active_filters, [])
     |> assign(:query, "")
     |> assign(:uri, URI.parse("?"))
     |> assign(:node_count, 0)
     |> assign(:nodes_empty?, true)
     |> assign(:search_form, search_form(""))
     |> assign(:bulletin, nil)
     |> assign(:bulletin_form, bulletin_form(nil))
     |> assign(:edge_summary, empty_edge_summary())
     |> assign_selected_node(nil)
     |> stream(:memory_nodes, [], reset: true)}
  end

  def handle_params(%{"id" => id} = params, uri, %{assigns: %{live_action: :show}} = socket) do
    parsed_uri = URI.parse(uri)

    case Memory.get_node(id) do
      %Node{} = node ->
        active_filters =
          Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

        {:noreply,
         socket
         |> assign(:uri, parsed_uri)
         |> assign(:page_title, detail_title(node))
         |> assign(:active_filters, active_filters)
         |> assign(:query, params["search"] || "")
         |> assign(:search_form, search_form(params["search"] || ""))
         |> assign_bulletin()
         |> assign_selected_node(node)}

      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Memory not found."))
         |> push_navigate(to: ~p"/memory")}
    end
  end

  def handle_params(params, uri, %{assigns: %{live_action: :index}} = socket) do
    active_filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    query = params["search"] || params["q"] || ""

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:page_title, gettext("Memory"))
     |> assign(:active_filters, active_filters)
     |> assign(:query, query)
     |> assign(:search_form, search_form(query))
     |> assign_bulletin()
     |> assign_selected_node(nil)
     |> load_nodes()}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    query_params =
      socket
      |> current_query_params()
      |> put_search_param(query)

    {:noreply, push_patch(socket, to: ~p"/memory?#{query_params}", replace: true)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket, current_query_params(socket))

    {:noreply,
     socket
     |> push_patch(to: ~p"/memory?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket, current_query_params(socket))

    {:noreply,
     socket
     |> push_patch(to: ~p"/memory?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event("save_node", %{"memory_node" => node_params}, %{assigns: %{selected_node: %Node{} = node}} = socket) do
    case Memory.update_node(node, node_params) do
      {:ok, updated_node} ->
        {:noreply,
         socket
         |> assign(:page_title, detail_title(updated_node))
         |> assign_selected_node(updated_node)
         |> put_flash(:info, gettext("Memory updated."))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:node_form, to_form(changeset, as: :memory_node, action: :validate))
         |> put_flash(:error, gettext("Could not update memory."))}
    end
  end

  def handle_event("forget_node", %{"id" => id}, socket) do
    update_memory_state(socket, id, &Memory.forget_node/1, gettext("Memory forgotten."))
  end

  def handle_event("restore_node", %{"id" => id}, socket) do
    update_memory_state(socket, id, &Memory.restore_node/1, gettext("Memory restored."))
  end

  def handle_event("save_bulletin", %{"bulletin" => %{"body" => body}}, socket) do
    case String.trim(body || "") do
      "" ->
        {:noreply, put_flash(socket, :error, gettext("Bulletin body cannot be blank."))}

      trimmed ->
        case Memory.upsert_bulletin(:global, trimmed) do
          {:ok, _bulletin} ->
            {:noreply,
             socket
             |> assign_bulletin()
             |> put_flash(:info, gettext("Memory bulletin updated."))}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not update memory bulletin."))}
        end
    end
  end

  def render(%{live_action: :show} = assigns), do: render_show(assigns)
  def render(assigns), do: render_index(assigns)

  defp render_index(assigns) do
    ~H"""
    <div id="admin-memory" data-page="index">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Memory")}</h1>
          <p data-part="description">
            {gettext("Explore workspace memory, inspect graph links, and correct stored facts.")}
          </p>
        </div>
        <div data-part="summary">
          <.badge
            id="admin-memory-visible-count"
            label={ngettext("%{count} memory", "%{count} memories", @node_count, count: @node_count)}
            color="neutral"
            style="light-fill"
          />
          <.badge
            id="admin-memory-filter-status"
            label={filter_status(@query, @active_filters)}
            color="information"
            style="light-fill"
          />
        </div>
      </div>

      <div data-part="workspace">
        <.card title={gettext("Explorer")} icon="search" data-part="explorer-card">
          <.card_section data-part="explorer-section">
            <div data-part="filters">
              <.filter_dropdown
                id="admin-memory-filters-dropdown"
                label={gettext("Filter")}
                available_filters={@available_filters}
                active_filters={@active_filters}
              />

              <div data-part="search">
                <.form
                  id="admin-memory-search-form"
                  for={@search_form}
                  phx-change="search"
                  phx-submit="search"
                >
                  <.text_input
                    id="admin-memory-search"
                    field={@search_form[:query]}
                    type="search"
                    show_suffix={false}
                    placeholder={gettext("Search memory body")}
                    phx-debounce="200"
                  />
                </.form>
              </div>
            </div>

            <div :if={Enum.any?(@active_filters)} data-part="active-filters">
              <.active_filter :for={filter <- @active_filters} filter={filter} />
            </div>

            <.table_empty_state
              :if={@nodes_empty?}
              icon="search"
              title={gettext("No memories found")}
              subtitle={gettext("Adjust the filters or save new memory from Atlas conversations.")}
            />

            <div :if={!@nodes_empty?} data-part="nodes-table">
              <.table
                id="admin-memory-nodes"
                rows={@streams.memory_nodes}
                row_key={fn {id, _node} -> id end}
                row_navigate={fn {_id, node} -> memory_node_path(node, @uri) end}
              >
                <:col :let={{_id, node}} label={gettext("Memory")}>
                  <.text_and_description_cell
                    label={node.body}
                    description={node_metadata(node)}
                  />
                </:col>
                <:col :let={{_id, node}} label={gettext("Kind")}>
                  <.badge_cell
                    label={kind_label(node.kind)}
                    color={kind_color(node.kind)}
                    style="light-fill"
                  />
                </:col>
                <:col :let={{_id, node}} label={gettext("Status")}>
                  <.badge_cell
                    label={node_status_label(node)}
                    color={node_status_color(node)}
                    style="light-fill"
                  />
                </:col>
                <:col :let={{_id, node}} label={gettext("Confirmation")}>
                  <.badge_cell
                    label={node_confirmation_label(node)}
                    color={node_confirmation_color(node)}
                    style="light-fill"
                  />
                </:col>
                <:col :let={{_id, node}} label={gettext("Updated")}>
                  <.text_cell label={format_datetime(node.updated_at)} />
                </:col>
              </.table>
            </div>
          </.card_section>
        </.card>

        <.card title={gettext("Bulletin")} icon="message_circle" data-part="bulletin-card">
          <.card_section data-part="bulletin-section">
            <div data-part="bulletin-meta">
              <span id="admin-memory-bulletin-generated-at">
                {bulletin_generated_label(@bulletin)}
              </span>
            </div>

            <.form
              id="admin-memory-bulletin-form"
              for={@bulletin_form}
              phx-submit="save_bulletin"
              data-part="bulletin-form"
            >
              <.text_area
                id="admin-memory-bulletin-body"
                field={@bulletin_form[:body]}
                label={gettext("Workspace prompt bulletin")}
                rows={8}
                max_length={8000}
                show_character_count={false}
              />

              <div data-part="editor-actions">
                <.button
                  id="admin-memory-save-bulletin"
                  label={gettext("Save bulletin")}
                  type="submit"
                />
              </div>
            </.form>
          </.card_section>
        </.card>
      </div>
    </div>
    """
  end

  defp render_show(assigns) do
    ~H"""
    <div id="admin-memory" data-page="detail">
      <.button
        id="admin-memory-back"
        label={gettext("Memory")}
        navigate={memory_index_path(@uri)}
        variant="secondary"
        size="medium"
        data-part="back-button"
      >
        <:icon_left><.arrow_left /></:icon_left>
      </.button>

      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{short_body(@selected_node.body)}</h1>
          <p data-part="description">{@selected_node.body}</p>
        </div>
        <div data-part="summary">
          <.badge
            id="admin-memory-selected-kind"
            label={kind_label(@selected_node.kind)}
            color={kind_color(@selected_node.kind)}
            style="light-fill"
          />
          <.badge
            id="admin-memory-selected-status"
            label={node_status_label(@selected_node)}
            color={node_status_color(@selected_node)}
            style="light-fill"
          />
        </div>
      </div>

      <div data-part="detail-stack">
        <.card title={gettext("Memory profile")} icon="file_text" data-part="profile-card">
          <.card_section data-part="profile-section">
            <div data-part="metadata-grid">
              <.metadata_item label={gettext("Kind")} value={kind_label(@selected_node.kind)} />
              <.metadata_item
                label={gettext("Importance")}
                value={format_importance(@selected_node.importance)}
              />
              <.metadata_item
                label={gettext("Recalls")}
                value={Integer.to_string(@selected_node.access_count)}
              />
              <.metadata_item
                label={gettext("Last recalled")}
                value={format_datetime(@selected_node.last_accessed_at)}
              />
              <.metadata_item
                label={gettext("Created")}
                value={format_datetime(@selected_node.inserted_at)}
              />
              <.metadata_item
                label={gettext("Updated")}
                value={format_datetime(@selected_node.updated_at)}
              />
              <.metadata_item label={gettext("Embedding")} value={embedding_label(@selected_node)} />
              <.metadata_item label={gettext("Scope")} value={scope_label(@selected_node)} />
            </div>
          </.card_section>
        </.card>

        <.card
          title={kind_section_title(@selected_node.kind)}
          icon={kind_icon(@selected_node.kind)}
          data-part="kind-card"
        >
          <.card_section data-part="kind-section">
            <div data-part="metadata-grid">
              <.metadata_item
                :for={item <- kind_detail_items(@selected_node, @edge_summary)}
                label={item.label}
                value={item.value}
              />
            </div>
          </.card_section>
        </.card>

        <.card title={gettext("Editor")} icon="settings" data-part="editor-card">
          <.card_section data-part="editor-section">
            <.form
              id="admin-memory-node-form"
              for={@node_form}
              phx-submit="save_node"
              data-part="editor-form"
            >
              <div data-part="editor-grid">
                <div data-part="select-field">
                  <.label label={gettext("Kind")} />
                  <.select
                    id="admin-memory-node-kind"
                    name={@node_form[:kind].name}
                    label={gettext("Select kind")}
                    value={kind_value(field_value(@node_form, :kind))}
                  >
                    <:item
                      :for={kind <- @memory_kinds}
                      value={Atom.to_string(kind)}
                      label={kind_label(kind)}
                    />
                  </.select>
                  <p :for={error <- field_errors(@node_form[:kind])} data-part="error">{error}</p>
                </div>

                <div data-part="input-field">
                  <.text_input
                    id="admin-memory-node-importance"
                    field={@node_form[:importance]}
                    input_type="number"
                    label={gettext("Importance")}
                    min="0"
                    max="1"
                    step="0.05"
                  />
                </div>
              </div>

              <.text_area
                id="admin-memory-node-body"
                field={@node_form[:body]}
                label={gettext("Body")}
                rows={7}
                max_length={4000}
                show_character_count={false}
              />

              <div data-part="editor-actions">
                <.button
                  id="admin-memory-save-node"
                  label={gettext("Save")}
                  type="submit"
                />
                <.button
                  :if={!@selected_node.forgotten}
                  id="admin-memory-forget-node"
                  label={gettext("Forget")}
                  variant="destructive"
                  type="button"
                  phx-click="forget_node"
                  phx-value-id={@selected_node.id}
                />
                <.button
                  :if={@selected_node.forgotten}
                  id="admin-memory-restore-node"
                  label={gettext("Restore")}
                  variant="secondary"
                  type="button"
                  phx-click="restore_node"
                  phx-value-id={@selected_node.id}
                />
              </div>
            </.form>
          </.card_section>
        </.card>

        <.card title={gettext("Graph links")} icon="timeline_event" data-part="edges-card">
          <.card_section data-part="edges-section">
            <div data-part="edge-group">
              <h2 data-part="section-title">{gettext("Outgoing")}</h2>
              <div :if={@outgoing_edges_empty?} data-part="edge-empty-state">
                <.table_empty_state
                  icon="timeline_event"
                  title={gettext("No outgoing links")}
                  subtitle={gettext("This memory does not point to another stored memory yet.")}
                />
              </div>
              <div :if={!@outgoing_edges_empty?} data-part="edge-table">
                <.table
                  id="admin-memory-outgoing-edges"
                  rows={@streams.outgoing_edges}
                  row_key={fn {id, _edge} -> id end}
                  row_navigate={fn {_id, edge} -> adjacent_memory_path(edge, :outgoing, @uri) end}
                >
                  <:col :let={{_id, edge}} label={gettext("Relationship")}>
                    <.badge_cell
                      label={edge_label(edge)}
                      color={edge_color(edge.kind)}
                      style="light-fill"
                    />
                  </:col>
                  <:col :let={{_id, edge}} label={gettext("Memory")}>
                    <.text_and_description_cell
                      label={adjacent_body(edge, :outgoing)}
                      description={adjacent_kind(edge, :outgoing)}
                    />
                  </:col>
                  <:col :let={{_id, edge}} label={gettext("Weight")}>
                    <.text_cell label={format_importance(edge.weight)} />
                  </:col>
                </.table>
              </div>
            </div>

            <div data-part="edge-group">
              <h2 data-part="section-title">{gettext("Incoming")}</h2>
              <div :if={@incoming_edges_empty?} data-part="edge-empty-state">
                <.table_empty_state
                  icon="timeline_event"
                  title={gettext("No incoming links")}
                  subtitle={gettext("No other memory points to this item yet.")}
                />
              </div>
              <div :if={!@incoming_edges_empty?} data-part="edge-table">
                <.table
                  id="admin-memory-incoming-edges"
                  rows={@streams.incoming_edges}
                  row_key={fn {id, _edge} -> id end}
                  row_navigate={fn {_id, edge} -> adjacent_memory_path(edge, :incoming, @uri) end}
                >
                  <:col :let={{_id, edge}} label={gettext("Relationship")}>
                    <.badge_cell
                      label={edge_label(edge)}
                      color={edge_color(edge.kind)}
                      style="light-fill"
                    />
                  </:col>
                  <:col :let={{_id, edge}} label={gettext("Memory")}>
                    <.text_and_description_cell
                      label={adjacent_body(edge, :incoming)}
                      description={adjacent_kind(edge, :incoming)}
                    />
                  </:col>
                  <:col :let={{_id, edge}} label={gettext("Weight")}>
                    <.text_cell label={format_importance(edge.weight)} />
                  </:col>
                </.table>
              </div>
            </div>
          </.card_section>
        </.card>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp metadata_item(assigns) do
    ~H"""
    <div data-part="metadata-item">
      <span data-part="label">{@label}</span>
      <span data-part="value">{@value}</span>
    </div>
    """
  end

  defp update_memory_state(socket, id, update_fun, success_message) do
    with %Node{} = node <- Memory.get_node(id),
         {:ok, updated_node} <- update_fun.(node) do
      {:noreply,
       socket
       |> assign(:page_title, detail_title(updated_node))
       |> assign_selected_node(updated_node)
       |> put_flash(:info, success_message)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Memory not found."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update memory."))}
    end
  end

  defp assign_selected_node(socket, nil) do
    socket
    |> assign(:selected_node, nil)
    |> assign(:node_form, nil)
    |> assign(:outgoing_edges_empty?, true)
    |> assign(:incoming_edges_empty?, true)
    |> assign(:edge_summary, empty_edge_summary())
    |> stream(:outgoing_edges, [], reset: true)
    |> stream(:incoming_edges, [], reset: true)
  end

  defp assign_selected_node(socket, %Node{} = node) do
    edges = Memory.list_node_edges(node)

    socket
    |> assign(:selected_node, node)
    |> assign(:node_form, to_form(Memory.change_node(node), as: :memory_node))
    |> assign(:outgoing_edges_empty?, edges.outgoing == [])
    |> assign(:incoming_edges_empty?, edges.incoming == [])
    |> assign(:edge_summary, edge_summary(edges))
    |> stream(:outgoing_edges, edges.outgoing, reset: true)
    |> stream(:incoming_edges, edges.incoming, reset: true)
  end

  defp assign_bulletin(socket) do
    bulletin = Memory.get_bulletin(:global)

    socket
    |> assign(:bulletin, bulletin)
    |> assign(:bulletin_form, bulletin_form(bulletin))
  end

  defp load_nodes(socket) do
    active_filters = socket.assigns.active_filters

    nodes =
      Memory.list_nodes(
        scope: :global,
        query: socket.assigns.query,
        kind: active_filter_kind(active_filters),
        status: active_filter_status(active_filters),
        confirmation: active_filter_confirmation(active_filters),
        include_pending: include_pending?(active_filters),
        limit: @node_limit
      )

    socket
    |> assign(:nodes_empty?, nodes == [])
    |> assign(:node_count, length(nodes))
    |> stream(:memory_nodes, nodes, reset: true)
  end

  defp define_filters do
    kind_filter = %Filter.Filter{
      id: "kind",
      field: :kind,
      display_name: gettext("Kind"),
      type: :option,
      searchable: false,
      options: Enum.map(Node.kinds(), &Atom.to_string/1),
      options_display_names: Map.new(Node.kinds(), fn kind -> {Atom.to_string(kind), kind_label(kind)} end),
      operator: :==,
      value: nil
    }

    status_filter = %Filter.Filter{
      id: "status",
      field: :status,
      display_name: gettext("Status"),
      type: :option,
      searchable: false,
      options: ["active", "forgotten"],
      options_display_names: %{
        "active" => gettext("Active"),
        "forgotten" => gettext("Forgotten")
      },
      operator: :==,
      value: nil
    }

    confirmation_filter = %Filter.Filter{
      id: "confirmation",
      field: :confirmation,
      display_name: gettext("Confirmation"),
      type: :option,
      searchable: false,
      options: ["confirmed", "pending"],
      options_display_names: %{
        "confirmed" => gettext("Confirmed"),
        "pending" => gettext("Pending")
      },
      operator: :==,
      value: nil
    }

    [kind_filter, status_filter, confirmation_filter]
  end

  defp active_filter_kind(filters) do
    filters
    |> filter_value("kind")
    |> parse_kind()
  end

  defp active_filter_status(filters) do
    filters
    |> filter_value("status")
    |> parse_status()
  end

  defp active_filter_confirmation(filters) do
    filters
    |> filter_value("confirmation")
    |> parse_confirmation()
  end

  defp include_pending?(filters) do
    active_filter_confirmation(filters) == :pending
  end

  defp filter_value(filters, filter_id) do
    filters
    |> Enum.find(&(&1.id == filter_id))
    |> case do
      nil -> nil
      %{value: nil} -> nil
      filter -> WebQuery.present_string(to_string(filter.value))
    end
  end

  defp parse_kind(nil), do: nil

  defp parse_kind(value) when is_atom(value) do
    if value in Node.kinds(), do: value
  end

  defp parse_kind(value) when is_binary(value) do
    Enum.find(Node.kinds(), &(Atom.to_string(&1) == value))
  end

  defp parse_status("active"), do: :active
  defp parse_status("forgotten"), do: :forgotten
  defp parse_status(_value), do: nil

  defp parse_confirmation("confirmed"), do: :confirmed
  defp parse_confirmation("pending"), do: :pending
  defp parse_confirmation(_value), do: nil

  defp current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp put_search_param(params, query) do
    case String.trim(to_string(query)) do
      "" -> Map.delete(params, "search")
      trimmed -> Map.put(params, "search", trimmed)
    end
  end

  defp memory_node_path(%Node{id: id}, %URI{} = uri) do
    params = URI.decode_query(uri.query || "")
    ~p"/memory/#{id}?#{params}"
  end

  defp adjacent_memory_path(%Edge{dst: %Node{} = node}, :outgoing, %URI{} = uri), do: memory_node_path(node, uri)
  defp adjacent_memory_path(%Edge{src: %Node{} = node}, :incoming, %URI{} = uri), do: memory_node_path(node, uri)
  defp adjacent_memory_path(_edge, _direction, %URI{} = uri), do: memory_index_path(uri)

  defp memory_index_path(%URI{} = uri) do
    params = URI.decode_query(uri.query || "")
    ~p"/memory?#{params}"
  end

  defp search_form(query), do: to_form(%{"query" => query}, as: :search)
  defp bulletin_form(bulletin), do: to_form(%{"body" => bulletin_body(bulletin)}, as: :bulletin)

  defp field_value(form, field), do: Form.input_value(form, field)

  defp field_errors(field) do
    Enum.map(field.errors, &AtlasWeb.CoreComponents.translate_error/1)
  end

  defp kind_value(nil), do: ""
  defp kind_value(kind) when is_atom(kind), do: Atom.to_string(kind)
  defp kind_value(kind), do: kind

  defp kind_label(kind) when is_atom(kind) do
    kind
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp kind_label(kind), do: kind

  defp kind_color(:decision), do: "primary"
  defp kind_color(:goal), do: "success"
  defp kind_color(:todo), do: "warning"
  defp kind_color(:preference), do: "focus"
  defp kind_color(:identity), do: "secondary"
  defp kind_color(:event), do: "information"
  defp kind_color(:observation), do: "attention"
  defp kind_color(_kind), do: "neutral"

  defp kind_icon(:decision), do: "git_merge"
  defp kind_icon(:goal), do: "circle_check"
  defp kind_icon(:todo), do: "check"
  defp kind_icon(:preference), do: "user"
  defp kind_icon(:identity), do: "user"
  defp kind_icon(:event), do: "history"
  defp kind_icon(:observation), do: "eye"
  defp kind_icon(_kind), do: "file_text"

  defp kind_section_title(:decision), do: gettext("Decision trail")
  defp kind_section_title(:goal), do: gettext("Goal context")
  defp kind_section_title(:todo), do: gettext("Action context")
  defp kind_section_title(:preference), do: gettext("Preference context")
  defp kind_section_title(:identity), do: gettext("Identity context")
  defp kind_section_title(:event), do: gettext("Timeline context")
  defp kind_section_title(:observation), do: gettext("Signal context")
  defp kind_section_title(_kind), do: gettext("Fact context")

  defp kind_detail_items(%Node{kind: :decision} = node, edges) do
    [
      %{label: gettext("Decision"), value: node.body},
      %{label: gettext("Supersedes"), value: Integer.to_string(edges.updates)},
      %{label: gettext("Contradictions"), value: Integer.to_string(edges.contradicts)},
      %{label: gettext("Related memories"), value: Integer.to_string(edges.total)}
    ]
  end

  defp kind_detail_items(%Node{kind: :goal} = node, edges) do
    [
      %{label: gettext("Goal"), value: node.body},
      %{label: gettext("Linked todos"), value: Integer.to_string(edges.todos)},
      %{label: gettext("Last recalled"), value: format_datetime(node.last_accessed_at)},
      %{label: gettext("Related memories"), value: Integer.to_string(edges.total)}
    ]
  end

  defp kind_detail_items(%Node{kind: :todo} = node, edges) do
    [
      %{label: gettext("Task"), value: node.body},
      %{label: gettext("Status"), value: node_status_label(node)},
      %{label: gettext("Supporting facts"), value: Integer.to_string(edges.facts)},
      %{label: gettext("Related memories"), value: Integer.to_string(edges.total)}
    ]
  end

  defp kind_detail_items(%Node{kind: :preference} = node, edges) do
    [
      %{label: gettext("Preference"), value: node.body},
      %{label: gettext("Recall priority"), value: format_importance(node.importance)},
      %{label: gettext("Related decisions"), value: Integer.to_string(edges.decisions)},
      %{label: gettext("Related memories"), value: Integer.to_string(edges.total)}
    ]
  end

  defp kind_detail_items(%Node{kind: :identity} = node, edges) do
    [
      %{label: gettext("Identity"), value: node.body},
      %{label: gettext("Scope"), value: scope_label(node)},
      %{label: gettext("Recall priority"), value: format_importance(node.importance)},
      %{label: gettext("Related memories"), value: Integer.to_string(edges.total)}
    ]
  end

  defp kind_detail_items(%Node{kind: :event} = node, edges) do
    [
      %{label: gettext("Event"), value: node.body},
      %{label: gettext("Recorded"), value: format_datetime(node.inserted_at)},
      %{label: gettext("Updates"), value: Integer.to_string(edges.updates)},
      %{label: gettext("Related memories"), value: Integer.to_string(edges.total)}
    ]
  end

  defp kind_detail_items(%Node{kind: :observation} = node, edges) do
    [
      %{label: gettext("Observation"), value: node.body},
      %{label: gettext("Recalls"), value: Integer.to_string(node.access_count)},
      %{label: gettext("Supporting facts"), value: Integer.to_string(edges.facts)},
      %{label: gettext("Related memories"), value: Integer.to_string(edges.total)}
    ]
  end

  defp kind_detail_items(%Node{} = node, edges) do
    [
      %{label: gettext("Fact"), value: node.body},
      %{label: gettext("Contradictions"), value: Integer.to_string(edges.contradicts)},
      %{label: gettext("Updates"), value: Integer.to_string(edges.updates)},
      %{label: gettext("Related memories"), value: Integer.to_string(edges.total)}
    ]
  end

  defp node_status_label(%Node{forgotten: true}), do: gettext("Forgotten")
  defp node_status_label(_node), do: gettext("Active")

  defp node_status_color(%Node{forgotten: true}), do: "neutral"
  defp node_status_color(_node), do: "success"

  defp node_confirmation_label(%Node{confirmation: :pending}), do: gettext("Pending")
  defp node_confirmation_label(_node), do: gettext("Confirmed")

  defp node_confirmation_color(%Node{confirmation: :pending}), do: "warning"
  defp node_confirmation_color(_node), do: "success"

  defp node_metadata(node) do
    gettext("Importance %{importance} · %{count} recalls",
      importance: format_importance(node.importance),
      count: node.access_count
    )
  end

  defp edge_label(%Edge{kind: kind}) do
    kind
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp edge_color(:updates), do: "primary"
  defp edge_color(:contradicts), do: "destructive"
  defp edge_color(_kind), do: "neutral"

  defp adjacent_body(%Edge{dst: %Node{body: body}}, :outgoing), do: body
  defp adjacent_body(%Edge{src: %Node{body: body}}, :incoming), do: body
  defp adjacent_body(_edge, _direction), do: gettext("Memory no longer exists")

  defp adjacent_kind(%Edge{dst: %Node{kind: kind}}, :outgoing), do: kind_label(kind)
  defp adjacent_kind(%Edge{src: %Node{kind: kind}}, :incoming), do: kind_label(kind)
  defp adjacent_kind(_edge, _direction), do: nil

  defp edge_summary(%{outgoing: outgoing, incoming: incoming}) do
    edges = outgoing ++ incoming

    %{
      total: length(edges),
      updates: Enum.count(edges, &(&1.kind == :updates)),
      contradicts: Enum.count(edges, &(&1.kind == :contradicts)),
      facts: Enum.count(edges, &adjacent_kind?(&1, :fact)),
      decisions: Enum.count(edges, &adjacent_kind?(&1, :decision)),
      todos: Enum.count(edges, &adjacent_kind?(&1, :todo))
    }
  end

  defp empty_edge_summary do
    %{total: 0, updates: 0, contradicts: 0, facts: 0, decisions: 0, todos: 0}
  end

  defp adjacent_kind?(%Edge{src: %Node{kind: kind}}, target_kind) when kind == target_kind, do: true
  defp adjacent_kind?(%Edge{dst: %Node{kind: kind}}, target_kind) when kind == target_kind, do: true
  defp adjacent_kind?(_edge, _target_kind), do: false

  defp scope_label(%Node{scope: :global}), do: gettext("Workspace")
  defp scope_label(%Node{scope: :channel}), do: gettext("Channel")
  defp scope_label(_node), do: "-"

  defp format_importance(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp format_importance(value) when is_integer(value), do: :erlang.float_to_binary(value / 1, decimals: 2)
  defp format_importance(_value), do: "0.00"

  defp format_datetime(nil), do: gettext("Never")

  defp format_datetime(%NaiveDateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
  end

  defp embedding_label(%Node{embedding_model: nil}), do: gettext("Not indexed")

  defp embedding_label(%Node{embedding_model: model, embedded_at: embedded_at}) do
    gettext("%{model} at %{datetime}", model: model, datetime: format_datetime(embedded_at))
  end

  defp bulletin_body(nil), do: ""
  defp bulletin_body(%Bulletin{body: body}), do: body

  defp bulletin_generated_label(nil), do: gettext("No bulletin generated yet")

  defp bulletin_generated_label(%Bulletin{generated_at: generated_at}) do
    gettext("Generated %{datetime}", datetime: format_datetime(generated_at))
  end

  defp filter_status("", []), do: gettext("Active only")
  defp filter_status(_query, []), do: gettext("Searching")

  defp filter_status("", filters),
    do: ngettext("%{count} filter", "%{count} filters", length(filters), count: length(filters))

  defp filter_status(_query, filters) do
    ngettext("%{count} filter + search", "%{count} filters + search", length(filters), count: length(filters))
  end

  defp detail_title(%Node{} = node), do: gettext("Memory · %{kind}", kind: kind_label(node.kind))

  defp short_body(body) when is_binary(body) do
    if String.length(body) > 96, do: String.slice(body, 0, 96) <> "...", else: body
  end

  defp short_body(_body), do: gettext("Memory")
end
