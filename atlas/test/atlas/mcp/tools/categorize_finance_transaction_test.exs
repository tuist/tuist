defmodule Atlas.MCP.Tools.CategorizeFinanceTransactionTest do
  use Atlas.MCP.ToolCase

  import Atlas.FinanceFixtures

  alias Atlas.Audit.Activity
  alias Atlas.Finance.Category
  alias Atlas.Finance.Transaction
  alias Atlas.MCP.Tools.CategorizeFinanceTransaction

  setup do
    source = insert_finance_source!()
    account = insert_finance_account!(source, %{currency: "USD"})
    misc = insert_finance_category!(%{name: "Miscellaneous Income", direction: "credit"})
    financing = insert_finance_category!(%{name: "Financing", direction: "credit"})
    payroll = insert_finance_category!(%{name: "Payroll", direction: "debit"})

    wire =
      insert_finance_transaction!(account, %{
        direction: "credit",
        kind: "incoming_domestic_wire",
        counterparty_name: "INDIE FUND I, L.P.",
        amount_value: Decimal.new("300000.00"),
        amount_currency: "USD",
        finance_category_id: misc.id,
        categorized_by_agent: "finance_transaction_categorization_agent"
      })

    %{wire: wire, financing: financing, payroll: payroll}
  end

  test "recategorizes a transaction as financing and takes it out of runway", %{wire: wire, financing: financing} do
    assert {:ok, payload} =
             execute_tool(CategorizeFinanceTransaction, executive_mcp_conn(), %{
               "transaction_id" => wire.id,
               "category_slug" => financing.slug,
               "affects_runway" => false,
               "reason" => "Investor wire, not revenue"
             })

    assert payload.category.id == financing.id
    assert payload.affects_runway == false
    assert payload.runway_override == false

    stored = Repo.get!(Transaction, wire.id)
    assert stored.finance_category_id == financing.id
    refute stored.affects_runway
    assert stored.affects_cash_balance
    assert is_nil(stored.categorized_by_agent)
    assert stored.categorization_reason == "Investor wire, not revenue"
    assert Repo.get_by!(Activity, action: "finance_transaction.recategorized", target_id: wire.id)
  end

  test "leaves the runway flag alone when affects_runway is omitted", %{wire: wire, financing: financing} do
    assert {:ok, payload} =
             execute_tool(CategorizeFinanceTransaction, executive_mcp_conn(), %{
               "transaction_id" => wire.id,
               "category_id" => financing.id
             })

    assert payload.affects_runway == true
    assert is_nil(payload.runway_override)
  end

  test "rejects a category whose direction does not match", %{wire: wire, payroll: payroll} do
    assert {:error, message} =
             execute_tool(CategorizeFinanceTransaction, executive_mcp_conn(), %{
               "transaction_id" => wire.id,
               "category_slug" => payroll.slug
             })

    assert message =~ "does not match the transaction's direction"
    refute message =~ payroll.slug
    assert Repo.get!(Transaction, wire.id).finance_category_id != payroll.id
  end

  test "names valid slugs when the category is unknown", %{wire: wire, financing: financing} do
    assert {:error, message} =
             execute_tool(CategorizeFinanceTransaction, executive_mcp_conn(), %{
               "transaction_id" => wire.id,
               "category_slug" => "equity-round"
             })

    assert message =~ "not found"
    assert message =~ financing.slug
  end

  test "creates a broad category by name when none fits, then reuses it", %{wire: wire} do
    name =
      "Investor Funding #{System.unique_integer([:positive]) |> Integer.to_string(36) |> String.replace(~r/\d/, "x")}"

    assert {:ok, first} =
             execute_tool(CategorizeFinanceTransaction, executive_mcp_conn(), %{
               "transaction_id" => wire.id,
               "new_category_name" => name,
               "affects_runway" => false
             })

    assert first.category.name == name
    assert Repo.get!(Category, first.category.id).direction == "credit"

    assert {:ok, second} =
             execute_tool(CategorizeFinanceTransaction, executive_mcp_conn(), %{
               "transaction_id" => wire.id,
               "new_category_name" => name
             })

    assert second.category.id == first.category.id
  end

  test "rejects a category name too narrow to reuse", %{wire: wire} do
    assert {:error, message} =
             execute_tool(CategorizeFinanceTransaction, executive_mcp_conn(), %{
               "transaction_id" => wire.id,
               "new_category_name" => "Indie Fund Wire 2026"
             })

    assert message =~ "must not include numbers"
  end

  test "rejects users without the finance:write scope", %{wire: wire, financing: financing} do
    conn = %{role: :employee} |> insert_user!() |> mcp_conn()

    assert {:error, "Finance tools require the finance:write scope."} =
             execute_tool(CategorizeFinanceTransaction, conn, %{
               "transaction_id" => wire.id,
               "category_slug" => financing.slug
             })
  end
end
