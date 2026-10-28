defmodule Atlas.Finance.Workers.CategorizeTransactionsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Finance
  alias Atlas.Finance.Workers.CategorizeTransactions

  setup :verify_on_exit!

  test "delegates to the finance categorization workflow" do
    expect(Finance, :categorize_transactions, fn ->
      {:ok, %{categorized_count: 2}}
    end)

    assert :ok = CategorizeTransactions.perform(%Oban.Job{})
  end

  test "cancels when no LLM is configured" do
    expect(Finance, :categorize_transactions, fn ->
      {:error, :llm_not_configured}
    end)

    assert {:cancel, :llm_not_configured} = CategorizeTransactions.perform(%Oban.Job{})
  end
end
