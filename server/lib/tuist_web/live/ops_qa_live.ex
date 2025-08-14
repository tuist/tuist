defmodule TuistWeb.OpsQALive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Billing
  alias Tuist.QA

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:qa_runs_chart_data, QA.qa_runs_chart_data())
     |> assign(:projects_usage_chart_data, QA.projects_usage_chart_data())
     |> assign(:recent_qa_runs, QA.recent_qa_runs())
     |> assign(:token_usage_by_account, Billing.feature_token_usage_by_account("qa"))
     |> assign(:head_title, "#{gettext("QA Operations")} · Tuist")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="qa-operations">
      <div data-part="charts-row">
        <.card title={gettext("QA Runs (Last 30 Days)")} icon="chart_arcs">
          <.card_section>
            <.chart
              id="qa-runs-chart"
              type="line"
              extra_options={
                %{
                  grid: %{
                    width: "97%",
                    left: "0.4%",
                    height: "88%",
                    top: "5%"
                  },
                  xAxis: %{
                    boundaryGap: false,
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary"
                    }
                  },
                  yAxis: %{
                    splitNumber: 4,
                    splitLine: %{
                      lineStyle: %{
                        color: "var:noora-chart-lines"
                      }
                    },
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary"
                    }
                  },
                  legend: %{
                    show: false
                  }
                }
              }
              series={[
                %{
                  color: "var:noora-chart-primary",
                  data: @qa_runs_chart_data,
                  name: gettext("QA Runs"),
                  type: "line",
                  smooth: 0.1,
                  symbol: "none"
                }
              ]}
              y_axis_min={0}
            />
          </.card_section>
        </.card>

        <.card title={gettext("Projects Using QA (Last 30 Days)")} icon="chart_arcs">
          <.card_section>
            <.chart
              id="projects-usage-chart"
              type="line"
              extra_options={
                %{
                  grid: %{
                    width: "97%",
                    left: "0.4%",
                    height: "88%",
                    top: "5%"
                  },
                  xAxis: %{
                    boundaryGap: false,
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary"
                    }
                  },
                  yAxis: %{
                    splitNumber: 4,
                    splitLine: %{
                      lineStyle: %{
                        color: "var:noora-chart-lines"
                      }
                    },
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary"
                    }
                  },
                  legend: %{
                    show: false
                  }
                }
              }
              series={[
                %{
                  color: "var:noora-chart-secondary",
                  data: @projects_usage_chart_data,
                  name: gettext("Projects"),
                  type: "line",
                  smooth: 0.1,
                  symbol: "none"
                }
              ]}
              y_axis_min={0}
            />
          </.card_section>
        </.card>
      </div>

      <div data-part="token-usage-section">
        <.card title={gettext("Token Usage by Account")} icon="chart_arcs">
          <.card_section>
            <.table id="token-usage-table" rows={@token_usage_by_account}>
              <:col :let={usage} label={gettext("Account")}>
                <.text_cell label={usage.account_name} />
              </:col>
              <:col :let={usage} label={gettext("Last 30 Days")}>
                <.text_cell label={"#{format_number(usage.thirty_day.total_input_tokens)} / #{format_number(usage.thirty_day.total_output_tokens)}"} />
              </:col>
              <:col :let={usage} label={gettext("All Time")}>
                <.text_cell label={"#{format_number(usage.all_time.total_input_tokens)} / #{format_number(usage.all_time.total_output_tokens)}"} />
              </:col>
              <:col :let={usage} label={gettext("Average Tokens per Run")}>
                <.text_cell label={format_number(usage.all_time.average_tokens)} />
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="chart_arcs"
                  title={gettext("No token usage found")}
                  subtitle={
                    gettext("Token usage will appear here once QA runs start using LLM features")
                  }
                />
              </:empty_state>
            </.table>
          </.card_section>
        </.card>
      </div>

      <div data-part="qa-runs-section">
        <.card title={gettext("Recent QA Runs")} icon="history">
          <.card_section>
            <%= if Enum.empty?(@recent_qa_runs) do %>
              <div data-part="empty-table">
                <span>{gettext("No QA runs found")}</span>
              </div>
            <% else %>
              <.table id="recent-qa-runs-table" rows={@recent_qa_runs}>
                <:col :let={qa_run} label={gettext("Project")}>
                  <.text_cell label={"#{qa_run.account_name}/#{qa_run.project_name}"} />
                </:col>
                <:col :let={qa_run} label={gettext("Status")}>
                  <.text_cell label={String.capitalize(qa_run.status)} />
                </:col>
                <:col :let={qa_run} label={gettext("Prompt")}>
                  <.text_cell label={String.slice(qa_run.prompt || "No prompt", 0, 50) <> if(String.length(qa_run.prompt || "") > 50, do: "...", else: "")} />
                </:col>
                <:col :let={qa_run} label={gettext("Token usage")}>
                  <.text_cell label={format_qa_run_token_usage(qa_run)} />
                </:col>
                <:col :let={qa_run} label={gettext("Ran at")}>
                  <.text_cell label={format_datetime(qa_run.inserted_at)} />
                </:col>
                <:col :let={qa_run} label={gettext("Actions")}>
                  <.button
                    variant="secondary"
                    label={gettext("View Logs")}
                    navigate={~p"/ops/qa/#{qa_run.id}/logs"}
                  />
                </:col>
              </.table>
            <% end %>
          </.card_section>
        </.card>
      </div>
    </div>
    """
  end

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end

  defp format_datetime(_), do: "Unknown"

  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_number(_), do: "0"

  defp format_qa_run_token_usage(qa_run) do
    input_tokens = qa_run.input_tokens
    output_tokens = qa_run.output_tokens

    if input_tokens == 0 and output_tokens == 0 do
      "No tokens"
    else
      "#{format_number(input_tokens)} / #{format_number(output_tokens)}"
    end
  end
end
