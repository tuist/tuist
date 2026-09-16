defmodule Atlas.Accounts.Agents.InvoicePaidCelebrationAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Agents.InvoicePaidCelebrationAgent
  alias Atlas.Accounts.Invoice
  alias Atlas.LLMs

  @em_dash <<0x2014::utf8>>

  setup :verify_on_exit!

  test "returns :llm_not_configured when no LLM config is available" do
    stub(LLMs, :config, fn -> nil end)

    assert {:error, :llm_not_configured} =
             InvoicePaidCelebrationAgent.celebrate(account_fixture(), invoice_fixture())
  end

  describe "system_prompt/0" do
    test "documents the celebration job and prohibits em dashes" do
      prompt = InvoicePaidCelebrationAgent.system_prompt()

      assert prompt =~ "short, upbeat Slack celebration"
      assert prompt =~ "company sales channel"
      assert prompt =~ "one headline"
      assert prompt =~ "1 to 3 short sentences"
      assert prompt =~ "Do not invent"
      assert prompt =~ "Vary the phrasing"
      assert prompt =~ "Never use em dashes"
      refute prompt =~ @em_dash
    end
  end

  defp account_fixture do
    %Account{
      id: "acct-celebrate-1",
      name: "Acme",
      stripe_customer_id: "cus_acme"
    }
  end

  defp invoice_fixture do
    %Invoice{
      external_id: "in_123",
      source: "stripe",
      number: "TUIST-8002",
      due_date: ~D[2026-03-01],
      amount_value: Decimal.new("30000.00"),
      amount_currency: "USD",
      status: "paid",
      stripe_url: "https://stripe.example/invoices/in_123"
    }
  end
end
