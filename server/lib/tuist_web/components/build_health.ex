defmodule TuistWeb.Components.BuildHealth do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.Components.AsyncCard

  alias Tuist.Utilities.DateFormatter

  attr :health, :any, required: true

  def cache_card(assigns) do
    ~H"""
    <.async_card
      :let={ready?}
      icon="chart_arcs"
      title={dgettext("dashboard_gradle", "Cache savings")}
      results={[@health]}
      id="gradle-cache-savings"
      data-part="analytics-card"
    >
      <div data-part="widgets">
        <.widget
          id="cache-work-avoided"
          title={dgettext("dashboard_gradle", "Estimated cache work avoided")}
          description={
            dgettext(
              "dashboard_gradle",
              "Cumulative task execution time avoided by cache hits. Parallel tasks can overlap, so this is not elapsed build time saved."
            )
          }
          loading={!ready?}
          value={
            if ready? && !is_nil(@health.result.totals["cache_work_avoided"]),
              do:
                DateFormatter.format_duration_from_milliseconds(
                  @health.result.totals["cache_work_avoided"]
                ),
              else: ""
          }
          empty={ready? && is_nil(@health.result.totals["cache_work_avoided"])}
          empty_label={dgettext("dashboard_gradle", "Not reported")}
        />
        <.widget
          id="cache-savings-coverage"
          title={dgettext("dashboard_gradle", "Reporting coverage")}
          description={
            dgettext(
              "dashboard_gradle",
              "Builds that reported an estimate, including recorded zero savings."
            )
          }
          loading={!ready?}
          value={
            if ready?,
              do:
                dgettext("dashboard_gradle", "%{reported} of %{total} builds",
                  reported:
                    TuistWeb.CldrHelpers.format_number(
                      @health.result.totals["cache_work_avoided_samples"]
                    ),
                  total: TuistWeb.CldrHelpers.format_number(@health.result.totals["builds"])
                ),
              else: ""
          }
        />
      </div>
    </.async_card>
    """
  end

  attr :category, :string, required: true

  def category_cell(assigns) do
    ~H"""
    <.badge_cell
      :if={@category in ["verification", "infrastructure_tooling", "unknown"]}
      label={category_label(@category)}
      color="neutral"
      style="light-fill"
    />
    <.text_cell
      :if={@category not in ["verification", "infrastructure_tooling", "unknown"]}
      label="—"
    />
    """
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
