defmodule TuistWeb.Components.BuildHealth do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.Components.AsyncCard
  import TuistWeb.Components.EmptyCardSection

  alias Tuist.Utilities.DateFormatter

  attr :health, :any, required: true
  attr :selected, :boolean, default: false

  def cache_widget(assigns) do
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
      phx_click="select_widget"
      phx_value_widget="cache_work_avoided"
      selected={@selected}
    />
    """
  end

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
      <span data-part="heading">{dgettext("dashboard_builds", "Failure category")}</span>
      <.badge label={category_label(@category)} color="neutral" style="light-fill" />
      <p>{category_description(@category)}</p>
    </div>
    """
  end

  defp category_description("verification") do
    dgettext(
      "dashboard_builds",
      "Tuist classifies failures using recorded build data. Verification includes compilation, test, lint and check errors."
    )
  end

  defp category_description("infrastructure_tooling") do
    dgettext(
      "dashboard_builds",
      "Tuist classifies failures using recorded build data. Infrastructure and tooling includes configuration, dependency resolution and execution infrastructure errors."
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
