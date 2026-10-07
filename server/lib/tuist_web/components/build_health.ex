defmodule TuistWeb.Components.BuildHealth do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.Components.AsyncCard

  alias Tuist.Utilities.DateFormatter

  attr :health, :any, required: true
  attr :account, :any, required: true
  attr :project, :any, required: true

  def failure_card(assigns) do
    ~H"""
    <.async_card
      :let={ready?}
      :if={@health}
      icon="alert_circle"
      title={dgettext("dashboard_builds", "Failure categories")}
      results={[@health]}
      id="build-failure-categories"
    >
      <.card_section>
        <%= if ready? do %>
          <.table
            id="build-failure-category-counts"
            rows={@health.result.categories}
            row_key={fn row -> row.category end}
          >
            <:col :let={row} label={dgettext("dashboard_builds", "Category")}>
              <.text_cell label={category_label(row.category)} />
            </:col>
            <:col :let={row} label={dgettext("dashboard_builds", "Failed builds")}>
              <.text_cell label={TuistWeb.CldrHelpers.format_number(row.builds)} />
            </:col>
          </.table>
          <h3>{dgettext("dashboard_builds", "Recent failed builds")}</h3>
          <.table
            id="build-category-failures"
            rows={@health.result.failures}
            row_key={fn row -> "failure-#{row.id}" end}
            row_navigate={fn row -> build_path(@account, @project, row) end}
          >
            <:col :let={row} label={dgettext("dashboard_builds", "Build")}>
              <.text_cell label={build_label(row)} />
            </:col>
            <:col :let={row} label={dgettext("dashboard_builds", "Category")}>
              <.text_cell label={category_label(row.failure_category)} />
            </:col>
            <:col :let={row} label={dgettext("dashboard_builds", "Branch")}>
              <.text_cell label={row.git_branch} />
            </:col>
            <:col :let={row} label={dgettext("dashboard_builds", "Duration")}>
              <.text_cell label={
                if is_nil(row.duration_ms),
                  do: dgettext("dashboard_builds", "Not reported"),
                  else: DateFormatter.format_duration_from_milliseconds(row.duration_ms)
              } />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="check"
                title={dgettext("dashboard_builds", "No failed builds")}
                subtitle={
                  dgettext(
                    "dashboard_builds",
                    "No failures were recorded for the selected period and filters."
                  )
                }
              />
            </:empty_state>
          </.table>
          <p>
            {dgettext(
              "dashboard_builds",
              "Showing the latest 100 failed builds. Failures without enough recorded evidence remain unclassified."
            )}
          </p>
        <% else %>
          <p>{dgettext("dashboard_builds", "Loading failure categories…")}</p>
        <% end %>
      </.card_section>
    </.async_card>
    """
  end

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

  defp build_label(row) do
    case row.requested_tasks |> Enum.join(" ") |> String.trim() do
      "" -> dgettext("dashboard_builds", "Not reported")
      label -> label
    end
  end

  defp category_label("verification"), do: dgettext("dashboard_builds", "Verification")
  defp category_label("infrastructure_tooling"), do: dgettext("dashboard_builds", "Infrastructure / tooling")
  defp category_label(_), do: dgettext("dashboard_builds", "Unclassified")

  defp build_path(account, project, %{build_system: "bazel", id: id}),
    do: ~p"/#{account.name}/#{project.name}/builds/invocations/#{id}"

  defp build_path(account, project, %{build_system: "once", id: id}),
    do: ~p"/#{account.name}/#{project.name}/once/runs/#{id}"

  defp build_path(account, project, %{id: id}), do: ~p"/#{account.name}/#{project.name}/builds/build-runs/#{id}"
end
