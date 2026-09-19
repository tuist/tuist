defmodule TuistWeb.Webhooks.BillingControllerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Billing.Workers.CreateRunnerPrepaidGrantWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Webhooks.BillingController

  describe "handle_event/1 for customer.updated" do
    test "updates billing email when customer is found" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account

      event = %Stripe.Event{
        type: "customer.updated",
        data: %{
          object: %{
            id: account.customer_id,
            email: "new-billing-email@example.com"
          }
        }
      }

      assert :ok = BillingController.handle_event(event)

      {:ok, updated_account} = Accounts.get_account_by_id(account.id)
      assert updated_account.billing_email == "new-billing-email@example.com"
    end
  end

  describe "handle_event/1 for invoice.finalized" do
    defp invoice_event(type, invoice_id) do
      %Stripe.Event{type: type, data: %{object: %Stripe.Invoice{id: invoice_id}}}
    end

    # A renewal carrying standing prepaid minutes is finalized about an hour
    # after the period opens, however late it is later paid.
    test "enqueues the grant when an invoice is finalized" do
      invoice_id = "in_#{System.unique_integer([:positive])}"

      assert :ok = BillingController.handle_event(invoice_event("invoice.finalized", invoice_id))

      assert_enqueued(worker: CreateRunnerPrepaidGrantWorker, args: %{invoice_id: invoice_id})
    end

    test "does not enqueue a second grant when the finalized invoice is paid" do
      invoice_id = "in_#{System.unique_integer([:positive])}"

      assert :ok = BillingController.handle_event(invoice_event("invoice.finalized", invoice_id))
      assert :ok = BillingController.handle_event(invoice_event("invoice.paid", invoice_id))

      assert [_one] = all_enqueued(worker: CreateRunnerPrepaidGrantWorker)
    end
  end

  describe "handle_event/1 for invoice.paid" do
    defp invoice_paid do
      %Stripe.Event{
        type: "invoice.paid",
        data: %{object: %Stripe.Invoice{id: "in_#{System.unique_integer([:positive])}"}}
      }
    end

    # The payload carries at most the first handful of an invoice's
    # lines, so the controller cannot tell a prepaid invoice from an
    # ordinary one without truncating its view. It enqueues for every
    # paid invoice and lets the worker page the lines and decide.
    test "enqueues for every paid invoice, so a prepaid line further down a bill is not missed" do
      event = invoice_paid()

      assert :ok = BillingController.handle_event(event)

      assert_enqueued(worker: CreateRunnerPrepaidGrantWorker, args: %{invoice_id: event.data.object.id})
    end

    test "enqueues once per invoice however many times Stripe redelivers" do
      event = invoice_paid()

      assert :ok = BillingController.handle_event(event)
      assert :ok = BillingController.handle_event(event)

      assert [_one] = all_enqueued(worker: CreateRunnerPrepaidGrantWorker)
    end
  end
end
