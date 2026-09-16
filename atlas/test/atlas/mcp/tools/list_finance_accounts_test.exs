defmodule Atlas.MCP.Tools.ListFinanceAccountsTest do
  use Atlas.MCP.ToolCase

  import Atlas.FinanceFixtures

  alias Atlas.MCP.Tools.ListFinanceAccounts

  test "filters finance accounts by provider, currency, and query" do
    conn = executive_mcp_conn()
    tuist_gmbh = insert_account!(%{name: "Tuist GmbH", segment: :customer})
    tuist_inc = insert_account!(%{name: "Tuist Inc.", segment: :customer})

    qonto_source =
      insert_finance_source!(%{
        atlas_account_id: tuist_gmbh.id,
        provider: "qonto",
        config_key: "qonto-main",
        name: "Qonto Main"
      })

    mercury_source =
      insert_finance_source!(%{
        atlas_account_id: tuist_inc.id,
        provider: "mercury",
        config_key: "mercury-main",
        name: "Mercury Main"
      })

    _qonto_account =
      insert_finance_account!(qonto_source, %{
        name: "Operating",
        currency: "EUR",
        iban: "FR761234"
      })

    mercury_account =
      insert_finance_account!(mercury_source, %{
        name: "Reserve",
        currency: "USD",
        balance_currency: "USD",
        available_balance_currency: "USD",
        iban: "BE991234"
      })

    {:ok, payload} =
      execute_tool(ListFinanceAccounts, conn, %{
        "provider" => "mercury",
        "atlas_account_key" => tuist_inc.account_key,
        "currency" => "USD",
        "query" => "Reserve"
      })

    assert payload.count == 1
    tuist_inc_key = tuist_inc.account_key

    assert [
             %{
               name: "Reserve",
               currency: "USD",
               provider: "mercury",
               source: %{
                 atlas_account: %{account_key: ^tuist_inc_key, name: "Tuist Inc."},
                 config_key: config_key,
                 name: "Mercury Main"
               }
             }
           ] = payload.accounts

    assert config_key == mercury_source.config_key
    assert hd(payload.accounts).id == mercury_account.id
  end

  test "respects page_size" do
    conn = executive_mcp_conn()
    source = insert_finance_source!()
    first = insert_finance_account!(source, %{external_id: "acct-a", name: "A Account"})
    _second = insert_finance_account!(source, %{external_id: "acct-b", name: "B Account"})

    {:ok, payload} = execute_tool(ListFinanceAccounts, conn, %{"page_size" => 1})

    assert payload.count == 1
    assert hd(payload.accounts).id == first.id
  end

  test "rejects non-executive users" do
    conn =
      %{role: :employee}
      |> insert_user!()
      |> mcp_conn()

    assert {:error, "Finance tools are only available to executives."} =
             execute_tool(ListFinanceAccounts, conn, %{})
  end
end
