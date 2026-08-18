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

  describe "handle_event/1 for invoice.paid" do
    defp invoice_paid(metadata) do
      %Stripe.Event{
        type: "invoice.paid",
        data: %{object: %Stripe.Invoice{id: "in_#{System.unique_integer([:positive])}", metadata: metadata}}
      }
    end

    test "enqueues a grant for an invoice marked as prepaid runner credit" do
      event = invoice_paid(%{"tuist_prepaid_runners" => "true"})

      assert :ok = BillingController.handle_event(event)

      assert_enqueued(worker: CreateRunnerPrepaidGrantWorker, args: %{invoice_id: event.data.object.id})
    end

    test "enqueues for a malformed scope so the mistake surfaces as a failing job" do
      event = invoice_paid(%{"tuist_prepaid_runners" => "mac0s"})

      assert :ok = BillingController.handle_event(event)

      assert_enqueued(worker: CreateRunnerPrepaidGrantWorker, args: %{invoice_id: event.data.object.id})
    end

    test "ignores the subscription renewals that make up nearly every invoice.paid" do
      event = invoice_paid(%{})

      assert :ok = BillingController.handle_event(event)

      refute_enqueued(worker: CreateRunnerPrepaidGrantWorker)
    end
  end
end
