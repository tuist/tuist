defmodule Atlas.Finance.Providers.QontoTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Finance.Account
  alias Atlas.Finance.Providers.Qonto

  setup :verify_on_exit!

  test "describes a source with API key auth" do
    expect(Req, :get, fn %Req.Request{} = request ->
      assert URI.to_string(request.url) == "https://thirdparty.qonto.com/v2/organization"
      assert request.headers["authorization"] == ["tuist-gmbh-5271:secret"]
      assert request.options.params[:include_external_accounts] == true

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "organization" => %{
             "id" => "org_123",
             "legal_name" => "Tuist GmbH",
             "slug" => "tuist-gmbh",
             "legal_country" => "DE",
             "legal_form" => "gmbh",
             "locale" => "en"
           }
         }
       }}
    end)

    assert {:ok, source} =
             Qonto.describe_source(
               sign_in: "tuist-gmbh-5271",
               secret_key: "secret",
               include_external_accounts: true,
               name: "Qonto"
             )

    assert source.external_id == "org_123"
    assert source.name == "Tuist GmbH"
    assert source.metadata["slug"] == "tuist-gmbh"
  end

  test "lists transactions and normalizes the response" do
    expect(Req, :get, fn %Req.Request{} = request ->
      status_params =
        request.options.params
        |> Enum.filter(fn {key, _value} -> key == "status[]" end)
        |> Enum.map(&elem(&1, 1))

      assert URI.to_string(request.url) == "https://thirdparty.qonto.com/v2/transactions"
      assert List.keyfind(request.options.params, "bank_account_id", 0) == {"bank_account_id", "ba_123"}
      assert List.keyfind(request.options.params, "sort_by", 0) == {"sort_by", "updated_at:asc"}
      assert List.keyfind(request.options.params, "per_page", 0) == {"per_page", 100}
      assert List.keyfind(request.options.params, "updated_at_from", 0) == {"updated_at_from", "2026-05-01T00:00:00Z"}
      assert status_params == ["completed", "pending", "declined"]

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "transactions" => [
             %{
               "id" => "txn_123",
               "status" => "completed",
               "side" => "debit",
               "operation_type" => "CARD",
               "label" => "AWS",
               "note" => "Infrastructure bill",
               "reference" => "AWS-2026-05",
               "amount" => "-6500.00",
               "currency" => "EUR",
               "local_amount" => "-6500.00",
               "local_currency" => "EUR",
               "settled_balance" => "70000.00",
               "settled_at" => "2026-05-16T10:15:00Z",
               "updated_at" => "2026-05-16T10:16:00Z"
             }
           ],
           "meta" => %{"next_page" => nil}
         }
       }}
    end)

    assert {:ok, %{transactions: [transaction], next_cursor: ~U[2026-05-26 12:00:00Z]}} =
             Qonto.list_transactions(
               [sign_in: "tuist-gmbh-5271", secret_key: "secret"],
               %Account{external_id: "ba_123"},
               synced_after: ~U[2026-05-01 00:00:00Z],
               now: ~U[2026-05-26 12:00:00Z]
             )

    assert transaction.external_id == "txn_123"
    assert transaction.direction == "debit"
    assert transaction.kind == "card"
    assert transaction.counterparty_name == "AWS"
    assert Decimal.equal?(transaction.amount_value, Decimal.new("6500.00"))
    assert transaction.affects_cash_balance
    assert transaction.affects_runway
  end

  test "keeps SEPA transfers runway relevant despite Qonto transfer metadata" do
    expect(Req, :get, fn _request ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "transactions" => [
             %{
               "id" => "txn_transfer",
               "status" => "completed",
               "side" => "debit",
               "operation_type" => "TRANSFER",
               "label" => "Jane Doe",
               "amount" => "-5000.00",
               "currency" => "EUR",
               "settled_at" => "2026-05-16T10:15:00Z",
               "updated_at" => "2026-05-16T10:16:00Z",
               "transfer" => %{"id" => "transfer_123"}
             }
           ],
           "meta" => %{"next_page" => nil}
         }
       }}
    end)

    assert {:ok, %{transactions: [transaction]}} =
             Qonto.list_transactions(
               [sign_in: "tuist-gmbh-5271", secret_key: "secret"],
               %Account{external_id: "ba_123"},
               synced_after: ~U[2026-05-01 00:00:00Z],
               now: ~U[2026-05-26 12:00:00Z]
             )

    # Payroll and vendor payments leave Qonto as SEPA transfers (and carry the
    # `transfer` metadata), so they must still count toward runway/burn.
    # Intercompany movement is excluded by counterparty, not by this flag.
    assert transaction.affects_cash_balance
    assert transaction.affects_runway
  end

  test "keeps transfer operation transactions runway relevant without Qonto transfer metadata" do
    expect(Req, :get, fn _request ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "transactions" => [
             %{
               "id" => "txn_vendor_transfer",
               "status" => "completed",
               "side" => "debit",
               "operation_type" => "TRANSFER",
               "label" => "Contractor",
               "amount" => "-5000.00",
               "currency" => "EUR",
               "settled_at" => "2026-05-16T10:15:00Z",
               "updated_at" => "2026-05-16T10:16:00Z"
             }
           ],
           "meta" => %{"next_page" => nil}
         }
       }}
    end)

    assert {:ok, %{transactions: [transaction]}} =
             Qonto.list_transactions(
               [sign_in: "tuist-gmbh-5271", secret_key: "secret"],
               %Account{external_id: "ba_123"},
               synced_after: ~U[2026-05-01 00:00:00Z],
               now: ~U[2026-05-26 12:00:00Z]
             )

    assert transaction.kind == "transfer"
    assert transaction.affects_cash_balance
    assert transaction.affects_runway
  end

  test "keeps external transfers runway relevant without Qonto transfer metadata" do
    expect(Req, :get, fn _request ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "transactions" => [
             %{
               "id" => "txn_external_transfer",
               "status" => "completed",
               "side" => "debit",
               "operation_type" => "external_transfer",
               "label" => "Mercury",
               "amount" => "-5000.00",
               "currency" => "EUR",
               "settled_at" => "2026-05-16T10:15:00Z",
               "updated_at" => "2026-05-16T10:16:00Z"
             }
           ],
           "meta" => %{"next_page" => nil}
         }
       }}
    end)

    assert {:ok, %{transactions: [transaction]}} =
             Qonto.list_transactions(
               [sign_in: "tuist-gmbh-5271", secret_key: "secret"],
               %Account{external_id: "ba_123"},
               synced_after: ~U[2026-05-01 00:00:00Z],
               now: ~U[2026-05-26 12:00:00Z]
             )

    assert transaction.kind == "external_transfer"
    assert transaction.affects_cash_balance
    assert transaction.affects_runway
  end
end
