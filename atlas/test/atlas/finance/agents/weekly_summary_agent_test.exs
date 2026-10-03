defmodule Atlas.Finance.Agents.WeeklySummaryAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Finance
  alias Atlas.Finance.Agents.WeeklySummaryAgent
  alias Atlas.Finance.Transaction
  alias Atlas.LLMs

  setup :verify_on_exit!

  test "builds the last completed week context" do
    context = WeeklySummaryAgent.context(now: ~U[2026-05-25 09:00:00Z])

    assert context.cadence == :weekly
    assert context.period_start == ~U[2026-05-18 00:00:00Z]
    assert context.period_end == ~U[2026-05-25 00:00:00Z]
    assert context.previous_period_start == ~U[2026-05-11 00:00:00Z]
    assert context.previous_period_end == ~U[2026-05-18 00:00:00Z]
    assert context.currency == "EUR"
  end

  test "builds the previous-day context for a daily financial pulse" do
    context = WeeklySummaryAgent.context(cadence: :daily, now: ~U[2026-05-25 09:00:00Z])

    assert context.cadence == :daily
    assert context.period_start == ~U[2026-05-24 00:00:00Z]
    assert context.period_end == ~U[2026-05-25 00:00:00Z]
    assert context.previous_period_start == ~U[2026-04-24 00:00:00Z]
    assert context.previous_period_end == ~U[2026-05-24 00:00:00Z]
  end

  test "returns :llm_not_configured when no LLM config is available" do
    stub(LLMs, :config, fn -> nil end)

    assert {:error, :llm_not_configured} = WeeklySummaryAgent.summarize(summary_context())
  end

  test "documents tool-backed finance analysis in the system prompt" do
    prompt = WeeklySummaryAgent.system_prompt()

    assert prompt =~ "tools to inspect Atlas finance data"
    assert prompt =~ "get_finance_overview"
    assert prompt =~ "list_finance_transactions"
    assert prompt =~ "get_finance_expense_history"
    assert prompt =~ "Do not invent"
  end

  test "asks for structured analysis and preserves the agent's key drivers" do
    expect(LLMs, :config, fn ->
      %{model: "openai:gpt-4o-mini", api_key: "test-key"}
    end)

    expect(Condukt, :run, fn prompt, opts ->
      assert prompt =~ "current_period: 2026-05-18 to 2026-05-24"
      assert prompt =~ "Call get_finance_expense_history"
      assert Keyword.fetch!(opts, :tools) |> length() == 3
      schema = Keyword.fetch!(opts, :output)
      assert "drivers" in schema.required
      assert schema.properties.drivers.items.required == ["title", "detail"]

      {:ok,
       %{
         "headline" => "Costs increased",
         "summary" => "Cash covers eight months.

Hardware drove spending.",
         "drivers" => [%{"title" => "Hardware", "detail" => "A supplier received EUR 4,000."}],
         "concerns" => [],
         "next_steps" => ["Confirm whether the hardware purchase is a one-off."]
       }}
    end)

    assert {:ok, readout} = WeeklySummaryAgent.summarize(summary_context())
    assert readout.drivers == [%{title: "Hardware", detail: "A supplier received EUR 4,000."}]
    assert readout.summary =~ "

"
  end

  test "rejects malformed drivers so the caller can use the explicit fallback" do
    stub(LLMs, :config, fn -> %{model: "openai:gpt-4o-mini", api_key: "test-key"} end)

    expect(Condukt, :run, fn _prompt, _opts ->
      {:ok, %{"headline" => "Update", "summary" => "Cash is stable.", "drivers" => ["invalid"]}}
    end)

    assert {:error, :unexpected_result} = WeeklySummaryAgent.summarize(summary_context())
  end

  test "builds a deterministic fallback with core metrics and largest transactions" do
    context = summary_context()
    overview = overview_fixture()

    transaction = %Transaction{
      direction: "debit",
      counterparty_name: "Grafana Labs",
      amount_value: Decimal.new("3993.03"),
      amount_currency: "EUR",
      affects_runway: true,
      settled_at: ~U[2026-05-21 10:00:00Z]
    }

    expect(Finance, :overview, fn -> overview end)

    expect(Finance, :list_transactions, fn opts ->
      assert opts[:date_from] == context.period_start
      assert opts[:date_to] == ~U[2026-05-24 23:59:59Z]
      assert opts[:currency] == "EUR"
      [transaction]
    end)

    expect(Finance, :expense_history, fn opts ->
      assert opts[:ending_on] == ~D[2026-05-24]
      assert opts[:months] == 3
      assert opts[:currency] == "EUR"
      expense_history_fixture()
    end)

    report = WeeklySummaryAgent.fallback(context)

    assert report.status == :attention
    assert report.readout.headline == "Weekly financial pulse needs attention"
    assert report.readout.summary =~ "EUR 294,870.97"
    assert report.readout.summary =~ "8.18 months"
    assert Enum.any?(report.readout.concerns, &(&1.title == "Runway is below twelve months"))
    assert [%{label: "Grafana Labs", direction: "debit"}] = report.top_transactions
  end

  defp summary_context do
    %{
      cadence: :weekly,
      currency: "EUR",
      period_start: ~U[2026-05-18 00:00:00Z],
      period_end: ~U[2026-05-25 00:00:00Z],
      previous_period_start: ~U[2026-05-11 00:00:00Z],
      previous_period_end: ~U[2026-05-18 00:00:00Z]
    }
  end

  defp expense_history_fixture do
    %{
      currency: "EUR",
      months: [
        %{
          period: %{date_from: ~D[2026-03-01], date_to: ~D[2026-03-31], partial?: false},
          total_amount_value: Decimal.new("31000.00"),
          complete?: true,
          categories: [],
          exclusions: %{}
        },
        %{
          period: %{date_from: ~D[2026-04-01], date_to: ~D[2026-04-30], partial?: false},
          total_amount_value: Decimal.new("34000.00"),
          complete?: true,
          categories: [],
          exclusions: %{}
        },
        %{
          period: %{date_from: ~D[2026-05-01], date_to: ~D[2026-05-24], partial?: true},
          total_amount_value: Decimal.new("28000.00"),
          complete?: true,
          categories: [],
          exclusions: %{}
        }
      ]
    }
  end

  defp overview_fixture do
    %{
      currency: "EUR",
      available_cash_value: Decimal.new("294870.97"),
      net_30d_value: Decimal.new("-35834.25"),
      monthly_burn_value: Decimal.new("36048.38"),
      runway_months: Decimal.new("8.18"),
      projected_runway_months: Decimal.new("9.59"),
      last_synced_at: DateTime.utc_now()
    }
  end
end
