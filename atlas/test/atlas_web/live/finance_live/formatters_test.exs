defmodule AtlasWeb.FinanceLive.FormattersTest do
  use ExUnit.Case, async: true

  alias Atlas.Finance.Account
  alias Atlas.Finance.Source
  alias Atlas.Finance.Transaction
  alias AtlasWeb.FinanceLive.Formatters

  describe "labels" do
    test "builds compact account labels" do
      account = %Account{
        name: "Operating",
        provider: "qonto",
        account_type: "bank_account",
        account_subtype: "business_checking",
        currency: "EUR",
        source: %Source{name: "Qonto Main", atlas_account: %{name: "Tuist GmbH"}}
      }

      assert Formatters.account_description(account) == "Tuist GmbH · Qonto Main · Qonto · EUR"
      assert Formatters.account_type_label(account) == "Bank account / Business checking"
    end

    test "builds transaction labels without duplicate blank segments" do
      transaction = %Transaction{
        description: "Payroll",
        kind: "salary_payment",
        reference: "Payroll",
        local_amount_value: Decimal.new("100"),
        local_amount_currency: "USD",
        fee_value: Decimal.new("1.50"),
        fee_currency: "EUR"
      }

      assert Formatters.transaction_description(transaction) == "Payroll · Salary payment"
      assert Formatters.transaction_amount_description(transaction) == "Local USD 100.00 · Fee EUR 1.50"
    end
  end

  describe "amount and status formatting" do
    test "formats signed amounts by direction" do
      assert Formatters.signed_amount_label(Decimal.new("10"), "EUR", "credit") == "+EUR 10.00"
      assert Formatters.signed_amount_label(Decimal.new("10"), "EUR", "debit") == "-EUR 10.00"
      assert Formatters.signed_amount_label(Decimal.new("-10"), "EUR") == "-EUR 10.00"
    end

    test "maps statuses to badge colors" do
      assert Formatters.status_color("completed") == "success"
      assert Formatters.status_color("pending") == "attention"
      assert Formatters.status_color("failed") == "destructive"
      assert Formatters.status_color("unknown") == "neutral"
    end
  end
end
