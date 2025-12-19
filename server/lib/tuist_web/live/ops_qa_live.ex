defmodule TuistWeb.OpsQALive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Billing
  alias Tuist.QA
  alias Tuist.Utilities.DateFormatter

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:qa_runs_chart_data, QA.qa_runs_chart_data())
     |> assign(:projects_usage_chart_data, QA.projects_usage_chart_data())
     |> assign(:recent_qa_runs, QA.recent_qa_runs())
     |> assign(:token_usage_by_account, Billing.feature_token_usage_by_account("qa"))
     |> assign(:head_title, "#{dgettext("dashboard_qa", "QA Operations")} · Tuist")}
  end

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
