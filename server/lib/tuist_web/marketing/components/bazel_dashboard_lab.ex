defmodule TuistWeb.Marketing.Components.BazelDashboardLab do
  @moduledoc """
  A live, read-only slice of the Bazel overview dashboard, embedded in the
  Bazel announcement post. It renders the same components the dashboard uses
  (cards, widgets, legends, and charts) with data from
  `Tuist.Marketing.BazelShowcase`, which only exposes aggregates for a single
  configured project.
  """
  use TuistWeb, :live_component
  use Noora

  alias Tuist.Marketing.BazelShowcase
  alias Tuist.Utilities.DateFormatter

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:project, fn -> BazelShowcase.project_handle() end)
      |> assign_new(:data, fn -> showcase_data(BazelShowcase.get()) end)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <style :type={TuistWeb.ColocatedCSS}>
      [data-part="bazel-dashboard-lab"] {
        display: grid;
        gap: var(--noora-spacing-5);
        margin: var(--noora-spacing-7) 0;

        & .noora-card {
          overflow-x: hidden;
        }

        & [data-part="source"] {
          color: var(--noora-surface-label-secondary);
          font: var(--noora-font-weight-medium) var(--noora-font-body-small);
        }

        & [data-part="widgets"] {
          display: flex;
          flex-direction: row;
          gap: var(--noora-spacing-4);

          & > * {
            flex: 1;
          }

          @media (max-width: 768px) {
            flex-direction: column;
          }
        }

        & [data-part="builds-chart"] {
          display: flex;
          flex-direction: column;
          gap: var(--noora-spacing-7);
          padding: var(--noora-spacing-5);

          & > [data-part="label"] {
            color: var(--noora-surface-label-secondary);
            font: var(--noora-font-weight-regular) var(--noora-font-code-small);
          }

          & .noora-chart {
            width: 100%;
            height: 148px;
          }
        }

        & [data-part="legends"] {
          display: flex;
          flex-direction: row;
          gap: var(--noora-spacing-5);

          & > * {
            flex-grow: 1;
          }
        }

        /* The dashboard styles legends in app.css, which marketing pages don't load. */
        & .tuist-legend {
          display: flex;
          flex-direction: column;
          gap: var(--noora-spacing-5);

          & > [data-part="header"] {
            display: flex;
            flex-direction: row;
            align-items: stretch;
            gap: var(--noora-spacing-3);

            & [data-part="indicator"] {
              border-radius: var(--noora-radius-1);
              background-color: var(--indicator-color);
              width: 6px;
            }

            & > [data-part="title"] {
              color: var(--noora-surface-label-secondary);
              font: var(--noora-font-weight-medium) var(--noora-font-body-small);
            }
          }

          & > [data-part="value"] {
            color: var(--noora-surface-label-primary);
            font: var(--noora-font-weight-medium) var(--noora-font-heading-large);
          }

          &[data-style="primary"] {
            --indicator-color: var(--noora-chart-legend-primary);
          }

          &[data-style="destructive"] {
            --indicator-color: var(--noora-chart-destructive);
          }
        }
      }
    </style>

    <div id={@id} data-part="bazel-dashboard-lab">
      <.card title="Analytics" icon="chart_arcs">
        <:actions>
          <span data-part="source">
            Live from {@project}, last {BazelShowcase.period_days()} days
          </span>
        </:actions>
        <div data-part="widgets">
          <.widget
            id={"#{@id}-invocations"}
            title="Invocations"
            description="Bazel commands that reported to Tuist."
            value={@data && Integer.to_string(@data.invocations)}
            empty={is_nil(@data)}
          />
          <.widget
            id={"#{@id}-success-rate"}
            title="Success rate"
            description="The share of invocations that finished successfully."
            value={@data && percentage(@data.success_rate)}
            empty={is_nil(@data)}
          />
          <.widget
            id={"#{@id}-median-duration"}
            title="Median duration"
            description="The median duration of Bazel invocations."
            value={@data && DateFormatter.format_duration_from_milliseconds(@data.median_duration_ms)}
            empty={is_nil(@data)}
          />
          <.widget
            id={"#{@id}-cache-hit-rate"}
            title="Cache hit rate"
            description="The share of action-cache lookups served from Tuist's remote cache."
            value={@data && percentage(@data.cache_hit_rate)}
            empty={is_nil(@data)}
          />
        </div>
      </.card>

      <.card title="Builds" icon="subtask">
        <.card_section>
          <div data-part="builds-chart">
            <%= if @data do %>
              <div data-part="legends">
                <.legend
                  title="Passed invocations"
                  value={Enum.count(@data.recent_invocations, &(&1.status == "success"))}
                  style="primary"
                />
                <.legend
                  title="Failed invocations"
                  value={Enum.count(@data.recent_invocations, &(&1.status == "failure"))}
                  style="destructive"
                />
              </div>
              <.chart
                data-lazy="true"
                id={"#{@id}-recent-invocations"}
                type="bar"
                extra_options={chart_options(chart_data(@data.recent_invocations))}
                series={[
                  %{data: chart_data(@data.recent_invocations), name: "Invocation", type: "bar"}
                ]}
                y_axis_min={0}
                grid_lines
                bar_width={8}
                bar_radius={2}
              />
              <span data-part="label">Last {length(@data.recent_invocations)} invocations</span>
            <% else %>
              <span data-part="label">
                No Bazel invocations in the last {BazelShowcase.period_days()} days yet.
              </span>
            <% end %>
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp showcase_data({:ok, %{invocations: invocations} = data}) when invocations > 0, do: data
  defp showcase_data(_), do: nil

  defp percentage(nil), do: "n/a"
  defp percentage(value), do: "#{value}%"

  defp chart_data(invocations) do
    invocations
    |> Enum.reverse()
    |> Enum.map(fn invocation ->
      %{
        value: invocation.duration_ms,
        itemStyle: %{
          color:
            if(invocation.status == "success",
              do: "var:noora-chart-primary",
              else: "var:noora-chart-destructive"
            )
        },
        date: invocation.finished_at,
        status: invocation.status
      }
    end)
  end

  defp chart_options(chart_data) do
    %{
      grid: %{width: "100%", left: "0.4%", height: "88%", top: "5%"},
      tooltip: %{valueFormat: "fn:formatMilliseconds", dateFormat: "minute"},
      xAxis: %{axisLabel: %{show: false}, data: Enum.map(chart_data, & &1.date)},
      yAxis: %{
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "fn:formatMilliseconds"}
      },
      legend: %{show: false}
    }
  end
end
