defmodule AtlasWeb.AcquisitionLive.Tables do
  @moduledoc """
  Search, sorting and filters for the Acquisition tables, with the server
  dashboard's controls. Each table keeps its state in the page URL under its
  own prefix (`channels_q`, `channels_sort_by`, `filter_channels_source_val`,
  ...), so several tables share one page without sharing state.
  """
  use Phoenix.Component
  use Noora
  use Gettext, backend: AtlasWeb.Gettext

  import Noora.Filter

  alias AtlasWeb.Utilities.Query
  alias Noora.Filter

  @tables ~w(campaigns channels subscriptions)
  @page_size 20

  def tables, do: @tables

  @doc "Every table's filters, with options from the funnel's rows, for Noora's filter events."
  def available_filters(funnel), do: Enum.flat_map(@tables, &filters(&1, funnel))

  @doc "The search, sort and filter state of `table` from the page's query parameters."
  def state(table, params, funnel) do
    options = sort_options(table)
    {default_sort, default_order} = default_sort(table)

    sort_by =
      if params[table <> "_sort_by"] in Enum.map(options, &elem(&1, 0)),
        do: params[table <> "_sort_by"],
        else: default_sort

    sort_order =
      if params[table <> "_sort_order"] in ~w(asc desc), do: params[table <> "_sort_order"], else: default_order

    query =
      if is_binary(params[table <> "_q"]), do: params[table <> "_q"] |> String.trim() |> String.slice(0, 120), else: ""

    available = filters(table, funnel)

    %{
      table: table,
      query: query,
      form: to_form(%{"query" => query, "table" => table}, as: :table_search),
      available_filters: available,
      active_filters: Filter.Operations.decode_filters_from_query(params, available),
      sort_by: sort_by,
      sort_order: sort_order,
      page: Query.parse_page(params[table <> "_page"]),
      sort_options: options
    }
  end

  @doc "The rows of `table` that match its search and filters, in its sort order."
  def apply(rows, state) do
    term = String.downcase(state.query)

    rows
    |> Enum.filter(fn row ->
      row |> search_text(state.table) |> String.downcase() |> String.contains?(term) and
        Enum.all?(state.active_filters, &matches?(row, &1, state.table))
    end)
    |> Enum.sort_by(&sort_value(&1, state.sort_by), sorter(state.sort_order))
  end

  @doc """
  Page `number` of `rows`, #{@page_size} to a page, as `%{rows, number,
  total_pages}`. A number past the last page shows the last page.
  """
  def paginate(rows, number) do
    total_pages = max(div(length(rows) + @page_size - 1, @page_size), 1)
    number = min(number, total_pages)
    %{rows: Enum.slice(rows, (number - 1) * @page_size, @page_size), number: number, total_pages: total_pages}
  end

  @doc "The query parameters that sort `state`'s table by `field`, flipping the order when it already does."
  def sort_params(state, field) do
    order =
      cond do
        state.sort_by == field and state.sort_order == "desc" -> "asc"
        state.sort_by == field -> "desc"
        true -> "desc"
      end

    %{(state.table <> "_sort_by") => field, (state.table <> "_sort_order") => order}
  end

  @doc "The column header patch and arrow for `field`, shown only on the sorted column as on the server."
  def column_sort(state, field, path_fun) do
    if state.sort_by == field, do: {path_fun.(sort_params(state, field)), state.sort_order}, else: {nil, false}
  end

  attr :state, :map, required: true
  attr :path, :any, required: true, doc: "A function from query parameter changes to a page path."

  def toolbar(assigns) do
    ~H"""
    <div data-part="table-toolbar" id={"acquisition-#{@state.table}-toolbar"}>
      <.form
        for={@state.form}
        id={"acquisition-#{@state.table}-search-form"}
        phx-change="search_table"
        phx-submit="search_table"
      >
        <input type="hidden" name="table_search[table]" value={@state.table} />
        <.text_input
          id={"acquisition-#{@state.table}-search"}
          field={@state.form[:query]}
          type="search"
          placeholder={gettext("Search...")}
          aria-label={gettext("Search table")}
          show_suffix={false}
          phx-debounce="200"
        />
      </.form>
      <.dropdown
        id={"acquisition-#{@state.table}-sort-by"}
        label={Map.new(@state.sort_options)[@state.sort_by]}
        secondary_text={gettext("Sort by:")}
      >
        <.dropdown_item
          :for={{field, label} <- @state.sort_options}
          value={field}
          label={label}
          patch={@path.(sort_params(@state, field))}
          data-selected={@state.sort_by == field}
        >
          <:right_icon :if={@state.sort_by == field}><.check /></:right_icon>
        </.dropdown_item>
      </.dropdown>
      <.filter_dropdown
        id={"acquisition-#{@state.table}-filter-dropdown"}
        label={gettext("Filter")}
        available_filters={@state.available_filters}
        active_filters={@state.active_filters}
      />
    </div>
    <div
      :if={@state.active_filters != []}
      id={"acquisition-#{@state.table}-active-filters"}
      data-part="active-filters"
    >
      <.active_filter :for={filter <- @state.active_filters} filter={filter} />
    </div>
    """
  end

  defp default_sort("subscriptions"), do: {"subscribed_on", "desc"}
  defp default_sort(_table), do: {"signups", "desc"}

  defp sort_options("campaigns") do
    [
      {"signups", gettext("Signups")},
      {"landings", gettext("Landings")},
      {"customers", gettext("Customers")},
      {"signup_rate", gettext("Signup rate")},
      {"customer_rate", gettext("Customer rate")},
      {"campaign", gettext("Campaign")}
    ]
  end

  defp sort_options("channels") do
    [
      {"signups", gettext("Signups")},
      {"landings", gettext("Landings")},
      {"customers", gettext("Customers")},
      {"signup_rate", gettext("Signup rate")},
      {"customer_rate", gettext("Customer rate")},
      {"source", gettext("Source")}
    ]
  end

  defp sort_options("subscriptions") do
    [
      {"subscribed_on", gettext("Subscribed")},
      {"signed_up_on", gettext("Signed up")},
      {"account", gettext("Account")},
      {"plan", gettext("Plan")}
    ]
  end

  defp filters(table, funnel) do
    rows = rows(table, funnel)

    case table do
      "campaigns" ->
        [option(table, "source", gettext("Source"), rows |> Enum.flat_map(& &1.sources) |> distinct())]

      "channels" ->
        [
          option(table, "source", gettext("Source"), distinct_field(rows, :source)),
          option(table, "medium", gettext("Medium"), distinct_field(rows, :medium)),
          option(table, "campaign", gettext("Campaign"), distinct_field(rows, :campaign)),
          option(table, "content", gettext("Ad"), distinct_field(rows, :content))
        ]

      "subscriptions" ->
        [
          option(table, "plan", gettext("Plan"), ~w(pro enterprise), %{
            "pro" => gettext("Pro"),
            "enterprise" => gettext("Enterprise")
          }),
          option(table, "status", gettext("Status"), ~w(active past_due), %{
            "active" => gettext("Active"),
            "past_due" => gettext("Past due")
          }),
          option(table, "source", gettext("Source"), distinct_field(rows, :source)),
          option(table, "campaign", gettext("Campaign"), distinct_field(rows, :campaign)),
          option(table, "content", gettext("Ad"), distinct_field(rows, :content))
        ]
    end
  end

  defp rows(table, %{} = funnel), do: Map.get(funnel, String.to_existing_atom(table), [])
  defp rows(_table, _funnel), do: []

  defp distinct_field(rows, field), do: rows |> Enum.map(&Map.fetch!(&1, field)) |> distinct()
  defp distinct(values), do: values |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq() |> Enum.sort()

  defp option(table, field, label, values, names \\ %{}) do
    %Filter.Filter{
      id: "#{table}_#{field}",
      display_name: label,
      type: :option,
      options: values,
      options_display_names: Map.new(values, &{&1, Map.get(names, &1, &1)}),
      operator: :==,
      value: nil,
      searchable: length(values) > 8
    }
  end

  defp matches?(_row, %{value: value}, _table) when value in [nil, ""], do: true

  defp matches?(row, filter, table) do
    field = String.replace_prefix(filter.id, table <> "_", "")

    match =
      case {table, field} do
        {"campaigns", "source"} -> filter.value in row.sources
        _ -> to_string(Map.get(row, String.to_existing_atom(field))) == filter.value
      end

    if filter.operator == :!=, do: not match, else: match
  end

  defp search_text(row, "campaigns"), do: Enum.join([row.campaign | row.sources ++ row.ads], " ")
  defp search_text(row, "channels"), do: Enum.join([row.source, row.medium, row.campaign, row.content], " ")

  defp search_text(row, "subscriptions"),
    do: Enum.join([row.account, row.plan, row.source, row.medium, row.campaign, row.content], " ")

  defp sort_value(row, "signup_rate"), do: rate(row.signups, row.landings)
  defp sort_value(row, "customer_rate"), do: rate(row.customers, row.signups)

  defp sort_value(row, field) when field in ~w(subscribed_on signed_up_on),
    do: Date.to_gregorian_days(Map.get(row, String.to_existing_atom(field)) || ~D[0000-01-01])

  defp sort_value(row, field), do: Map.fetch!(row, String.to_existing_atom(field))

  defp rate(_count, 0), do: -1.0
  defp rate(count, total), do: count / total

  defp sorter("asc"), do: :asc
  defp sorter(_order), do: :desc
end
