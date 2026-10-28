defmodule TuistWeb.Components.BuildHealth do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.Components.AsyncCard
  import TuistWeb.Components.EmptyCardSection

  alias Tuist.Utilities.DateFormatter

  attr :health, :any, required: true
  attr :selected, :boolean, default: false

  attr :trend_label, :string, default: nil

  def cache_widget(assigns) do
    trend =
      if assigns.health.ok? do
        current = assigns.health.result.totals["cache_work_avoided"]
        previous = Map.get(assigns.health.result, :previous_totals, %{})["cache_work_avoided"]
        cache_trend(current, previous)
      else
        {nil, nil}
      end

    assigns = assign(assigns, :trend, trend)

    ~H"""
    <.widget
      id="cache-work-avoided"
      title={dgettext("dashboard_gradle", "Cumulative task time saved")}
      legend_color="p90"
      description={
        dgettext(
          "dashboard_gradle",
          "Estimated task execution time saved by cache hits. Parallel tasks can overlap, so this is not elapsed build time saved. Only builds with a reported estimate are included."
        )
      }
      loading={!@health.ok?}
      value={
        if @health.ok? && !is_nil(@health.result.totals["cache_work_avoided"]),
          do:
            DateFormatter.format_duration_from_milliseconds(
              @health.result.totals["cache_work_avoided"]
            ),
          else: ""
      }
      empty={@health.ok? && is_nil(@health.result.totals["cache_work_avoided"])}
      empty_label={dgettext("dashboard_gradle", "Not reported")}
      trend_value={elem(@trend, 0)}
      trend_value_label={elem(@trend, 1)}
      trend_type={:neutral}
      trend_label={
        if @health.ok? &&
             !is_nil(Map.get(@health.result, :previous_totals, %{})["cache_work_avoided"]),
           do: @trend_label
      }
      phx_click="select_widget"
      phx_value_widget="cache_work_avoided"
      selected={@selected}
    />
    """
  end

  defp cache_trend(nil, _previous), do: {nil, nil}
  defp cache_trend(_current, nil), do: {0, dgettext("dashboard_gradle", "No comparison available")}
  defp cache_trend(0, 0), do: {0, nil}

  defp cache_trend(current, 0) do
    {1, "+" <> DateFormatter.format_duration_from_milliseconds(current)}
  end

  defp cache_trend(current, previous), do: {(current - previous) / previous * 100, nil}

  attr :health, :any, required: true

  attr :preset, :string, default: "last-30-days"

  def cache_chart(assigns) do
    ~H"""
    <.async_section :let={ready?} results={[@health]}>
      <.card_section
        :if={!ready? || !is_nil(@health.result.totals["cache_work_avoided"])}
        data-chart-frame="standard"
      >
        <TuistWeb.Components.Skeleton.skeleton_chart :if={!ready?} />
        <.chart
          :if={ready? && !is_nil(@health.result.totals["cache_work_avoided"])}
          id="gradle-task-time-saved-chart"
          type="line"
          extra_options={
            %{
              grid: %{width: "93%", left: "0.4%", right: "7%", height: "88%", top: "5%"},
              xAxis: %{
                type: "category",
                boundaryGap: false,
                axisLabel: %{
                  formatter:
                    if(@preset == "last-24-hours", do: "fn:toLocaleDateHour", else: "fn:toLocaleDate")
                }
              },
              yAxis: %{axisLabel: %{formatter: "fn:formatMilliseconds"}},
              tooltip: %{
                valueFormat: "fn:formatMilliseconds",
                dateFormat: if(@preset == "last-24-hours", do: "hour", else: "date")
              },
              legend: %{show: false}
            }
          }
          series={[
            %{
              name: dgettext("dashboard_gradle", "Cumulative task time saved"),
              data:
                Enum.zip_with(
                  @health.result.dates,
                  @health.result.series["cache_work_avoided"],
                  fn date, value ->
                    [date |> DateTime.from_unix!() |> DateTime.to_iso8601(), value]
                  end
                ),
              type: "line",
              smooth: 0.1,
              symbol: "circle",
              symbolSize: 6,
              color: "var:noora-chart-p90"
            }
          ]}
          y_axis_min={0}
        />
      </.card_section>
      <.empty_card_section
        :if={ready? && is_nil(@health.result.totals["cache_work_avoided"])}
        title={dgettext("dashboard_gradle", "No task time estimates reported for this period.")}
        data-chart-frame="standard"
      >
        <:image>
          <img
            src={~p"/images/empty_line_chart_light.png"}
            data-theme="light"
            loading="lazy"
            decoding="async"
          />
          <img
            src={~p"/images/empty_line_chart_dark.png"}
            data-theme="dark"
            loading="lazy"
            decoding="async"
          />
        </:image>
      </.empty_card_section>
    </.async_section>
    """
  end

  attr :category, :string, default: nil

  def category_detail(assigns) do
    ~H"""
    <div
      :if={@category in ["verification", "infrastructure_tooling", "unknown"]}
      class="tuist-failure-classification"
    >
      <div data-part="heading">
        <span>{dgettext("dashboard_builds", "Failure category")}</span>
        <.tooltip
          id="build-failure-category-hint"
          title={dgettext("dashboard_builds", "Failure category")}
          description={category_description(@category)}
          size="large"
        >
          <:trigger :let={attrs}>
            <button
              {attrs}
              type="button"
              aria-label={dgettext("dashboard_builds", "About failure category")}
            >
              <.alert_circle />
            </button>
          </:trigger>
        </.tooltip>
      </div>
      <.badge label={category_label(@category)} color="neutral" style="light-fill" />
    </div>
    """
  end

  defp category_description("verification") do
    dgettext(
      "dashboard_builds",
      "Inferred from recorded build data. Verification covers compilation, test, lint, and check failures."
    )
  end

  defp category_description("infrastructure_tooling") do
    dgettext(
      "dashboard_builds",
      "Inferred from recorded build data. Infrastructure and tooling covers configuration, dependency resolution, and execution infrastructure failures."
    )
  end

  defp category_description("unknown") do
    dgettext(
      "dashboard_builds",
      "The recorded build data does not contain enough evidence for Tuist to classify this failure as verification or infrastructure and tooling."
    )
  end

  def category_filter do
    %Noora.Filter.Filter{
      id: "failure_category",
      field: :failure_category,
      display_name: dgettext("dashboard_builds", "Failure category"),
      type: :option,
      options: ["verification", "infrastructure_tooling", "unknown"],
      options_display_names: Map.new(["verification", "infrastructure_tooling", "unknown"], &{&1, category_label(&1)}),
      operator: :==,
      value: nil
    }
  end

  def category_label("verification"), do: dgettext("dashboard_builds", "Verification")
  def category_label("infrastructure_tooling"), do: dgettext("dashboard_builds", "Infrastructure / tooling")
  def category_label("unknown"), do: dgettext("dashboard_builds", "Unclassified")
  def category_label(_), do: "—"
end
