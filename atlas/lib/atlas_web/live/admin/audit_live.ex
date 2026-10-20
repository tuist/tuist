defmodule AtlasWeb.Admin.AuditLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.Filter

  alias Atlas.Audit
  alias Atlas.Audit.Activity
  alias AtlasWeb.Utilities.Query
  alias Noora.Filter

  @page_size 25
  @legacy_filter_ids ~w(interface action target_type)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Audit"))
     |> assign(:available_filters, [])}
  end

  def handle_params(params, uri, socket) do
    available_filters = define_filters()
    query_params = Query.query_params(uri)
    normalized_query_params = normalize_query_params(query_params)

    params =
      params
      |> Map.drop(Map.keys(query_params))
      |> Map.merge(normalized_query_params)

    page = Query.parse_page(params["page"])
    query = params["q"] || ""
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    {activities, meta} =
      Audit.list_activities(audit_list_opts(query, active_filters, page))

    socket =
      socket
      |> assign(:uri, uri_from_query_params(normalized_query_params))
      |> assign(:activities, activities)
      |> assign(:activities_empty?, activities == [])
      |> assign(:activities_meta, meta)
      |> assign(:available_filters, available_filters)
      |> assign(:active_filters, active_filters)
      |> assign(:query, query)
      |> assign(:search_form, to_form(%{"query" => query}, as: :search))

    socket =
      if query_params == normalized_query_params do
        socket
      else
        push_patch(socket, to: ~p"/admin/audit?#{normalized_query_params}", replace: true)
      end

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/admin/audit?#{audit_query_params(query, socket.assigns.active_filters)}",
       replace: true
     )}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Filter.Operations.add_filter_to_query(filter_id, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/admin/audit?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Filter.Operations.update_filters_in_query(params, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/admin/audit?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def render(assigns) do
    ~H"""
    <div id="admin-audit" data-part="admin-audit">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Audit")}</h1>
          <p data-part="description">
            {gettext("Trace Atlas activity across the dashboard, MCP, Slack, jobs, and system paths.")}
          </p>
        </div>
      </div>

      <.card title={gettext("Activity")} icon="history" data-part="audit-card">
        <.card_section data-part="audit-table-section">
          <div data-part="filters">
            <.filter_dropdown
              id="admin-audit-filters-dropdown"
              available_filters={@available_filters}
              active_filters={@active_filters}
            />

            <div data-part="search">
              <.form
                id="admin-audit-search-form"
                for={@search_form}
                phx-change="search"
                phx-submit="search"
              >
                <.text_input
                  id="admin-audit-search"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={gettext("Search actor, action, target, or metadata...")}
                />
              </.form>
            </div>
          </div>

          <div :if={@active_filters != []} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>

          <.table id="admin-audit-table" rows={@activities}>
            <:col :let={activity} label={gettext("Time")}>
              <.text_cell
                label={format_datetime(activity.occurred_at)}
                sublabel={format_date(activity.occurred_at)}
              />
            </:col>
            <:col :let={activity} label={gettext("Actor")}>
              <.text_and_description_cell
                label={Audit.actor_label(activity)}
                description={activity.actor_email || actor_role_label(activity)}
              />
            </:col>
            <:col :let={activity} label={gettext("Interface")}>
              <.badge_cell
                label={interface_label(activity.interface)}
                color={interface_badge_color(activity.interface)}
                style="light-fill"
              />
            </:col>
            <:col :let={activity} label={gettext("Action")}>
              <.text_cell label={action_label(activity.action)} sublabel={activity.action} />
            </:col>
            <:col :let={activity} label={gettext("Target")}>
              <.link
                :if={activity_path(activity)}
                navigate={activity_path(activity)}
                data-part="target-link"
              >
                <.text_and_description_cell
                  label={activity.target_label || activity.target_id || "-"}
                  description={target_description(activity)}
                />
              </.link>
              <.text_and_description_cell
                :if={!activity_path(activity)}
                label={activity.target_label || activity.target_id || "-"}
                description={target_description(activity)}
              />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="history"
                title={gettext("No activity found")}
                subtitle={gettext("Adjust the filters or wait for new activity to be recorded.")}
              />
            </:empty_state>
          </.table>

          <div data-part="table-footer">
            <span id="admin-audit-count" data-part="count">
              {ngettext("%{count} activity", "%{count} activities", @activities_meta.total_count,
                count: @activities_meta.total_count
              )}
            </span>

            <.pagination_group
              :if={@activities_meta.total_pages > 1}
              id="admin-audit-pagination"
              current_page={@activities_meta.current_page}
              number_of_pages={@activities_meta.total_pages}
              page_patch={fn page -> "?#{Query.put(@uri.query, "page", page)}" end}
            />
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp audit_query_params(query, active_filters) do
    active_filters
    |> Filter.Operations.encode_filters_to_query()
    |> Query.put_present("q", Query.present_string(query))
  end

  defp audit_list_opts(query, active_filters, page) do
    [page: page, page_size: @page_size, query: Query.present_string(query)]
    |> put_active_filter(active_filters, "interface", :interface, :exclude_interface)
    |> put_active_filter(active_filters, "action", :action, :exclude_action)
    |> put_active_filter(active_filters, "target_type", :target_type, :exclude_target_type)
  end

  defp put_active_filter(opts, active_filters, filter_id, include_key, exclude_key) do
    case Enum.find(active_filters, &(&1.id == filter_id)) do
      %{operator: :==, value: value} -> put_option(opts, include_key, Query.present_string(value))
      %{operator: :!=, value: value} -> put_option(opts, exclude_key, Query.present_string(value))
      _filter -> opts
    end
  end

  defp put_option(opts, _key, nil), do: opts
  defp put_option(opts, key, value), do: Keyword.put(opts, key, value)

  defp current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp normalize_query_params(params) do
    params
    |> Query.copy_legacy_search("query", "q")
    |> Query.copy_legacy_filters(@legacy_filter_ids)
    |> Map.drop(["query" | @legacy_filter_ids])
  end

  defp uri_from_query_params(params) do
    case URI.encode_query(params) do
      "" -> URI.parse("")
      query -> URI.parse("?" <> query)
    end
  end

  defp define_filters do
    options = Audit.filter_options()

    [
      option_filter("interface", gettext("Interface"), options.interfaces, &interface_label/1, searchable: true),
      option_filter("action", gettext("Action"), options.actions, &action_label/1, searchable: true),
      option_filter("target_type", gettext("Target"), options.target_types, &target_label/1, searchable: true)
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp option_filter(id, display_name, options, formatter, opts) do
    options =
      options
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    %Filter.Filter{
      id: id,
      display_name: display_name,
      type: :option,
      options: options,
      options_display_names: Map.new(options, &{&1, formatter.(&1)}),
      operator: :==,
      searchable: Keyword.get(opts, :searchable, false),
      value: nil
    }
  end

  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M:%S UTC")
  defp format_datetime(_datetime), do: "-"

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
  defp format_date(_datetime), do: "-"

  defp actor_role_label(%Activity{actor_role: role}) when is_binary(role) and role != "", do: interface_label(role)
  defp actor_role_label(_activity), do: gettext("No actor")

  defp target_description(%Activity{target_type: nil}), do: "-"

  defp target_description(%Activity{target_type: type, target_id: id}) when is_binary(id) and id != "" do
    "#{target_label(type)} · #{id}"
  end

  defp target_description(%Activity{target_type: type}), do: target_label(type)

  defp activity_path(%Activity{} = activity),
    do: Audit.resource_path(activity.target_type, activity.target_id, activity.metadata)

  defp action_label(action) when is_binary(action) do
    action
    |> String.replace([".", "_"], " ")
    |> String.capitalize()
  end

  defp action_label(_action), do: "-"

  defp target_label(target) when is_binary(target) do
    target
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp target_label(_target), do: "-"

  defp interface_label(interface) when is_binary(interface) do
    interface
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp interface_label(_interface), do: "-"

  defp interface_badge_color("dashboard"), do: "information"
  defp interface_badge_color("mcp"), do: "focus"
  defp interface_badge_color("slack"), do: "success"
  defp interface_badge_color("api"), do: "secondary"
  defp interface_badge_color("worker"), do: "warning"
  defp interface_badge_color(_interface), do: "neutral"
end
