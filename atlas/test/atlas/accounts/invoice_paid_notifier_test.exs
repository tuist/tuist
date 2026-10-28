defmodule Atlas.Accounts.InvoicePaidNotifierTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Agents.InvoicePaidCelebrationAgent
  alias Atlas.Accounts.Invoice
  alias Atlas.Accounts.InvoicePaidNotifier
  alias Atlas.Slack.API

  @em_dash <<0x2014::utf8>>

  setup :verify_on_exit!

  setup do
    stub(InvoicePaidCelebrationAgent, :celebrate, fn _account, _invoice ->
      {:error, :llm_not_configured}
    end)

    :ok
  end

  describe "build_blocks/3" do
    test "renders the static fallback when no agent celebration is provided" do
      blocks = InvoicePaidNotifier.build_blocks(account_fixture(), invoice_fixture())
      rendered = inspect(blocks)

      assert hd(blocks)["text"]["text"] == "Payment received from Acme"
      assert rendered =~ "apple-touch-icon.png"
      assert rendered =~ "Celebrating customer payments as they land in Stripe."
      assert rendered =~ "Acme"
      assert rendered =~ "USD 30,000.00"
      assert rendered =~ "Huge thanks to everyone"
      assert rendered =~ "Invoice TUIST-8002"
      assert rendered =~ "Due 2026-03-01"
      assert rendered =~ "View invoice"
      assert rendered =~ "https://stripe.example/invoices/in_123"
      assert rendered =~ "Detected during Stripe invoice reconciliation."
    end

    test "uses the agent's headline and body when a celebration is provided" do
      celebration = %{
        headline: "Acme just made it rain",
        body: "Massive congrats to Maya and the deals team for closing this one."
      }

      blocks = InvoicePaidNotifier.build_blocks(account_fixture(), invoice_fixture(), celebration)
      rendered = inspect(blocks)

      assert hd(blocks)["text"]["text"] == "Acme just made it rain"
      assert rendered =~ "Massive congrats to Maya and the deals team"
      assert rendered =~ "USD 30,000.00"
      assert rendered =~ "Written by invoice_paid_celebration_agent"
      refute rendered =~ "Huge thanks to everyone"
      refute rendered =~ "Detected during Stripe invoice reconciliation."
    end

    test "renders without the action button when the invoice has no Stripe URL" do
      invoice = %{invoice_fixture() | stripe_url: nil}
      blocks = InvoicePaidNotifier.build_blocks(account_fixture(), invoice)
      rendered = inspect(blocks)

      refute rendered =~ "View invoice"
    end

    test "renders without the meta line when number and due date are missing" do
      invoice = %{invoice_fixture() | number: nil, due_date: nil}
      blocks = InvoicePaidNotifier.build_blocks(account_fixture(), invoice)
      rendered = inspect(blocks)

      refute rendered =~ "Invoice "
      refute rendered =~ "Due "
    end

    test "falls back to a generic customer name when the account name is blank" do
      account = %{account_fixture() | name: "   "}
      blocks = InvoicePaidNotifier.build_blocks(account, invoice_fixture())
      rendered = inspect(blocks)

      assert hd(blocks)["text"]["text"] == "Payment received from Customer"
      assert rendered =~ "Customer"
    end

    test "does not use any em dashes in the static fallback copy" do
      blocks = InvoicePaidNotifier.build_blocks(account_fixture(), invoice_fixture())
      refute inspect(blocks) =~ @em_dash
    end
  end

  describe "notify/2" do
    test "asks the celebration agent for copy and posts it to #sales" do
      account = account_fixture()
      invoice = invoice_fixture()
      test_pid = self()

      expect(InvoicePaidCelebrationAgent, :celebrate, fn called_account, called_invoice ->
        assert called_account.id == account.id
        assert called_invoice.external_id == invoice.external_id

        {:ok,
         %{
           headline: "Acme just paid us!",
           body: "Hat tip to the deals crew. Time to ring the bell."
         }}
      end)

      expect(API, :post_message, fn app_key, channel, text, blocks ->
        assert app_key == :company
        assert channel == "C072A0Z53B7"
        assert is_binary(text)
        assert is_list(blocks)
        send(test_pid, {:posted, text, blocks})
        {:ok, %{"ok" => true}}
      end)

      assert :ok = InvoicePaidNotifier.notify(account, invoice)

      assert_received {:posted, text, blocks}
      assert text =~ "Acme just paid us!"
      assert text =~ "USD 30,000.00"
      rendered = inspect(blocks)
      assert rendered =~ "Acme just paid us!"
      assert rendered =~ "Hat tip to the deals crew"
      assert rendered =~ "Written by invoice_paid_celebration_agent"
      refute text =~ @em_dash
      refute rendered =~ @em_dash
    end

    test "falls back to the static celebration when the agent fails" do
      account = account_fixture()
      invoice = invoice_fixture()
      test_pid = self()

      expect(InvoicePaidCelebrationAgent, :celebrate, fn _account, _invoice ->
        {:error, :llm_not_configured}
      end)

      expect(API, :post_message, fn :company, "C072A0Z53B7", text, blocks ->
        send(test_pid, {:posted, text, blocks})
        {:ok, %{"ok" => true}}
      end)

      log = ExUnit.CaptureLog.capture_log(fn -> assert :ok = InvoicePaidNotifier.notify(account, invoice) end)

      assert log =~ "InvoicePaidCelebrationAgent returned :llm_not_configured"
      assert_received {:posted, text, blocks}
      assert text =~ "Payment received from Acme"
      rendered = inspect(blocks)
      assert rendered =~ "Huge thanks to everyone"
      assert rendered =~ "Detected during Stripe invoice reconciliation."
    end

    test "returns the Slack error and logs when the API call fails" do
      expect(InvoicePaidCelebrationAgent, :celebrate, fn _account, _invoice ->
        {:error, :llm_not_configured}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          expect(API, :post_message, fn :company, "C072A0Z53B7", _text, _blocks ->
            {:error, :slack_down}
          end)

          assert {:error, :slack_down} = InvoicePaidNotifier.notify(account_fixture(), invoice_fixture())
        end)

      assert log =~ "Failed to post invoice paid celebration to Slack"
      assert log =~ "slack_down"
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
