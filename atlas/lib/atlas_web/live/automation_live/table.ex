defmodule AtlasWeb.AutomationLive.Table do
  @moduledoc "Shared server-style controls and independently scoped URL state for every Automation table."
  use Phoenix.Component
  use Noora
  use Gettext, backend: AtlasWeb.Gettext

  import Noora.Filter

  alias Noora.Filter

  @filter_ids ~w(domain effect permission approval status trigger language workflow reviewer config_behavior_type)
  @query_keys ~w(q sort_by sort_order config_q config_sort_by config_sort_order) ++
                Enum.flat_map(@filter_ids, &["filter_#{&1}_op", "filter_#{&1}_val"])

  def query_keys, do: @query_keys

  def state(section, params, types, prefix \\ "") do
    available = Enum.map(filters(section, types), &%{&1 | id: prefix <> &1.id})
    options = sort_options(section)
    default = if section == "behaviors", do: "name", else: "created"

    sort_by =
      if params[prefix <> "sort_by"] in Enum.map(options, &elem(&1, 0)), do: params[prefix <> "sort_by"], else: default

    default_order = if section == "behaviors", do: "asc", else: "desc"
    order = if params[prefix <> "sort_order"] in ~w(asc desc), do: params[prefix <> "sort_order"], else: default_order

    query =
      if is_binary(params[prefix <> "q"]), do: params[prefix <> "q"] |> String.trim() |> String.slice(0, 120), else: ""

    %{
      prefix: prefix,
      query: query,
      form: to_form(%{"query" => query}, as: :table_search),
      available_filters: available,
      active_filters: Filter.Operations.decode_filters_from_query(params, available),
      sort_by: sort_by,
      sort_order: order,
      sort_options: options
    }
  end

  def list_params(state) do
    Enum.reduce(
      state.active_filters,
      %{"q" => state.query, "sort_by" => state.sort_by, "sort_order" => state.sort_order},
      fn filter, acc ->
        id = String.replace_prefix(filter.id, state.prefix, "")
        acc |> Map.put(id, filter.value) |> Map.put("#{id}_op", to_string(filter.operator))
      end
    )
  end

  def types(types, state) do
    term = String.downcase(state.query)

    types
    |> Enum.filter(fn type ->
      String.contains?(
        String.downcase(Enum.join([type.reference, type.domain, type.description | type.permissions], " ")),
        term
      ) and
        Enum.all?(state.active_filters, &matches?(type, &1))
    end)
    |> Enum.sort_by(
      &{sort_value(&1, state.sort_by), &1.name, &1.version},
      if(state.sort_order == "asc", do: :asc, else: :desc)
    )
  end

  defp matches?(_type, %{value: value}) when value in [nil, ""], do: true

  defp matches?(type, filter) do
    match =
      case filter.id do
        "permission" -> filter.value in type.permissions
        "approval" -> to_string(type.requires_approval) == filter.value
        "domain" -> type.domain == filter.value
        "effect" -> type.effect == filter.value
      end

    if filter.operator == :!=, do: not match, else: match
  end

  defp sort_value(type, "name"), do: type.name
  defp sort_value(type, "domain"), do: type.domain
  defp sort_value(type, "effect"), do: type.effect
  defp sort_value(type, "version"), do: type.version
  defp sort_value(type, "approval"), do: type.requires_approval
  defp sort_value(type, "permissions"), do: Enum.join(type.permissions, ", ")

  def path(section, params), do: "/automation/#{section}?#{URI.encode_query(params)}"

  def sort_path(section, params, state, field) do
    order =
      cond do
        state.sort_by == field and state.sort_order == "asc" -> "desc"
        state.sort_by == field -> "asc"
        field == "created" -> "desc"
        true -> "asc"
      end

    params = if section == "behaviors" and state.prefix == "", do: params, else: Map.delete(params, "page")
    params = Map.merge(params, %{(state.prefix <> "sort_by") => field, (state.prefix <> "sort_order") => order})
    path(section, params)
  end

  def filtered?(state), do: state.query != "" or Enum.any?(state.active_filters, &(&1.value not in [nil, ""]))

  attr :id, :string, required: true
  attr :state, :map, required: true
  attr :section, :string, required: true
  attr :params, :map, required: true

  def toolbar(assigns) do
    ~H"""
    <div data-part="table-toolbar" id={@id <> "-toolbar"}>
      <.form
        for={@state.form}
        id={@id <> "-search-form"}
        phx-change="search_table"
        phx-submit="search_table"
      >
        <input type="hidden" name="table_prefix" value={@state.prefix} />
        <.text_input
          id={@id <> "-search"}
          field={@state.form[:query]}
          type="search"
          placeholder={gettext("Search...")}
          aria-label={gettext("Search table")}
          show_suffix={false}
          phx-debounce="200"
        />
      </.form>
      <.dropdown
        id={@id <> "-sort-by"}
        label={Map.new(@state.sort_options)[@state.sort_by]}
        secondary_text={gettext("Sort by:")}
      >
        <.dropdown_item
          :for={{field, label} <- @state.sort_options}
          value={field}
          label={label}
          patch={sort_path(@section, @params, @state, field)}
          data-selected={@state.sort_by == field}
        >
          <:right_icon :if={@state.sort_by == field}><.check /></:right_icon>
        </.dropdown_item>
      </.dropdown>
      <.filter_dropdown
        id={@id <> "-filter-dropdown"}
        label={gettext("Filter")}
        available_filters={@state.available_filters}
        active_filters={@state.active_filters}
      />
    </div>
    <div :if={@state.active_filters != []} id={@id <> "-active-filters"} data-part="active-filters">
      <.active_filter :for={filter <- @state.active_filters} filter={filter} />
    </div>
    """
  end

  defp sort_options("behaviors"),
    do: [
      {"name", gettext("Type")},
      {"domain", gettext("Domain")},
      {"effect", gettext("Effect")},
      {"version", gettext("Version")},
      {"permissions", gettext("Permissions")},
      {"approval", gettext("Approval")}
    ]

  defp sort_options("workflows"),
    do: [
      {"name", gettext("Name")},
      {"status", gettext("Status")},
      {"language", gettext("Language")},
      {"created", gettext("Created")}
    ]

  defp sort_options("configurations"),
    do: [{"name", gettext("Name")}, {"type", gettext("Behavior type")}, {"created", gettext("Created")}]

  defp sort_options("schedules"),
    do: [
      {"name", gettext("Name")},
      {"workflow", gettext("Workflow")},
      {"status", gettext("Status")},
      {"cron", gettext("Schedule")},
      {"next_run", gettext("Next run")},
      {"created", gettext("Created")}
    ]

  defp sort_options("webhooks"),
    do: [
      {"name", gettext("Name")},
      {"workflow", gettext("Workflow")},
      {"status", gettext("Status")},
      {"endpoint", gettext("Endpoint")},
      {"created", gettext("Created")}
    ]

  defp sort_options("approvals"),
    do: [
      {"name", gettext("Name")},
      {"workflow", gettext("Workflow")},
      {"status", gettext("Status")},
      {"reviewer", gettext("Reviewer")},
      {"created", gettext("Created")}
    ]

  defp sort_options(_),
    do: [
      {"created", gettext("Created")},
      {"workflow", gettext("Workflow")},
      {"status", gettext("Status")},
      {"trigger", gettext("Trigger")}
    ]

  defp filters("behaviors", types) do
    [
      option("domain", gettext("Domain"), types |> Enum.map(& &1.domain) |> Enum.uniq() |> Enum.sort()),
      option("effect", gettext("Effect"), ~w(read write compute), %{
        "read" => gettext("Read"),
        "write" => gettext("Write"),
        "compute" => gettext("Compute")
      }),
      option(
        "permission",
        gettext("Permissions"),
        types |> Enum.flat_map(& &1.permissions) |> Enum.uniq() |> Enum.sort()
      ),
      option("approval", gettext("Approval"), ~w(true false), %{
        "true" => gettext("Required"),
        "false" => gettext("Not required")
      })
    ]
  end

  defp filters("executions", _) do
    [
      option("status", gettext("Status"), ~w(queued running waiting_approval succeeded failed rejected cancelled), %{
        "queued" => gettext("Queued"),
        "running" => gettext("Running"),
        "waiting_approval" => gettext("Waiting for approval"),
        "succeeded" => gettext("Succeeded"),
        "failed" => gettext("Failed"),
        "rejected" => gettext("Rejected"),
        "cancelled" => gettext("Cancelled")
      }),
      option("trigger", gettext("Trigger"), ~w(manual schedule webhook), %{
        "manual" => gettext("Manual"),
        "schedule" => gettext("Schedule"),
        "webhook" => gettext("Webhook")
      })
    ]
  end

  defp filters("workflows", _) do
    [
      option("status", gettext("Status"), ~w(published draft), %{
        "published" => gettext("Published"),
        "draft" => gettext("Not published")
      }),
      option("language", gettext("Language"), ~w(json javascript), %{"json" => "JSON", "javascript" => "JavaScript"})
    ]
  end

  defp filters("configurations", types) do
    [
      option(
        "behavior_type",
        gettext("Behavior type"),
        types |> Enum.flat_map(&[&1.reference, &1.name, "#{&1.name}@#{&1.version}"]) |> Enum.uniq() |> Enum.sort()
      )
    ]
  end

  defp filters("approvals", _) do
    [
      option("status", gettext("Status"), ~w(pending approved rejected cancelled), %{
        "pending" => gettext("Pending"),
        "approved" => gettext("Approved"),
        "rejected" => gettext("Rejected"),
        "cancelled" => gettext("Cancelled")
      }),
      text("workflow", gettext("Workflow")),
      text("reviewer", gettext("Reviewer"))
    ]
  end

  defp filters(section, _) when section in ~w(schedules webhooks) do
    [
      option("status", gettext("Status"), ~w(enabled paused), %{
        "enabled" => gettext("Enabled"),
        "paused" => gettext("Paused")
      }),
      text("workflow", gettext("Workflow"))
    ]
  end

  defp filters(_, _), do: []

  defp text(id, label), do: %Filter.Filter{id: id, display_name: label, type: :text, operator: :=~, value: nil}

  defp option(id, label, values, names \\ %{}) do
    %Filter.Filter{
      id: id,
      display_name: label,
      type: :option,
      options: values,
      options_display_names: Map.new(values, &{&1, Map.get(names, &1, &1)}),
      operator: :==,
      value: nil,
      searchable: length(values) > 8
    }
  end
end
