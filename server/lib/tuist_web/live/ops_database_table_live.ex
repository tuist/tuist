defmodule TuistWeb.OpsDatabaseTableLive do
  @moduledoc """
  Per-table browser at `/ops/db/tables/:schema/:name`. The detail page
  the tables tab links into: a Supabase-style row preview for a
  specific table, with single-column sort + Noora.Filter-backed filter
  chips layered on top.

  Read-only by construction — every row-preview query goes through
  `Tuist.Ops.Database.preview_table_rows/3`, which wraps the SELECT in
  a `BEGIN READ ONLY` transaction with a 5s statement timeout. The
  identifier from the URL is validated against `information_schema`
  before being spliced into a SQL statement, so a hand-crafted URL
  can't smuggle through arbitrary SQL on the relation name. Filter
  values bind as `$N` rather than splicing into the SQL string.

  Filter UI uses Noora's standard `<.filter_dropdown>` + `<.active_filter>`
  components and the matching `Noora.Filter.Operations` helpers —
  the same flow every other filterable table in the dashboard uses
  (generate_runs, build_runs, bundles, etc.), so the look and the URL
  shape (`filter_<id>_op`, `filter_<id>_val`) match the rest of the app.
  """
  use TuistWeb, :live_view
  use Noora

  alias Noora.Filter
  alias Tuist.Ops.Database
  alias TuistWeb.Utilities.Query

  @page_size 20
  @tabs ~w(rows columns)

  @impl true
  def mount(%{"schema" => schema, "name" => name}, _session, socket) do
    if Database.table_exists?(schema, name) do
      columns = Database.list_table_columns(schema, name)
      column_names = Enum.map(columns, & &1["name"])

      {:ok,
       socket
       |> assign(:head_title, "#{schema}.#{name} · Tuist Ops")
       |> assign(:schema, schema)
       |> assign(:name, name)
       |> assign(:columns, columns)
       |> assign(:column_names, column_names)
       |> assign(:available_filters, define_filters(columns))
       |> assign(:estimated_rows, Database.estimated_row_count(schema, name))
       |> assign(:size_pretty, Database.table_size_pretty(schema, name))
       |> assign(:page, 1)
       |> assign(:tab, "rows")
       # Pre-seed the sort column to the first column so the dropdown
       # label always reads "Sort by: <real column>" — no special-case
       # "Default" label that requires the operator to guess what's
       # going on.
       |> assign(:sort_column, List.first(column_names))
       |> assign(:sort_dir, :asc)
       |> assign(:active_filters, [])
       |> assign(:preview, nil)
       |> assign(:preview_error, nil)
       |> assign(:uri, URI.new!("/ops/db"))}
    else
      {:ok,
       socket
       |> put_flash(:error, dgettext("dashboard", "Table not found."))
       |> push_navigate(to: ~p"/ops/db?section=tables")}
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    parsed = URI.parse(uri)
    params = Query.query_params(uri)

    sort_column =
      params["sort"]
      |> pick(socket.assigns.column_names)
      |> case do
        nil -> List.first(socket.assigns.column_names)
        col -> col
      end

    sort_dir = parse_dir(params["dir"])
    page = parse_page(params["page"])
    tab = if params["tab"] in @tabs, do: params["tab"], else: "rows"
    active_filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    base =
      socket
      |> assign(:uri, parsed)
      |> assign(:tab, tab)
      |> assign(:page, page)
      |> assign(:sort_column, sort_column)
      |> assign(:sort_dir, sort_dir)
      |> assign(:active_filters, active_filters)

    # Only run the row-preview SELECT when the Rows tab is showing; the
    # Columns tab doesn't need the query and an oversized table would
    # otherwise spin up a 5s read transaction on every tab switch.
    if tab == "rows" do
      preview_opts = [
        page: page,
        page_size: @page_size,
        sort_column: sort_column,
        sort_dir: sort_dir,
        filters: active_filters
      ]

      case Database.preview_table_rows(socket.assigns.schema, socket.assigns.name, preview_opts) do
        {:ok, preview} ->
          {:noreply, base |> assign(:preview, preview) |> assign(:preview_error, nil)}

        {:error, reason} ->
          {:noreply, base |> assign(:preview, nil) |> assign(:preview_error, format_error(reason))}
      end
    else
      {:noreply, base |> assign(:preview, nil) |> assign(:preview_error, nil)}
    end
  end

  # Filter add/update/delete events all go through the Noora.Filter
  # Operations helpers and patch the page URL — same shape as every
  # other filterable table page in the dashboard. The trailing
  # `push_event("close-dropdown", all: true)` matches the pattern in
  # shards_live / build_run_live / etc.: after the patch swaps the
  # active-filter chip's DOM, any popover left open from the chip's
  # previous render orphans from its anchor and jumps to an odd
  # position. Closing all open dropdowns on the server side keeps the
  # UI clean.
  @impl true
  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(to: build_url(socket.assigns.schema, socket.assigns.name, params))
     |> push_event("close-dropdown", %{all: true})}
  end

  def handle_event("update_filter", params, socket) do
    updated = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: build_url(socket.assigns.schema, socket.assigns.name, updated))
     |> push_event("close-dropdown", %{all: true})}
  end

  # One %Noora.Filter.Filter{} per table column. Default to text type
  # with `contains` (`:=~`) — Postgres's `::text` cast in the SQL
  # builder lets a text filter run against any column type, so we
  # don't have to introspect Postgres column types to pick between
  # `:text` / `:number` here.
  defp define_filters(columns) do
    Enum.map(columns, fn col ->
      %Filter.Filter{
        id: col["name"],
        field: String.to_atom(col["name"]),
        display_name: col["name"],
        type: :text,
        operator: :=~,
        value: ""
      }
    end)
  end

  defp pick(nil, _allowed), do: nil
  defp pick(value, allowed), do: if(value in allowed, do: value)

  defp parse_dir("desc"), do: :desc
  defp parse_dir(_), do: :asc

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {p, _} when p > 0 -> p
      _ -> 1
    end
  end

  defp format_error(:no_columns), do: "The table has no columns to preview."
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  @doc "Page URL preserving the current sort + filter state."
  def page_patch(schema, name, page, %{uri: %URI{query: query}}) do
    params =
      (query || "")
      |> URI.decode_query()
      |> Map.put("page", to_string(page))

    build_url(schema, name, params)
  end

  @doc "Sort URL — picking a new column resets the page; same column flips direction."
  def sort_patch(schema, name, column, %{uri: %URI{query: query}, sort_column: cur_col, sort_dir: cur_dir}) do
    next_dir = if cur_col == column and cur_dir == :asc, do: "desc", else: "asc"

    params =
      (query || "")
      |> URI.decode_query()
      |> Map.put("sort", column)
      |> Map.put("dir", next_dir)
      |> Map.put("page", "1")

    build_url(schema, name, params)
  end

  @doc """
  Tab URL — preserves the current sort/filter/page state when
  switching between Rows and Columns so refreshing the page or
  bouncing between tabs doesn't drop the operator's filter context.
  """
  def tab_patch(schema, name, tab, %{uri: %URI{query: query}}) do
    params =
      (query || "")
      |> URI.decode_query()
      |> Map.put("tab", tab)

    build_url(schema, name, params)
  end

  defp build_url(schema, name, params) do
    base = "/ops/db/tables/#{URI.encode(schema)}/#{URI.encode(name)}"

    query =
      params
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> URI.encode_query()

    if query == "", do: base, else: base <> "?" <> query
  end

  @doc "Total page count for the row pager."
  def total_pages(estimated_rows) do
    estimated_rows
    |> Kernel./(@page_size)
    |> Float.ceil()
    |> trunc()
    |> max(1)
    |> min(5_000)
  end

  @doc "Page size — exposed for the template."
  def page_size, do: @page_size

  # Same formatter as the SQL editor's result table so cell rendering
  # stays consistent across both surfaces.
  defdelegate format_cell(value), to: TuistWeb.OpsDatabaseLive
end
