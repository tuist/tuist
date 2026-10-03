defmodule Atlas.Finance.Providers.MercuryTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Finance.Account
  alias Atlas.Finance.Providers.Mercury

  setup :verify_on_exit!

  test "lists accounts with bearer auth" do
    expect(Req, :get, fn %Req.Request{} = request ->
      assert URI.to_string(request.url) == "https://api.mercury.com/api/v1/accounts"
      assert request.options.auth == {:bearer, "token"}
      assert request.options.params[:limit] == 1000
      assert request.options.params[:order] == "asc"

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "accounts" => [
             %{
               "id" => "acc_123",
               "name" => "Operating",
               "kind" => "checking",
               "type" => "mercury",
               "status" => "active",
               "currency" => "USD",
               "currentBalance" => "132000.00",
               "availableBalance" => "128500.00",
               "accountNumber" => "1234567890",
               "legalBusinessName" => "Tuist Inc."
             }
           ],
           "page" => %{"nextPage" => nil}
         }
       }}
    end)

    assert {:ok, [account]} = Mercury.list_accounts(api_token: "token")

    assert account.external_id == "acc_123"
    assert account.account_type == "checking"
    assert account.account_subtype == "mercury"
    assert account.main
    assert account.currency == "USD"
    assert account.metadata["account_number_last4"] == "7890"
    assert account.metadata["legal_business_name"] == "Tuist Inc."
  end

  test "lists transactions and normalizes debit activity" do
    expect(Req, :get, fn %Req.Request{} = request ->
      assert URI.to_string(request.url) == "https://api.mercury.com/api/v1/account/acc_123/transactions"
      assert request.options.auth == {:bearer, "token"}
      assert request.options.params[:limit] == 1000
      assert request.options.params[:offset] == 0
      assert request.options.params[:order] == "asc"
      assert request.options.params[:start] == "2026-04-26T12:00:00Z"
      assert request.options.params[:end] == "2026-05-26T12:00:00Z"

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "transactions" => [
             %{
               "id" => "txn_123",
               "accountId" => "acc_123",
               "kind" => "outgoing_payment",
               "status" => "sent",
               "counterpartyName" => "Rippling",
               "note" => "US payroll",
               "requestId" => "req_123",
               "amount" => "-18500.00",
               "currency" => "USD",
               "postedAt" => "2026-05-18T14:40:00Z",
               "createdAt" => "2026-05-18T14:35:00Z",
               "currencyExchangeInfo" => %{
                 "convertedFromCurrency" => "EUR",
                 "convertedToCurrency" => "USD",
                 "convertedFromAmount" => "17000.00",
                 "convertedToAmount" => "18500.00",
                 "feeAmount" => "15.00"
               }
             }
           ],
           "total" => 1
         }
       }}
    end)

    assert {:ok, %{transactions: [transaction], next_cursor: ~U[2026-05-26 12:00:00Z]}} =
             Mercury.list_transactions(
               [api_token: "token"],
               %Account{external_id: "acc_123"},
               synced_after: ~U[2026-05-01 00:00:00Z],
               now: ~U[2026-05-26 12:00:00Z]
             )

    assert transaction.external_id == "txn_123"
    assert transaction.direction == "debit"
    assert transaction.kind == "outgoing_payment"
    assert transaction.counterparty_name == "Rippling"
    assert Decimal.equal?(transaction.amount_value, Decimal.new("18500.00"))
    assert Decimal.equal?(transaction.local_amount_value, Decimal.new("17000.00"))
    assert transaction.local_amount_currency == "EUR"
    assert Decimal.equal?(transaction.fee_value, Decimal.new("15.00"))
    assert transaction.fee_currency == "USD"
    assert transaction.affects_cash_balance
    assert transaction.affects_runway
  end

  test "keeps external transfers runway relevant" do
    expect(Req, :get, fn _request ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "transactions" => [
             %{
               "id" => "txn_transfer",
               "accountId" => "acc_123",
               "kind" => "external_transfer",
               "status" => "sent",
               "counterpartyName" => "Qonto",
               "amount" => "-5000.00",
               "currency" => "USD",
               "postedAt" => "2026-05-18T14:40:00Z",
               "createdAt" => "2026-05-18T14:35:00Z"
             }
           ],
           "total" => 1
         }
       }}
    end)

    assert {:ok, %{transactions: [transaction]}} =
             Mercury.list_transactions(
               [api_token: "token"],
               %Account{external_id: "acc_123"},
               synced_after: ~U[2026-05-01 00:00:00Z],
               now: ~U[2026-05-26 12:00:00Z]
             )

    assert transaction.affects_cash_balance
    assert transaction.affects_runway
  end

  test "marks internal transfers as cash balance activity but not runway activity" do
    expect(Req, :get, fn _request ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "transactions" => [
             %{
               "id" => "txn_internal_transfer",
               "accountId" => "acc_123",
               "kind" => "internal_transfer",
               "status" => "sent",
               "counterpartyName" => "Mercury Reserve",
               "amount" => "-5000.00",
               "currency" => "USD",
               "postedAt" => "2026-05-18T14:40:00Z",
               "createdAt" => "2026-05-18T14:35:00Z"
             }
           ],
           "total" => 1
         }
       }}
    end)

    assert {:ok, %{transactions: [transaction]}} =
             Mercury.list_transactions(
               [api_token: "token"],
               %Account{external_id: "acc_123"},
               synced_after: ~U[2026-05-01 00:00:00Z],
               now: ~U[2026-05-26 12:00:00Z]
             )

    assert transaction.affects_cash_balance
    refute transaction.affects_runway
  end
end
