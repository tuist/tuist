defmodule Atlas.Finance.PaymentDetectionTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Audit.Activity
  alias Atlas.Finance.Agents.PaymentDetectionAgent
  alias Atlas.Finance.PaymentCelebrationNotifier
  alias Atlas.Finance.PaymentDetection
  alias Atlas.Finance.Transaction

  setup :verify_on_exit!

  test "immediately notifies a confident customer payment match" do
    account = %Account{id: Ecto.UUID.generate(), name: "Acme", segment: :customer}
    transaction = transaction_fixture()

    detection = %{
      status: "matched",
      account_id: account.id,
      confidence: Decimal.new("0.96"),
      reason: "The bank counterparty matches Acme",
      headline: "Acme cleared the payment level",
      body: "Reliable builds unlocked, finance boss defeated."
    }

    expect(PaymentDetectionAgent, :run, fn ^transaction -> {:ok, detection} end)
    expect(Accounts, :get_account, fn account_id -> if account_id == account.id, do: account end)

    expect(PaymentCelebrationNotifier, :maybe_post, fn ^transaction, ^account, celebration ->
      assert celebration == Map.take(detection, [:headline, :body])
      {:ok, %{channel_id: "C_SALES", ts: "1717400000.000100"}}
    end)

    assert {:ok, "notified"} = PaymentDetection.review_and_notify(transaction)

    activity = Repo.get_by!(Activity, action: "finance.customer_payment.celebrated")
    assert activity.interface == "worker"
    assert activity.target_id == account.id
    assert activity.metadata["finance_transaction_id"] == transaction.id
    assert activity.metadata["path"] == "/sales/accounts/#{account.id}"
  end

  test "does not notify when the agent cannot match a likely payment" do
    transaction = transaction_fixture()

    expect(PaymentDetectionAgent, :run, fn ^transaction ->
      {:ok, %{status: "unmatched", account_id: nil, confidence: nil, reason: "Unknown payer"}}
    end)

    reject(&PaymentCelebrationNotifier.maybe_post/3)

    assert {:ok, "unmatched"} = PaymentDetection.review_and_notify(transaction)
    refute Repo.exists?(Activity)
  end

  test "does not ask the agent to review debits or internal transfers" do
    reject(&PaymentDetectionAgent.run/1)

    assert {:ok, "not_eligible"} =
             PaymentDetection.review_and_notify(%{transaction_fixture() | direction: "debit"})

    assert {:ok, "not_eligible"} =
             PaymentDetection.review_and_notify(%{transaction_fixture() | affects_runway: false})
  end

  defp transaction_fixture do
    %Transaction{
      id: Ecto.UUID.generate(),
      provider: "mercury",
      external_id: "txn-payment",
      direction: "credit",
      status: "sent",
      kind: "incoming_transfer",
      counterparty_name: "Acme International Ltd",
      amount_value: Decimal.new("30000.00"),
      amount_currency: "USD",
      settled_at: ~U[2026-07-15 14:00:00Z],
      affects_runway: true
    }
  end
end
