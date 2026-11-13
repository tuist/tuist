defmodule TuistWeb.SandboxInstancesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.SandboxesLive, only: [flash_alerts: 1, sandboxes_table: 1]

  alias Noora.Filter
  alias Tuist.Sandboxes
  alias TuistWeb.SandboxesLive
  alias TuistWeb.Utilities.Query

  @refresh_interval 5_000
  @page_size 20
  @sorts ["created", "last_active", "name"]
  @statuses ~w(active idle starting resuming paused archived failed)a

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: user}} = socket) do
    SandboxesLive.ensure_available!(user, account)

    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok,
     assign(socket,
       head_title: "#{dgettext("dashboard_sandboxes", "Instances")} · #{account.name} · Tuist",
       available_filters: available_filters(account)
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    sort_by = if params["sort_by"] in @sorts, do: params["sort_by"], else: "created"

    {:noreply,
     socket
     |> assign(
       uri: URI.parse(uri),
       search: String.slice(params["search"] || "", 0, 200),
       active_filters: Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters),
       sort_by: sort_by,
       sort_order: if(params["sort_order"] in ["asc", "desc"], do: params["sort_order"], else: default_order(sort_by)),
       page: parse_page(params["page"])
     )
     |> load()}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket,
       to: list_path(socket, socket.assigns.uri.query |> Query.put("search", search) |> Query.drop("page"))
     )}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    params = Filter.Operations.add_filter_to_query(filter_id, socket, decoded_query(socket))

    {:noreply,
     socket
     |> push_patch(to: list_path(socket, params |> Map.delete("page") |> URI.encode_query()))
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    params = Filter.Operations.update_filters_in_query(params, socket, decoded_query(socket))

    {:noreply,
     socket
     |> push_patch(to: list_path(socket, params |> Map.delete("page") |> URI.encode_query()))
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load(socket)}
  end

  # `Filter.Operations` decodes `uri.query` itself, which raises on a URL
  # without one.
  defp decoded_query(%{assigns: %{uri: %URI{query: nil}}}), do: %{}
  defp decoded_query(%{assigns: %{uri: %URI{query: query}}}), do: URI.decode_query(query)

  defp list_path(socket, ""), do: "/#{socket.assigns.selected_account.name}/sandboxes/instances"
  defp list_path(socket, query), do: "/#{socket.assigns.selected_account.name}/sandboxes/instances?#{query}"

  defp load(%{assigns: %{selected_account: account, page: page}} = socket) do
    opts =
      [
        search: socket.assigns.search,
        sort_by: String.to_existing_atom(socket.assigns.sort_by),
        sort_order: String.to_existing_atom(socket.assigns.sort_order)
      ] ++ filter_opts(socket.assigns.active_filters)

    total_pages = max(1, ceil(Sandboxes.count_sandboxes(account, opts) / @page_size))
    page = min(page, total_pages)

    assign(socket,
      sandboxes: Sandboxes.list_sandboxes(account, opts ++ [limit: @page_size, offset: (page - 1) * @page_size]),
      page: page,
      total_pages: total_pages
    )
  end

  defp filter_opts(filters) do
    for %{id: id, operator: operator, value: value} <- filters,
        operator in [:==, :!=],
        not is_nil(value),
        opt = filter_opt(id, operator, value),
        do: opt
  end

  defp filter_opt("status", operator, status) when status in @statuses, do: {:status, {operator, status}}
  defp filter_opt("vcpus", operator, vcpus) when is_integer(vcpus), do: {:vcpus, {operator, vcpus}}
  defp filter_opt(_id, _operator, _value), do: nil

  defp available_filters(account) do
    vcpus = Sandboxes.sandbox_vcpus(account)

    [
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_sandboxes", "Status"),
        type: :option,
        options: @statuses,
        options_display_names: %{
          active: dgettext("dashboard_sandboxes", "Active"),
          idle: dgettext("dashboard_sandboxes", "Idle"),
          starting: dgettext("dashboard_sandboxes", "Starting"),
          resuming: dgettext("dashboard_sandboxes", "Resuming"),
          paused: dgettext("dashboard_sandboxes", "Paused"),
          archived: dgettext("dashboard_sandboxes", "Archived"),
          failed: dgettext("dashboard_sandboxes", "Failed")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "vcpus",
        field: :vcpus,
        display_name: dgettext("dashboard_sandboxes", "vCPUs"),
        type: :option,
        options: vcpus,
        options_display_names: Map.new(vcpus, &{&1, Integer.to_string(&1)}),
        operator: :==,
        value: nil
      }
    ]
  end

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  defp default_order("name"), do: "asc"
  defp default_order(_sort_by), do: "desc"

  def sort_options do
    [
      {"created", dgettext("dashboard_sandboxes", "Created")},
      {"last_active", dgettext("dashboard_sandboxes", "Last active")},
      {"name", dgettext("dashboard_sandboxes", "Instance")}
    ]
  end

  def sort_label(sort_by), do: sort_options() |> List.keyfind(sort_by, 0) |> elem(1)

  @doc """
  The patch for sorting by `column`: choosing the current one flips its
  order, another starts in its default order. Either goes back to the first
  page.
  """
  def sort_patch(assigns, column) do
    order =
      if assigns.sort_by == column,
        do: if(assigns.sort_order == "asc", do: "desc", else: "asc"),
        else: default_order(column)

    "?" <>
      (assigns.uri.query
       |> Query.put("sort_by", column)
       |> Query.put("sort_order", order)
       |> Query.drop("page"))
  end

  def page_patch(uri, page), do: "?" <> Query.put(uri.query, "page", Integer.to_string(page))
end
