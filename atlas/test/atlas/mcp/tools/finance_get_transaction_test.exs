defmodule Atlas.MCP.Tools.FinanceGetTransactionTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Finance
  alias Atlas.Finance.Account
  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.Finance.Source
  alias Atlas.Finance.Transaction
  alias Atlas.MCP.Tools.FinanceGetTransaction

  test "passes the configured source map to the provider" do
    source_config = %{key: "qonto-main", provider: :qonto, name: "Qonto Main"}
    transaction = transaction()
    transaction_id = transaction.id

    expect(Finance, :list_transactions, fn [limit: 1, id: ^transaction_id] -> [transaction] end)
    expect(Config, :fetch_source, fn "qonto-main" -> {:ok, source_config} end)

    expect(Qonto, :list_transaction_attachments, fn ^source_config, "transaction-1" ->
      {:ok,
       [
         %{
           "id" => "attachment-1",
           "file_name" => "receipt.pdf",
           "file_content_type" => "application/pdf",
           "file_size" => 42,
           "url" => nil,
           "probative_attachment" => nil
         }
       ]}
    end)

    assert {:ok, result} =
             execute_tool(FinanceGetTransaction, executive_mcp_conn(), %{"transaction_id" => transaction.id})

    assert result.id == transaction.id
    assert result.occurred_at == "2026-08-17T15:30:00Z"
    assert [%{id: "attachment-1", file_size: 42}] = result.attachments
  end

  defp transaction do
    source = %Source{config_key: "qonto-main"}
    account = %Account{id: Ecto.UUID.generate(), name: "Operating", source: source}

    %Transaction{
      id: Ecto.UUID.generate(),
      account: account,
      external_id: "transaction-1",
      provider: "qonto",
      status: "completed",
      direction: "debit",
      kind: "card",
      counterparty_name: "Vendor",
      description: "Receipt",
      reference: "REF-1",
      amount_value: Decimal.new("42.00"),
      amount_currency: "EUR",
      local_amount_value: Decimal.new("42.00"),
      local_amount_currency: "EUR",
      booked_at: ~U[2026-08-17 15:30:00Z]
    }
  end
end
