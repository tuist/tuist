defmodule TuistWeb.Components.ChartTypeToggle do
  @moduledoc false
  use Phoenix.Component
  use Noora
  use Gettext, backend: TuistWeb.Gettext

  alias TuistWeb.Utilities.Query

  attr(:id, :string, required: true, doc: "Unique ID prefix for the component elements.")
  attr(:chart_type, :string, required: true, doc: "Current chart type.")
  attr(:chart_types, :list, default: ~w(line scatter), doc: "Available chart types, in display order.")
  attr(:chart_type_event, :string, required: true, doc: "Event name for toggling the chart type.")

  attr(:group_by_options, :list,
    default: [],
    doc: "List of %{value: string, label: string} maps for the Group by dropdown. Empty means no dropdown."
  )

  attr(:selected_group_by, :string, default: nil, doc: "Currently selected group by value.")

  attr(:group_by_query_param, :string,
    default: nil,
    doc: "URL query param name for the group by selection."
  )

  attr(:uri, URI, required: true, doc: "Current URI for building patch URLs.")

  def chart_type_toggle(assigns) do
    ~H"""
    <div class="tuist-chart-type-toggle">
      <.dropdown
        :if={@chart_type == "scatter" and @group_by_options != []}
        id={"#{@id}-group-by-dropdown"}
        size="medium"
        label={
          Enum.find_value(@group_by_options, fn opt ->
            if opt.value == @selected_group_by, do: opt.label
          end) || List.first(@group_by_options).label
        }
        secondary_text={gettext("Group by:")}
      >
        <.dropdown_item
          :for={option <- @group_by_options}
          value={option.value}
          label={option.label}
          patch={"?#{Query.put(@uri.query, @group_by_query_param, option.value)}"}
          data-selected={@selected_group_by == option.value}
        >
          <:right_icon :if={@selected_group_by == option.value}><.check /></:right_icon>
        </.dropdown_item>
      </.dropdown>
      <.button_group size="medium">
        <.button_group_item
          :for={type <- @chart_types}
          label={chart_type_label(type)}
          phx-click={@chart_type_event}
          phx-value-type={type}
          data-selected={@chart_type == type}
        />
      </.button_group>
    </div>
    """
  end

  defp chart_type_label("line"), do: gettext("Line")
  defp chart_type_label("scatter"), do: gettext("Scatter plot")
  defp chart_type_label("bar"), do: gettext("Bar")
end
