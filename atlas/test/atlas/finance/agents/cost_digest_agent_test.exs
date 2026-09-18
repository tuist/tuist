defmodule Atlas.Finance.Agents.CostDigestAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Finance
  alias Atlas.Finance.Agents.CostDigestAgent
  alias Atlas.LLMs

  setup :verify_on_exit!

  test "builds the last completed week context" do
    context = CostDigestAgent.weekly_context(now: ~U[2026-05-25 09:00:00Z])

    assert context.cadence == :weekly
    assert context.period_start == ~U[2026-05-18 00:00:00Z]
    assert context.period_end == ~U[2026-05-25 00:00:00Z]
    assert context.comparison_period_start == ~U[2026-05-11 00:00:00Z]
    assert context.comparison_period_end == ~U[2026-05-18 00:00:00Z]
    assert context.currency == "EUR"
  end

  test "builds yesterday context for the daily cost check" do
    context = CostDigestAgent.daily_context(now: ~U[2026-05-25 09:00:00Z])

    assert context.cadence == :daily
    assert context.period_start == ~U[2026-05-24 00:00:00Z]
    assert context.period_end == ~U[2026-05-25 00:00:00Z]
    assert context.comparison_period_start == ~U[2026-04-24 00:00:00Z]
    assert context.comparison_period_end == ~U[2026-05-24 00:00:00Z]
  end

  test "returns :llm_not_configured when no LLM config is available" do
    stub(LLMs, :config, fn -> nil end)

    assert {:error, :llm_not_configured} = CostDigestAgent.summarize(CostDigestAgent.daily_context())
  end

  test "documents Slack block output and cost analysis in the system prompt" do
    prompt = CostDigestAgent.system_prompt()

    assert prompt =~ "Atlas renders it into Slack blocks"
    assert prompt =~ "get_vendor_cost_analytics"
    assert prompt =~ "list_finance_invoices"
    assert prompt =~ "Do not invent"
  end

  test "renders structured agent copy into consistently styled Slack blocks" do
    context = CostDigestAgent.daily_context(now: ~U[2026-07-17 09:00:00Z])

    expect(LLMs, :config, fn ->
      %{model: "openai:gpt-4o-mini", api_key: "test-key"}
    end)

    expect(Condukt, :run, fn prompt, opts ->
      assert prompt =~ "summary: a compact leadership readout"

      assert %{
               required: ["fallback_text", "summary", "concerns", "next_steps"],
               properties: %{summary: %{type: "string"}, concerns: %{type: "array"}}
             } = Keyword.fetch!(opts, :output)

      {:ok,
       %{
         "fallback_text" => "No new vendor costs were recorded yesterday.",
         "summary" => "No new invoices were recorded.\\nThe prior 30 days contained 17 invoices.",
         "concerns" => ["Sentry usage-driven costs should be watched."],
         "next_steps" => ["Review the next Sentry invoice for repeated overage."]
       }}
    end)

    assert {:ok, digest} = CostDigestAgent.summarize(context)

    assert [header, period_context, summary, concerns, next_steps, footer] = digest.blocks
    assert header["text"]["text"] == "Daily cost check - 2026-07-16"
    assert header["text"]["type"] == "plain_text"
    assert Enum.all?(period_context["elements"], &(&1["type"] == "mrkdwn"))

    assert summary["text"] == %{
             "type" => "mrkdwn",
             "text" => "*Summary*\nNo new invoices were recorded.\nThe prior 30 days contained 17 invoices."
           }

    assert concerns["text"]["text"] == "*Concerns*\n- Sentry usage-driven costs should be watched."

    assert next_steps["text"]["text"] ==
             "*Next steps*\n- Review the next Sentry invoice for repeated overage."

    assert footer["type"] == "context"
    refute inspect(digest.blocks) =~ "\\\\n"
  end

  test "builds a deterministic cost digest when language-model generation is unavailable" do
    context = CostDigestAgent.weekly_context(now: ~U[2026-05-25 09:00:00Z])
    current = analytics_fixture("1200.00", 3, 2)
    comparison = analytics_fixture("800.00", 2, 0)

    expect(Finance, :vendor_cost_analytics, 2, fn opts ->
      case opts[:date_from] do
        ~D[2026-05-18] -> current
        ~D[2026-05-11] -> comparison
      end
    end)

    digest = CostDigestAgent.fallback(context)
    rendered = inspect(digest.blocks)

    assert digest.fallback_text =~ "EUR 1,200.00"
    assert digest.fallback_text =~ "50.0% higher"
    assert rendered =~ "Grafana Labs"
    assert rendered =~ "Top-vendor concentration"
    assert rendered =~ "2 invoices need extraction review"
  end

  defp analytics_fixture(total, invoice_count, needs_review_count) do
    top_vendor = %{
      vendor_name: "Grafana Labs",
      total_amount_value: Decimal.new("900.00"),
      total_amount_currency: "EUR"
    }

    %{
      currency: "EUR",
      total_spend_value: Decimal.new(total),
      invoice_count: invoice_count,
      vendor_count: 2,
      needs_review_count: needs_review_count,
      concentration_percent: Decimal.new("75.0"),
      top_vendor: top_vendor,
      vendors: [top_vendor]
    }
  end
end
