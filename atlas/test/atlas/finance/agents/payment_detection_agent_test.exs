defmodule Atlas.Finance.Agents.PaymentDetectionAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Finance.Agents.PaymentDetectionAgent
  alias Atlas.Finance.Transaction

  @em_dash <<0x2014::utf8>>

  setup :verify_on_exit!

  test "instructs the agent to match carefully and ground funny copy in Tuist value" do
    prompt = PaymentDetectionAgent.system_prompt()

    assert prompt =~ "payment from a customer"
    assert prompt =~ "Never force a match"
    assert prompt =~ "funny, warm headline"
    assert prompt =~ "concrete value Tuist provides"
    assert prompt =~ "Never use em dashes"
    refute prompt =~ @em_dash
  end

  test "normalizes a matched result and removes em dashes from Slack copy" do
    account = %Account{id: Ecto.UUID.generate(), name: "Acme", segment: :customer}
    expect(Accounts, :get_account, fn account_id -> if account_id == account.id, do: account end)

    assert {:ok, result} =
             PaymentDetectionAgent.normalize_result(%{
               "status" => "matched",
               "account_id" => account.id,
               "confidence" => 0.94,
               "reason" => "Counterparty and account agree",
               "headline" => "Acme paid#{@em_dash}builds may now proceed",
               "body" => "Reliable builds#{@em_dash}reliably paid for."
             })

    assert result.status == "matched"
    assert result.account_id == account.id
    assert Decimal.equal?(result.confidence, Decimal.from_float(0.94))
    refute result.headline =~ @em_dash
    refute result.body =~ @em_dash
  end

  test "keeps an unmatched payment free of an account and celebration copy" do
    assert {:ok,
            %{
              status: "unmatched",
              account_id: nil,
              reason: "The payer is not identifiable"
            }} =
             PaymentDetectionAgent.normalize_result(%{
               "status" => "unmatched",
               "confidence" => 0.4,
               "reason" => "The payer is not identifiable"
             })
  end

  test "rejects a matched result below the confidence threshold" do
    account_id = Ecto.UUID.generate()

    assert {:error, :unexpected_result} =
             PaymentDetectionAgent.normalize_result(%{
               "status" => "matched",
               "account_id" => account_id,
               "confidence" => 0.79,
               "reason" => "Possible name overlap",
               "headline" => "Maybe money",
               "body" => "This match is not strong enough."
             })
  end

  test "bounds long transaction fields before sending them to the agent" do
    prompt =
      PaymentDetectionAgent.build_prompt(%Transaction{
        provider: "mercury",
        direction: "credit",
        status: "sent",
        kind: "incoming_transfer",
        counterparty_name: String.duplicate("c", 1_000),
        description: String.duplicate("d", 1_000),
        reference: String.duplicate("r", 1_000),
        amount_value: Decimal.new("30000.00"),
        amount_currency: "USD",
        settled_at: ~U[2026-07-15 14:00:00Z],
        metadata: %{
          "details" => String.duplicate("m", 2_000),
          "tracking_number" => String.duplicate("t", 2_000)
        }
      })

    assert prompt =~ "Counterparty: #{String.duplicate("c", 240)}\n"
    assert prompt =~ "Description: #{String.duplicate("d", 240)}\n"
    assert prompt =~ "Reference: #{String.duplicate("r", 240)}\n"
    assert prompt =~ "Provider metadata excerpt: {\"details\":\"#{String.duplicate("m", 160)}\"}"
    refute prompt =~ String.duplicate("m", 161)
    refute prompt =~ "tracking_number"
  end
end
