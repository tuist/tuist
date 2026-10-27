defmodule Atlas.Finance.PaymentCelebrationNotifierTest do
  use ExUnit.Case, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Finance.PaymentCelebrationNotifier
  alias Atlas.Finance.Transaction

  @em_dash <<0x2014::utf8>>

  test "builds a sales celebration from the agent copy and account context" do
    blocks =
      PaymentCelebrationNotifier.build_blocks(
        transaction_fixture(),
        account_fixture(),
        celebration_fixture()
      )

    rendered = inspect(blocks)

    assert hd(blocks)["type"] == "header"
    assert rendered =~ "Acme wired the money, the builds remain unwired"
    assert rendered =~ "Acme"
    assert rendered =~ "USD 30,000.00"
    assert rendered =~ "faster and more reliable build feedback"
    assert rendered =~ "View account"
    assert rendered =~ "Customer payment detected in Mercury"
    refute rendered =~ @em_dash
  end

  test "posts Block Kit to the configured sales channel" do
    parent = self()

    poster = fn app, channel, text, blocks ->
      send(parent, {:posted, app, channel, text, blocks})
      {:ok, %{"channel" => channel, "ts" => "1717400000.000100"}}
    end

    assert {:ok, %{channel_id: "C_SALES", ts: "1717400000.000100"}} =
             PaymentCelebrationNotifier.maybe_post(
               transaction_fixture(),
               account_fixture(),
               celebration_fixture(),
               finance_config: [sales_slack_channel_id: "C_SALES"],
               poster: poster
             )

    assert_received {:posted, :company, "C_SALES", text, blocks}
    assert text =~ "Acme"
    assert is_list(blocks)
    refute text =~ @em_dash
    refute inspect(blocks) =~ @em_dash
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

  defp account_fixture do
    %Account{id: Ecto.UUID.generate(), name: "Acme", segment: :customer}
  end

  defp celebration_fixture do
    %{
      headline: "Acme wired the money#{@em_dash}the builds remain unwired",
      body: "Here is to faster and more reliable build feedback#{@em_dash}and an invoice that passed on the first run."
    }
  end
end
